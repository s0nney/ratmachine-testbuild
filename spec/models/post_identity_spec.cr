require "./spec_helper"

describe "Optional post identity and sage" do
  it "keeps titles and names optional and never titles nested replies" do
    board = Post.create!(message: "general")
    root = Post.reply("body", nil, board.id.not_nil!.to_i32)
    Post.find!(root).title.should be_nil
    Post.find!(root).author_name.should be_nil
    Post.find!(root).tripcode.should be_nil
    reply = Post.reply("reply", nil, root.not_nil!.to_i32, title: "ignored", name: "Alice")
    Post.find!(reply).title.should be_nil
    Post.find!(reply).author_name.should eq("Alice")
  end

  it "stores a title, display name, and stable tripcode without storing the secret" do
    board = Post.create!(message: "general")
    id = Post.reply("body", nil, board.id.not_nil!.to_i32, title: "  Optional title  ", name: "Alice#private-test-secret")
    post = Post.find!(id)
    post.title.should eq("Optional title")
    post.author_name.should eq("Alice")
    post.tripcode.should eq(TripcodeHelper.parse("Bob#private-test-secret")[:tripcode])
    post.tripcode.should_not eq(TripcodeHelper.parse("Alice#another-secret")[:tripcode])
    post.tripcode.not_nil!.size.should eq(10)
    post.tripcode.not_nil!.should_not contain("private-test-secret")
  end

  it "supports anonymous tripcodes and empty secrets" do
    TripcodeHelper.parse("#secret")[:name].should be_nil
    TripcodeHelper.parse("#secret")[:tripcode].should_not be_nil
    TripcodeHelper.parse("Alice#")[:tripcode].should be_nil
    TripcodeHelper.parse("   ")[:name].should be_nil
  end

  it "validates field lengths before creating a post" do
    board = Post.create!(message: "general")
    expect_raises(ArgumentError) { Post.reply("body", nil, board.id.not_nil!.to_i32, title: "x" * 121) }
    expect_raises(ArgumentError) { Post.reply("body", nil, board.id.not_nil!.to_i32, name: "x" * 81) }
    expect_raises(ArgumentError) { TripcodeHelper.parse("Alice#" + "x" * 129) }
    Post.all("WHERE board = ?", [board.id]).size.should eq(0)
  end

  it "leaves all ancestor activity unchanged for sage replies, then bumps normally" do
    board = Post.create!(message: "general")
    root = Post.reply("opening", nil, board.id.not_nil!.to_i32)
    nested = Post.reply("reply", nil, root.not_nil!.to_i32)
    newer = Post.reply("newer thread", nil, board.id.not_nil!.to_i32)
    ancestors = [board.id, root, nested].map { |id| Post.find!(id) }
    result = Injector.create_post.call(message: "quiet reply", parent: nested.not_nil!.to_i32, ip_address: nil, sage: true)
    Post.find!(result[:post_id]).sage.should be_true
    ancestors.each do |before|
      after = Post.find!(before.id)
      after.updated_at.should eq(before.updated_at)
      after.last_reply.should eq(before.last_reply)
    end
    Post.overboard_threads.first.id.should eq(newer)
    loud = Post.reply("bump", nil, nested.not_nil!.to_i32)
    Post.find!(root).last_reply.should eq(loud)
    Post.overboard_threads.first.id.should eq(root)
  end

  it "restores automatic purging to ordinary boards" do
    board = Post.create!(message: "general")
    first = Post.reply("oldest", nil, board.id.not_nil!.to_i32)
    254.times { |i| Post.reply("message #{i}", nil, board.id.not_nil!.to_i32, sage: true) }
    Post.find(first).should be_nil
    Post.all("WHERE board = ?", [board.id]).size.should eq(254)
  end
end
