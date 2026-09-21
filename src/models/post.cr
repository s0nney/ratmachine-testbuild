require "set"
require "../helpers/formatter_helper.cr"
require "../helpers/tripcode_helper"
class Post < Granite::Base
  connection pg
  table posts

  column id : Int64, primary: true
  column parent : Int32?
  column board : Int32?
  column message : String
  column title : String?
  column author_name : String?
  column tripcode : String?
  column sage : Bool = false
  column ip_address : String?
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

  # Two separate ideas, deliberately not the same list:
  #   SYSTEM_BOARD_SLUGS -- gets its own tab at the right-hand end and is
  #                         read-only to everyone but mods.
  #   MOVE_TARGET_SLUGS  -- offered as a destination when a mod relocates a
  #                         post. Spam is an ordinary board that sits with the
  #                         rest, but mods can still file posts into it.
  SYSTEM_BOARD_SLUGS = ["archives"]
  MOVE_TARGET_SLUGS = ["archives", "spam"]

  def self.system_board?(board : Post)
    SYSTEM_BOARD_SLUGS.includes?(board.message.to_s.strip.downcase)
  end

  def self.move_target?(board : Post)
    MOVE_TARGET_SLUGS.includes?(board.message.to_s.strip.downcase)
  end

  # Re-home this post under another board, rewriting the denormalised board
  # pointer for the whole subtree -- every descendant carries one.
  def move_to_board(board : Post)
    board_id = board.id.not_nil!.to_i32
    self.parent = board_id
    self.board = board_id
    save
    rewrite_board(board_id)
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

  def self.reply(message, ip_address : String | Nil, parent_id : Int32 | Nil = nil, title : String? = nil, name : String? = nil, sage : Bool = false)
    board_id = board_for(parent_id)
    identity = TripcodeHelper.parse(name)
    thread_title = parent_id == board_id ? title.to_s.strip : ""
    raise ArgumentError.new("Title must be 120 characters or fewer") if thread_title.size > 120

    post_to_delete : Post | Nil
    post_to_delete = nil

    # The cap is per board, so a busy board can't purge a quiet one. Boards
    # themselves carry no board pointer, so they are never purge candidates.
    unless board_id.nil?
      if Post.all("WHERE board = ?", [board_id]).size >= 254
        post_to_delete = Post.first("WHERE board = ? AND NOT EXISTS (SELECT 1 FROM pinned_posts WHERE pinned_posts.post_id = posts.id) ORDER BY created_at ASC, id ASC", [board_id])
      end
    end

    post = Post.create!(message: message, title: thread_title.empty? ? nil : thread_title,
      author_name: identity[:name], tripcode: identity[:tripcode], sage: sage,
      parent: parent_id, board: board_id, ip_address: ip_address)
    post_id = post.id

    # Store the new reply ID on every ancestor. Reassigning an ancestor's own
    # ID can be a no-op, leaving updated_at stale after its first reply.
    until parent_id.nil? || sage
      parent = Post.find!(parent_id)
      parent.update(last_reply: post_id.not_nil!.to_i32)
      parent_id = parent.parent
    end

    post_to_delete.delete() unless post_to_delete.nil?
    post_id
  end

  def delete()
    orphan_children()
    destroy()
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
