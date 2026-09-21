require "./spec_helper"

private def overboard_threads
  posts = [] of Post
  Post.overboard_threads.each { |post| posts << post }
  posts
end

describe "Overboard threads" do
  it "combines board threads without including boards or nested replies" do
    general = Post.create!(message: "general")
    tech = Post.create!(message: "tech")
    first = Post.reply("first", nil, general.id.not_nil!.to_i32)
    second = Post.reply("second", nil, tech.id.not_nil!.to_i32)
    Post.reply("nested", nil, first.not_nil!.to_i32)

    overboard_threads.map(&.id).should eq([first, second])
  end

  it "limits the overboard to the 30 most recently active threads" do
    board = Post.create!(message: "general")
    ids = [] of Int64?
    32.times { |i| ids << Post.reply("thread #{i}", nil, board.id.not_nil!.to_i32) }
    overboard_threads.map(&.id).should eq(ids.reverse.first(30))
  end

  it "bumps the top-level thread when a nested reply receives a reply" do
    board = Post.create!(message: "general")
    older = Post.reply("older", nil, board.id.not_nil!.to_i32)
    nested = Post.reply("nested", nil, older.not_nil!.to_i32)
    newer = Post.reply("newer", nil, board.id.not_nil!.to_i32)
    overboard_threads.first.id.should eq(newer)
    Post.reply("deep reply", nil, nested.not_nil!.to_i32)
    overboard_threads.first.id.should eq(older)
  end
end
