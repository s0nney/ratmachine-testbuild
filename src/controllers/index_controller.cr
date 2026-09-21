require "../helpers/captcha/captcha"

class IndexController < ApplicationController
  @status_msg : String | Nil
  @heading_image : String | Nil
  @reply_to : Int32 | Nil
  @board : Post | Nil
  @overboard = false
  @pinned = false
  @boards = [] of Post

  def index
    @status_msg = ""
    @heading_image = ""
    @boards = boards_list
    @pinned = request.path == "/pinned"
    @overboard = !@pinned && params[:board]?.nil? && params[:id]?.nil?
    @board = resolve_board unless @overboard || @pinned
    id = params[:id]?
    unless id.nil?
      @reply_to = id.to_i
    end
    render("index.ecr")
  end

  # /b/:board picks a board by slug; anything else falls back to the first one.
  def resolve_board
    # Every board, system ones included: @boards is only the main strip, and a
    # /b/archives or /b/spam URL has to resolve too.
    boards = @boards + system_boards_list
    return nil if boards.empty?

    # Legacy /:id links must resolve the post's actual board.
    if params[:board]?.nil?
      if id = params[:id]?.to_s.to_i32?
        if post = Post.find(id)
          owner = boards.find { |board| board.id == post.board || board.id == post.id }
          return owner unless owner.nil?
        end
      end
    end
    slug = params[:board]?
    unless slug.nil?
      match = boards.find { |board| board_slug(board) == slug }
      return match unless match.nil?
    end
    @boards.empty? ? boards.first : @boards.first
  end

  # Distinct per strip: the desktop and mobile strips list the same boards, and
  # duplicate ids would send the anchor to whichever came first in the markup.
  def tab_anchor(board : Post, mobile : Bool)
    "#{mobile ? "mtab" : "tab"}-#{board_slug(board)}"
  end

  # Desktop dividers collapse; mobile board tabs use native horizontal swiping.
  def board_tabs(mobile = false)
    tabs = ""
    @boards.each do |board|
      current = @board
      active = !current.nil? && current.id == board.id
      tabs += board_tab(board.message.to_s, "/b/#{board_slug(board)}", active, mobile, "", tab_anchor(board, mobile))
    end
    content(element_name: :nav, options: {class: mobile ? "board_tabs mobile_board_tabs" : "board_tabs desktop_board_tabs"}.to_h) do
      tabs
    end
  end

  def mobile_navigation
    content(element_name: :nav, options: {class: "mobile_navigation"}.to_h) do
      board_tab("Overboard", "/", @overboard, true) +
        mobile_board_jump +
        system_board_tabs(true) +
        board_tab("Pinned", "/pinned", @pinned, true, " pinned_board_tab")
    end
  end

  def banner_board_tabs
    content(element_name: :nav, options: {
      class: "banner_board_tabs desktop_collection_tabs",
      "aria-label": "Default boards"}.to_h) do
      board_tab("Overboard", "/", @overboard, false) +
        system_board_tabs(false) +
        board_tab("Pinned", "/pinned", @pinned, false, " pinned_board_tab")
    end
  end

  # The same two jump targets, housed in the mobile bar instead of the screen
  # corners. Rendered unconditionally -- .mobile_navigation is display:none on
  # desktop, so this copy only ever shows on handheld. Sits between the two
  # tabs, which justify-content:space-between centres for us.
  def mobile_board_jump
    content(element_name: :div, options: {class: "mobile_board_jump"}.to_h) do
      content(element_name: :a, content: "", options: {
        href: "#board_top",
        class: "board_jump_button jump_up",
        title: "Jump to top"}.to_h) +
      content(element_name: :a, content: "", options: {
        href: "#board_bottom",
        class: "board_jump_button jump_down",
        title: "Jump to bottom"}.to_h)
    end
  end

  # Archives and Spam. Kept out of the main strip and rendered here so they sit
  # with Pinned at the right-hand end.
  def system_board_tabs(mobile : Bool)
    current = @board
    system_boards_list.map_with_index do |board, i|
      active = !current.nil? && current.id == board.id
      # Only the first of the group carries the auto margin that pushes the
      # whole group right; the rest must not, or they'd spread apart.
      start = i.zero? ? " right_group_start" : ""
      board_tab(board.message.to_s, "/b/#{board_slug(board)}", active, mobile, " system_board_tab#{start}").as(String)
    end.join
  end

  def board_tab(name : String, path : String, active : Bool, mobile : Bool, extra_class = "", anchor = "")
    extra_class += " utility_board_tab" if {"/", "/b/archives", "/pinned"}.includes?(path)
    active_class = active ? " active_board" : ""
    selected = active && @reply_to.nil? ? " selected_board" : ""
    label = content(element_name: mobile ? :div : :summary, options: {class: "board_tab_label"}.to_h) do
      link_options = {:href => path, :class => "board_tab_link"}
      link_options[:id] = anchor unless anchor.empty?
      content(element_name: :a, content: HTML.escape(name), options: link_options)
    end
    content(element_name: mobile ? :div : :details, options: {
      class: "board_tab#{active_class}#{selected}#{extra_class}", open: true}.to_h) do
      label
    end.as(String)
  end

  def is_selected_class(post : Post | Nil, is_root = false)
    if (@reply_to.nil? && (post.nil? || is_root)) || ((!post.nil?) && !is_root && @reply_to == post.id)
      " selected_post"
    else
      ""
    end
  end

  def render_main
    content(:div, options: {class: "board_container"}.to_h) do
      board_tabs() + (@pinned ? render_pinned : (@overboard ? render_overboard : render_thread(@board, true))) +
        content(element_name: :div, options: {class: "post_header collapsed_board_header"}.to_h) do
          collapsed_board_stats
        end
    end
  end

  # The jump anchors. They must sit inside the .root_post element, which is
  # the scroll container on handheld -- a fragment outside it cannot be
  # scrolled to. Zero-height spans, so they disturb no layout.
  def jump_anchor(which)
    content(element_name: :span, content: "", options: {id: "board_#{which}", class: "board_anchor"}.to_h)
  end

  # Jump rail: plain anchors to the two ends of the board container. Lives
  # outside that container so it can sit against the edge of the screen, and
  # needs no JS -- the browser's own fragment navigation does the scrolling.
  def board_jump
    content(element_name: :nav, options: {class: "board_jump"}.to_h) do
      content(element_name: :a, content: "", options: {
        href: "#board_top",
        class: "board_jump_button jump_up",
        title: "Jump to top"}.to_h) +
      content(element_name: :a, content: "", options: {
        href: "#board_bottom",
        class: "board_jump_button jump_down",
        title: "Jump to bottom"}.to_h)
    end
  end

  def render_overboard
    threads = [] of Post
    Post.overboard_threads.each { |post| threads << post }
    content(element_name: :div, options: {class: "post root_post selected_post overboard", id: "post-root"}.to_h) do
      jump_anchor("top") +
        (threads.empty? ? "<p class=\"overboard_empty\">No threads yet.</p>" : threads.map { |post| render_thread(post).as(String) }.join) +
        jump_anchor("bottom")
    end
  end

  def render_pinned
    posts = [] of Post
    PinnedPost.posts.each { |post| posts << post }
    content(element_name: :div, options: {class: "post root_post selected_post overboard", id: "post-root"}.to_h) do
      jump_anchor("top") +
        (posts.empty? ? "<p class=\"overboard_empty\">No pinned posts yet.</p>" : posts.map { |post| render_thread(post, false, false).as(String) }.join) +
        jump_anchor("bottom")
    end
  end

  def collapsed_board_stats
    board = @board
    return "Pinned posts selected by moderators" if @pinned
    return "Overboard · choose a board to post" if @overboard
    return "0 posts made with 0 identities" if board.nil?
    stats = board.board_stats
    post_label = stats[:posts] == 1 ? "post" : "posts"
    identity_label = stats[:unique_ips] == 1 ? "identity" : "identities"
    "#{stats[:posts]} #{post_label} made with #{stats[:unique_ips]} #{identity_label}"
  end

  # is_root marks the board itself, which frames the thread list rather than
  # appearing as a post of its own.
  def render_thread(parent : Post | Nil = nil, is_root = false, include_replies = true)
    root_class = is_root ? " root_post" : ""
    # Anchor on the <details> itself, so a backlink's :target highlights the
    # whole post. The <a id="reply-N"> anchors stay for the desktop links.
    post_anchor = "post-root"
    post_anchor = "post-#{parent.id}" unless parent.nil? || is_root
  	content(element_name: :details, options: {class: "post"+is_selected_class(parent, is_root)+root_class, id: post_anchor, open: true}.to_h) do
      mod_button = ""
      # Granite's query builder has no #to_a; collect explicitly so the
      # replies can be used twice (backlinks and recursion) on one query.
      replies = [] of Post
      Post.get_replies(parent).each { |reply| replies << reply } if include_replies
  		if parent.nil? || is_root
  			# The board tab strip stands in for this; see board_tabs.
  			post_button = ""
  		else
  			post_button = content(element_name: :a, content: "Reply", options: {
  				href: "#{board_path_for(parent)}/#{parent.id.to_s}#reply-#{parent.id.to_s}",
  				id: "reply-#{parent.id.to_s}" }.to_h) + " " +
				content(element_name: :span, options: {class: "post_meta"}.to_h) do
					parent.id.to_s + " " + check_digits(parent.id) + " " +
					parent.created_at.to_s + parent_backlink(parent) +
					(parent.parent == parent.board ? render_post_title(parent) : "")
				end

        if authenticate_token[:valid]
          mod_button = content(element_name: :a, content: "Mod", options: {
            href: "/mod?id=#{parent.id.to_s}&ip=#{parent.ip_address}",
            id: "mod-#{parent.id.to_s}"}.to_h)+" " +
            content(element_name: :a, content: "Pin / Unpin", options: {
              href: "/mod/pin?post_id=#{parent.id}"}.to_h) + " " +
            content(element_name: :a, content: "Archive", options: {
              href: "/mod/move?post_id=#{parent.id}&destination=archives",
              class: "mod_move_link"}.to_h) + " " +
            content(element_name: :a, content: "Spam", options: {
              href: "/mod/move?post_id=#{parent.id}&destination=spam",
              class: "mod_move_link"}.to_h) + " "
        end
  		end
  		post_content = content(element_name: :div, options: {class: "post_content"}.to_h) do
  			post_content_heading(parent, is_root) +
  			content(element_name: :p, options: {class: "post_text"}.to_h) do
  				parent.html unless parent.nil? || is_root
  			end + reply_backlinks(replies) + post_signature(parent, is_root)
  		end

  		child_posts = replies.map do |post|
  			render_thread(post).as(String)
  		end.join()

      # The jump anchors belong inside the root post: on handheld that element
      # is the scroll container, and a fragment outside it cannot be scrolled
      # to. Empty spans, zero height, so they disturb nothing.
      jump_top = is_root ? jump_anchor("top").as(String) : ""
      jump_bottom = is_root ? jump_anchor("bottom").as(String) : ""

      content(element_name: :summary, options: {class: "post_header"}.to_h) do
        (parent.nil? || is_root ? "" : render_post_identity(parent)) + mod_button + post_button
      end + jump_top + post_content + child_posts + jump_bottom
  	end
  end

  # THE HANDHELD LAYOUT PUTS THESE OVER AND UNDER THE MESSAGE, not in the
  # header: a phone's header row has no room for a title beside the number, the
  # date and the controls. Both are emitted for every post and hidden on the
  # desktop board, which is how the backlinks already work (see main.css) —
  # rendering them once and moving them with CSS is not possible, because the
  # header is a <summary> and the message is its sibling.

  # The board tag and the title, drawn above the message as "board: title".
  #
  # Either half can be missing and the colon goes with it: a thread moved to a
  # system board has no tag (those are not in @boards), and most posts have no
  # title at all.
  def post_content_heading(post : Post | Nil, is_root : Bool)
    return "" if post.nil? || is_root
    board = board_tag(post)
    title = render_post_title(post)
    return "" if board.empty? && title.empty?
    separator = board.empty? || title.empty? ? "" : content(
      element_name: :span, content: ":", options: {class: "thread_heading_separator"}.to_h).as(String)
    content(element_name: :div, options: {class: "post_content_heading"}.to_h) do
      board + separator + title
    end
  end

  # Who wrote it, signed off at the foot of the message: the name, the tripcode
  # and the sage flag, in the order the desktop header gives them.
  def post_signature(post : Post | Nil, is_root : Bool)
    return "" if post.nil? || is_root
    content(element_name: :div, options: {class: "post_signature"}.to_h) do
      content(element_name: :span, content: HTML.escape(post.author_name || "Anon"), options: {class: "post_author"}.to_h) +
        (post.tripcode.nil? ? "" : content(element_name: :span, content: "!#{post.tripcode.to_s[0, 10]}", options: {class: "post_tripcode"}.to_h).as(String)) +
        (post.sage ? content(element_name: :span, content: "sage", options: {class: "post_sage"}.to_h).as(String) : "")
    end
  end

  def render_post_identity(post : Post)
    content(element_name: :span, content: HTML.escape(post.author_name || "Anon"), options: {class: "post_author"}.to_h) + " " +
      (post.tripcode.nil? ? "" : content(element_name: :span, content: "!#{post.tripcode.to_s[0, 10]}", options: {class: "post_tripcode"}.to_h).as(String) + " ") +
      (post.sage ? "<span class=\"post_sage\">sage</span> " : "")
  end

  def render_post_title(post : Post)
    title = post.title.to_s.strip
    return "" if title.empty?
    content(element_name: :span, content: HTML.escape(title), options: {class: "thread_title_link"}.to_h)
  end

  # 4chan-style backlinks. Both are always rendered; only the handheld layout
  # displays them (main.css), since the desktop view shows the same
  # relationships through nesting instead.

  # ">>123" pointing at the post this one is replying to.
  # The board a thread sits on, as a tag. Pulled out of parent_backlink because
  # the handheld layout draws it a second time over the message, and two copies
  # built from two pieces of code drift apart.
  def board_tag(post : Post)
    return "" unless post.parent == post.board
    board = @boards.find { |item| item.id == post.board }
    return "" if board.nil?
    content(element_name: :a, content: HTML.escape(board.message.to_s), options: {
      href: "/b/#{board_slug(board)}", class: "thread_board"}.to_h)
  end

  def parent_backlink(post : Post)
    parent_id = post.parent
    return "" if parent_id.nil?
    if parent_id == post.board
      tag = board_tag(post)
      return tag.empty? ? "" : " " + tag
    end
    " " + content(element_name: :a, content: ">>#{parent_id}", options: {
      href: @pinned ? "#{board_path_for(post)}/#{parent_id}#post-#{parent_id}" : "#post-#{parent_id}",
      class: "backlink backlink_parent"}.to_h)
  end

  # ">>456 >>789" pointing at the posts that replied to this one.
  def reply_backlinks(replies : Array(Post))
    return "" if replies.empty?
    links = replies.map do |reply|
      content(element_name: :a, content: ">>#{reply.id}", options: {
        href: "#post-#{reply.id}",
        class: "backlink backlink_reply"}.to_h).as(String)
    end.join(" ")
    content(element_name: :div, options: {class: "backlinks"}.to_h) do
      links
    end
  end

  def check_digits(post_id : Int64 | Nil)
    unless post_id.nil?
      checked = Injector.check_digits.call(post_id: post_id)[:checked]
      return content(element_name: :span, content: "(x#{checked})", options: { class: "digit_check" }.to_h) if checked > 1
    end
    ""
  end

  def board_path_for(post : Post)
    board = (@boards + system_boards_list).find { |item| item.id == post.board }
    return "" if board.nil?
    "/b/#{board_slug(board)}"
  end

  # A top-level post on a board is a reply to the board post.
  def post_target
    board = @board
    return @reply_to unless @reply_to.nil?
    return nil if board.nil?
    board.id
  end

  def get_post_form_title()
    if @reply_to.nil?
      board = @board
      return HTML.escape(board.nil? ? "" : board.message.to_s) + " <br/>"
    end
    "Replying to post #{@reply_to} <br/>"
  end

  def render_post_form()
    content(element_name: :summary, options: {class: "form_heading"}.to_h) do
      get_post_form_title()
    end +
    content(element_name: :div, options: {class: "form_contents"}.to_h) do
  		form(action: "/post/create/#{@reply_to}", method: "post") do
        csrf_tag() +
        hidden_field(:parent, value: post_target) + "<br/>" +
        (@reply_to.nil? ? label(:title, "Title (optional):") + "<br/>" + text_field(:title, value: params[:title]?, maxlength: "120", class: "thread_title_input") + "<br/>" : "") +
        label(:name, "Name (optional):") + "<br/>" +
        text_field(:name, value: params[:name]?.to_s.split('#', 2)[0], placeholder: "Anonymous · Name#secret for tripcode", maxlength: "209", autocomplete: "off", class: "post_name_input") + "<br/>" +
        content(element_name: :label, options: {class: "sage_option"}.to_h) do
          "<input type=\"checkbox\" name=\"sage\" value=\"true\"#{params[:sage]? == "true" ? " checked" : ""}> Sage (do not bump)"
        end + "<br/>" +
        label(:msg, "Message:") + "<br/>" +
  			text_area(:msg, params[:msg]?, autofocus: "true") + "<br/>" +
        CaptchaHelper.captcha_form() +
  			submit("post")
  		end
    end
  end

  # The composer is pointless on Archives and Spam unless you can actually post
  # there; PostController enforces it regardless of what the view shows.
  def system_board_readonly?
    board = @board
    return false if board.nil?
    Post.system_board?(board) && !authenticate_token[:valid]
  end

  def render_post_container()
    composer = if @pinned
      content(element_name: :div, options: {class: "form overboard_prompt"}.to_h) do
        authenticate_token[:valid] ? content(element_name: :a, content: "Manage pins", options: {href: "/mod/pin"}.to_h) : "Pins selected by moderators"
      end
    elsif @overboard
      content(element_name: :div, options: {class: "form overboard_prompt"}.to_h) do
        "Choose a board to post"
      end
    elsif system_board_readonly?
      content(element_name: :div, options: {class: "form overboard_prompt"}.to_h) do
        "Moderators only"
      end
    elsif params[:msg]?.nil?
      content(element_name: :details, options: {class: "form"}.to_h) do
        render_post_form()
      end
    else
      content(element_name: :details, options: {class: "form", open: true}.to_h) do
        render_post_form()
      end
    end

    content(element_name: :div, options: {class: "posting_deck"}.to_h) do
      board_tabs(true) + composer
    end
  end
end
