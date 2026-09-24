require "set"
require "../helpers/formatter_helper.cr"
require "../helpers/poster_id_helper.cr"
require "../core/live/event_log"
class Post < Granite::Base
  connection pg
  table posts

  column id : Int64, primary: true
  column parent : Int32?
  column board : Int32?
  column message : String
  column sage : Bool = false
  column ip_address : String?
  # Eight characters telling one poster from another; see PosterIdHelper.
  # Nil on a board row, which is a container rather than a message.
  column poster_id : String?
  column last_reply : Int32?
  timestamps

  def html
    FormatterHelper.format(self.message.as(String))
  end

  # Boards are the posts with no parent; every other post hangs off one.
  OVERBOARD_THREAD_LIMIT = 30

  # Ancestors are touched by reply(), so updated_at includes nested replies.
  def self.overboard_threads
    Post.all("WHERE parent = board ORDER BY updated_at DESC, GREATEST(id, COALESCE(last_reply, id)) DESC, id DESC LIMIT ?",
      [OVERBOARD_THREAD_LIMIT])
  end

  # Boards a mod may file a post into. An ordinary board that sits in the strip
  # with the rest; being a move target adds nothing but the destination.
  #
  # Archives was one of these, and a "system board" besides -- its own tab, and
  # read-only to everyone but mods. Both notions were taken out on 2026-09-21
  # along with pinning; there is no archive in this application.
  MOVE_TARGET_SLUGS = ["spam"]

  def self.move_target?(board : Post)
    MOVE_TARGET_SLUGS.includes?(board.message.to_s.strip.downcase)
  end

  # Re-home this post under another board, rewriting the denormalised board
  # pointer for the whole subtree -- every descendant carries one.
  def move_to_board(board : Post)
    old_board = self.board
    board_id = board.id.not_nil!.to_i32
    self.parent = board_id
    self.board = board_id
    save
    rewrite_board(board_id)
    Live::LOG.append(old_board, :reload, id.not_nil!) unless old_board.nil?
    Live::LOG.append(board_id, :reload, id.not_nil!)
  end

  def rewrite_board(board_id : Int32)
    Post.where(parent: id).each do |child|
      child.board = board_id
      child.save
      child.rewrite_board(board_id)
    end
  end

  def self.boards
    Post.where(parent: nil).order(created_at: :asc)
  end

  # Current threads and replies only; the board wrapper is not a post here.
  # Missing addresses do not represent a known unique IP.
  def board_stats
    posts = 0
    addresses = Set(String).new
    Post.where(board: id).each do |post|
      posts += 1
      address = post.ip_address
      unless address.nil? || address.strip.empty?
        addresses << address.strip
      end
    end
    {posts: posts, unique_ips: addresses.size}
  end

  def self.board?(post : Post)
    post.parent.nil?
  end

  # The board a new post will belong to. Its parent is either a board itself
  # or already carries a board pointer, so this never walks the tree.
  def self.board_for(parent_id : Int32 | Nil)
    return nil if parent_id.nil?
    parent = Post.find(parent_id)
    return nil if parent.nil?
    return parent.id.not_nil!.to_i32 if parent.parent.nil?
    parent.board
  end

  # The top-level post a given post belongs to -- the unit the client
  # re-renders. A post whose parent is the board is its own thread; anything
  # else climbs its ancestor chain (read-only) until it reaches one. Used for
  # a saged reply, whose ancestors the mutating walk in reply() never visits,
  # and for a post about to be purged, whose own thread may not be itself.
  def self.thread_id_for(post_id : Int32 | Int64 | Nil, board_id : Int32) : Int64?
    return nil if post_id.nil?
    current_id = post_id.to_i64
    loop do
      current = Post.find(current_id)
      return nil if current.nil?
      return current.id if current.parent == board_id
      parent_id = current.parent
      return nil if parent_id.nil?
      current_id = parent_id.to_i64
    end
  end

  def self.reply(message, ip_address : String | Nil, parent_id : Int32 | Nil = nil, sage : Bool = false)
    board_id = board_for(parent_id)
    # parent_id gets consumed by the ancestor walk below; keep the post's
    # actual, immediate parent around for the thread_id fallbacks.
    original_parent_id = parent_id

    post_to_delete : Post | Nil
    post_to_delete = nil

    # The cap is per board, so a busy board can't purge a quiet one. Boards
    # themselves carry no board pointer, so they are never purge candidates.
    unless board_id.nil?
      if Post.all("WHERE board = ?", [board_id]).size >= 254
        # Oldest first, and nothing is exempt: pinning used to hold a post out
        # of this and no longer exists.
        post_to_delete = Post.first("WHERE board = ? ORDER BY created_at ASC, id ASC", [board_id])
      end
    end

    # The ID is settled HERE, at the moment of posting, and never derived
    # again: it is made from the day, and a post keeps the identity it was made
    # with however long it sits there. A board row gets none.
    post = Post.create!(message: message, sage: sage, parent: parent_id, board: board_id, ip_address: ip_address,
      poster_id: board_id.nil? ? nil : PosterIdHelper.for(ip_address, board_id))
    post_id = post.id

    # Store the new reply ID on every ancestor. Reassigning an ancestor's own
    # ID can be a no-op, leaving updated_at stale after its first reply.
    #
    # This walk also climbs to the top-level thread post -- the unit the
    # client re-renders -- so capture it as we go: every ancestor whose own
    # parent isn't nil is a real post (not the board), so the last one
    # captured before the walk reaches the board is the thread.
    thread_id : Int64? = nil
    until parent_id.nil? || sage
      parent = Post.find!(parent_id)
      parent.update(last_reply: post_id.not_nil!.to_i32)
      thread_id = parent.id unless parent.parent.nil?
      parent_id = parent.parent
    end

    unless board_id.nil?
      if thread_id.nil?
        if original_parent_id == board_id
          # The new post's parent IS the board: this post is itself
          # top-level, so it IS the thread. Covers both a fresh top-level
          # post and a saged one -- sage never applies here since there is
          # no ancestor to skip notifying.
          thread_id = post_id
        else
          # sage skips the mutating walk above entirely (it must not bump
          # last_reply on ancestors), but a saged reply still belongs to a
          # thread.
          thread_id = thread_id_for(original_parent_id, board_id)
        end
      end

      Live::LOG.append(board_id, :created, post_id.not_nil!, thread_id || post_id)
    end

    post_to_delete.delete() unless post_to_delete.nil?
    post_id
  end

  def delete()
    owner = board
    thread = owner.nil? ? nil : Post.thread_id_for(id, owner)
    promoted = [] of Int64
    Post.where(parent: id).each { |child| promoted << child.id.not_nil! } if parent == owner
    orphan_children()
    destroy()
    unless owner.nil?
      Live::LOG.append(owner, :deleted, id.not_nil!, thread || id)
      promoted.each { |child_id| Live::LOG.append(owner, :promoted, child_id, child_id) }
    end
  end

  # Re-home children onto the deleted post's own parent rather than detaching
  # them. A NULL parent now means "this is a board", so the old behaviour of
  # setting parent to nil would silently promote replies into new boards.
  #https://github.com/faissaloo/ratmachine/issues/3
  def orphan_children()
    Post.where(parent: id).each do |post|
      post.parent = parent
      post.save
    end
  end

  # Deleting a board takes its threads with it; re-homing them is meaningless.
  # Every descendant carries this board's id, so one query finds them all.
  def delete_board()
    Post.where(board: id).each do |post|
      post.destroy
    end
    destroy()
  end

  def self.get_replies(parent : Post | Nil = nil)
    if parent.nil?
      Post.where(parent: nil).order(updated_at: :desc)
    else
      Post.where(parent: parent.id).order(updated_at: :desc)
    end
  end
end
