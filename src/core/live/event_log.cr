# The record of what has happened on each board, so a polling client can be
# told what changed without re-reading the whole board.
#
# IN MEMORY AND SINGLE PROCESS, like everything else about this experiment.
# Two server instances would each see half the events and neither would report
# it; this type is the seam if that ever changes.
require "random/secure"

module Live
  # Sequence numbers alone cannot distinguish a restarted server.
  EPOCH = Random::Secure.hex(16)
  # A post was created, a post was deleted by the purge, or a thread's contents
  # changed. `thread_id` is the TOP-LEVEL post the change belongs to, which is
  # the unit the client re-renders.
  record Event, seq : Int64, kind : Symbol, post_id : Int64, thread_id : Int64

  class EventLog
    # Three minutes of a busy board at one post a second. A client that falls
    # further behind than this is told to reload, which is cheaper than keeping
    # an unbounded history for a tab nobody is looking at.
    DEFAULT_CAPACITY = 200

    def initialize(@capacity : Int32 = DEFAULT_CAPACITY)
      @mutex = Mutex.new
      @boards = {} of Int64 => Array(Event)
      @seqs = {} of Int64 => Int64
    end

    def append(board_id, kind : Symbol, post_id, thread_id = nil) : Int64
      board = board_id.to_i64
      @mutex.synchronize do
        seq = (@seqs[board]? || 0_i64) + 1
        @seqs[board] = seq
        events = @boards[board] ||= [] of Event
        events << Event.new(seq, kind, post_id.to_i64, (thread_id || post_id).to_i64)
        while events.size > @capacity
          events.shift
        end
        seq
      end
    end

    def current_seq(board_id) : Int64
      @mutex.synchronize { @seqs[board_id.to_i64]? || 0_i64 }
    end

    # Events after `seq`, or :reload when the caller is too far behind to be
    # brought up to date. An unknown board is empty, not a reload: a board
    # nobody has posted to since the server started has no history to miss.
    def since(board_id, seq) : Array(Event) | Symbol
      board = board_id.to_i64
      want = seq.to_i64
      @mutex.synchronize do
        return :reload if want < 0 || want > (@seqs[board]? || 0_i64)
        events = @boards[board]?
        return [] of Event if events.nil? || events.empty?
        oldest = events.first.seq
        return :reload if want < oldest - 1
        events.select { |event| event.seq > want }
      end
    end
  end

  # One log for the process.
  LOG = EventLog.new
end
