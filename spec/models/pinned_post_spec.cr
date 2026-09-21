require "./spec_helper"

private def pinned_posts
  posts = [] of Post
  PinnedPost.posts.each { |post| posts << post }
  posts
end

describe PinnedPost do
  it "collects only pinned posts and allows unpinning without deleting them" do
    board = Post.create!(message: "general")
    root = Post.reply("root", nil, board.id.not_nil!.to_i32)
    reply = Post.reply("reply", nil, root.not_nil!.to_i32)
    pin = PinnedPost.create!(post_id: reply.not_nil!, pinned_by: "mod")
    pinned_posts.map(&.id).should eq([reply])
    pin.destroy
    pinned_posts.should be_empty
    Post.find(reply).should_not be_nil
  end

  it "removes a pin when the source post is deleted" do
    board = Post.create!(message: "general")
    id = Post.reply("post", nil, board.id.not_nil!.to_i32)
    PinnedPost.create!(post_id: id.not_nil!, pinned_by: "mod")
    Post.find!(id).delete
    PinnedPost.find_by(post_id: id).should be_nil
  end

  it "preserves pinned posts when a board reaches its post limit" do
    board = Post.create!(message: "general")
    first = Post.reply("pinned", nil, board.id.not_nil!.to_i32)
    PinnedPost.create!(post_id: first.not_nil!, pinned_by: "mod")
    254.times { |i| Post.reply("post #{i}", nil, board.id.not_nil!.to_i32) }
    Post.find(first).should_not be_nil
    Post.all("WHERE board = ?", [board.id]).size.should eq(254)
  end
end
