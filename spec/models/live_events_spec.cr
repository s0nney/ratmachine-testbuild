require "../spec_helper"
require "../../src/core/live/event_log"

describe "live events" do
  it "records the surviving thread when a nested purge victim rehomes children" do
    board = Post.create!(message: "purgeable")
    bid = board.id.not_nil!.to_i32
    victim = Post.reply("old reply", nil, bid).not_nil!
    root = Post.reply("root", nil, bid).not_nil!
    Post.find!(victim).update(parent: root.to_i32)
    child = Post.reply("child", nil, victim.to_i32).not_nil!
    251.times { Post.reply("filler", nil, bid) }
    seq = Live::LOG.current_seq(bid)
    Post.reply("purge", nil, bid)
    event = Live::LOG.since(bid, seq).as(Array(Live::Event)).find { |e| e.kind == :deleted }.not_nil!
    event.thread_id.should eq(root)
    event.post_id.should eq(victim)
    Post.find!(child).parent.should eq(root)
  end

  it "announces new top-level threads when a deleted root promotes its children" do
    board = Post.create!(message: "promotions")
    bid = board.id.not_nil!.to_i32
    root = Post.reply("root", nil, bid).not_nil!
    child = Post.reply("child", nil, root.to_i32).not_nil!
    seq = Live::LOG.current_seq(bid)
    Post.find!(root).delete
    events = Live::LOG.since(bid, seq).as(Array(Live::Event))
    events.any? { |e| e.kind == :promoted && e.thread_id == child }.should be_true
    Post.find!(child).parent.should eq(bid)
  end
  it "records a created post against its top-level thread" do
    board = Post.create!(message: "general")
    board_id = board.id.not_nil!.to_i32
    thread = Post.reply("thread", nil, board_id).not_nil!
    seq_before = Live::LOG.current_seq(board_id)
    reply = Post.reply("reply", nil, thread.to_i32).not_nil!

    events = Live::LOG.since(board_id, seq_before).as(Array(Live::Event))
    events.map(&.post_id).should contain(reply)
    events.find { |e| e.post_id == reply }.not_nil!.thread_id.should eq(thread)
  end

  it "records a saged reply against its top-level thread, not itself" do
    board = Post.create!(message: "general")
    board_id = board.id.not_nil!.to_i32
    thread = Post.reply("thread", nil, board_id).not_nil!
    nested = Post.reply("nested", nil, thread.to_i32).not_nil!
    seq_before = Live::LOG.current_seq(board_id)
    saged = Post.reply("saged reply", nil, nested.to_i32, true).not_nil!

    events = Live::LOG.since(board_id, seq_before).as(Array(Live::Event))
    event = events.find { |e| e.post_id == saged }.not_nil!
    event.thread_id.should eq(thread)
  end

  it "records a deletion when the purge removes a post" do
    # The cap is 254; make a board that is already at it, then post once more.
    board = Post.create!(message: "purgeable")
    board_id = board.id.not_nil!.to_i32
    oldest = Post.reply("oldest", nil, board_id).not_nil!
    253.times { |i| Post.reply("filler #{i}", nil, board_id) }
    seq_before = Live::LOG.current_seq(board_id)
    Post.reply("the one that purges", nil, board_id)

    events = Live::LOG.since(board_id, seq_before).as(Array(Live::Event))
    events.any? { |e| e.kind == :deleted && e.post_id == oldest }.should be_true
  end
end
