require "json"
require "./index_controller"
require "./theme_controller"

# Live mode: the cookie that turns it on, and the event stream that feeds it.
#
# PROTOTYPE. Server-Sent Events over a held connection, with the cursor kept
# HERE rather than round-tripped through the client -- which is the whole
# reason to prefer SSE over polling. The connection knows which board (or the
# overboard) it is watching and which threads the page currently shows, so the
# browser sends nothing after the initial request.
#
# In memory and single process, like the event log it reads.
class LiveController < IndexController
  # How often the stream looks at the log. This is not how often the client
  # polls -- the client never polls -- it is how stale an update can be.
  TICK = 0.4

  # EventSource reconnects on its own, so closing periodically costs nothing
  # and stops a forgotten tab from holding a fiber forever.
  MAX_LIFETIME = 10.minutes

  def toggle
    state = params[:state]? == "on" ? "on" : "off"
    response.cookies["live_mode"] = state
    redirect_to(ThemeController.return_path(params[:return_to]?))
  end

  def feed
    scope = params[:board]?.to_s
    @overboard = scope.empty? || scope == "overboard"
    @boards = boards_list
    board = @overboard ? nil : @boards.find { |item| board_slug(item) == scope }

    if !@overboard && board.nil?
      response.status_code = 404
      return "No such board"
    end
    @board = board
    # A reply page is the same board with one post marked selected. Carrying
    # it here keeps the highlight through a re-render; anything unparseable is
    # simply no selection.
    @reply_to = params[:reply]?.to_s.to_i32?

    response.content_type = "text/event-stream"
    response.headers["Cache-Control"] = "no-store"
    # nginx buffers proxied responses by default, which would hold every event
    # until the connection closed -- i.e. break this entirely, silently.
    response.headers["X-Accel-Buffering"] = "no"

    cursors = start_cursors(board)
    known = start_known(board)
    stats = collapsed_board_stats
    deadline = Time.monotonic + MAX_LIFETIME
    next_stats_check = Time.monotonic + 30.seconds

    send_event(%({"hello":true}))

    while Time.monotonic < deadline
      payload = changes_since(board, cursors, known, stats)
      unless payload.nil?
        stats = payload[:stats]
        send_event(payload[:json])
      end
      # Hourly counts can decrease even when no new posts arrive.
      if Time.monotonic >= next_stats_check
        fresh_stats = collapsed_board_stats
        if fresh_stats != stats
          stats = fresh_stats
          send_event({stats: stats}.to_json)
        end
        next_stats_check = Time.monotonic + 30.seconds
      end
      sleep TICK
    end
    ""
  rescue IO::Error
    # The reader closed the tab. Not an error worth logging.
    ""
  end

  private def send_event(json : String)
    response.print("data: ")
    response.print(json)
    response.print("\n\n")
    response.flush
  end

  # Where each watched board's log stands right now. Starting from the current
  # sequence rather than zero means the stream reports only what happens from
  # here on; the page the reader is looking at already has everything else.
  private def start_cursors(board : Post | Nil) : Hash(Int32, Int64)
    cursors = {} of Int32 => Int64
    watched_boards(board).each do |item|
      id = item.id.not_nil!.to_i32
      cursors[id] = Live::LOG.current_seq(id)
    end
    cursors
  end

  # The threads the rendered page is showing, so the stream can tell an update
  # from an arrival without asking the browser.
  private def start_known(board : Post | Nil) : Set(Int64)
    current_thread_ids(board).to_set
  end

  private def watched_boards(board : Post | Nil) : Array(Post)
    board.nil? ? @boards : [board]
  end

  private def current_thread_ids(board : Post | Nil) : Array(Int64)
    ids = [] of Int64
    if board.nil?
      Post.overboard_threads.each { |post| ids << post.id.not_nil! }
    else
      board_id = board.id.not_nil!.to_i32
      Post.get_replies(board).each { |post| ids << post.id.not_nil! if post.board == board_id }
    end
    ids
  end

  # One tick. Returns nil when nothing happened, which is the common case and
  # costs one mutex and one array lookup per watched board -- no database.
  private def changes_since(board, cursors, known, stats)
    fresh = [] of Live::Event
    reload = false
    cursors.each do |board_id, seq|
      events = Live::LOG.since(board_id, seq)
      if events == :reload
        reload = true
        next
      end
      changes = events.as(Array(Live::Event))
      next if changes.empty?
      cursors[board_id] = changes.last.seq
      fresh.concat(changes)
    end

    return {json: %({"reload":true}), stats: stats} if reload
    return nil if fresh.empty?

    removed = [] of Int64
    inserted = [] of NamedTuple(id: Int64, html: String)
    replaced = [] of NamedTuple(id: Int64, html: String)

    visible = current_thread_ids(board)
    visible_set = visible.to_set

    # Anything the page is showing that no longer belongs -- purged, or pushed
    # off the overboard's cutoff by somebody else's post.
    known.each { |id| removed << id unless visible_set.includes?(id) }
    removed.each { |id| known.delete(id) }

    touched = fresh.map(&.thread_id).uniq
    touched.each do |id|
      next unless visible_set.includes?(id)
      thread = Post.find(id)
      next if thread.nil?
      html = render_thread(thread).as(String)
      if known.includes?(id)
        replaced << {id: id, html: html}
      else
        inserted << {id: id, html: html}
        known << id
      end
    end

    fresh_stats = collapsed_board_stats
    payload = {
      remove:  removed,
      replace: replaced,
      insert:  inserted,
      order:   visible,
      stats:   fresh_stats,
    }
    {json: payload.to_json, stats: fresh_stats}
  end
end
