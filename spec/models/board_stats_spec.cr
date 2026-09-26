require "./spec_helper"

private def stats_post(board : Post, at : Time, identity : String?, parent : Int32? = nil)
  post = Post.create!(message: "stats fixture", board: board.id.not_nil!.to_i32,
    parent: parent || board.id.not_nil!.to_i32, poster_id: identity)
  # Granite manages timestamps on save; set fixture times directly in the test DB.
  DB.open(Amber.settings.database_url) do |db|
    db.exec("UPDATE posts SET created_at = $1 WHERE id = $2", at, post.id)
  end
  post
end

describe "Hourly board statistics" do
  it "counts recent roots and replies, excluding the cutoff, future posts and other boards" do
    now = Time.utc(2026, 9, 25, 12)
    board = Post.create!(message: "stats")
    other = Post.create!(message: "other")
    root = stats_post(board, now - 59.minutes, "same")
    stats_post(board, now, "same", root.id.not_nil!.to_i32)
    stats_post(board, now - 1.minute, "second")
    stats_post(board, now - 1.hour, "expired")
    stats_post(board, now + 1.second, "future")
    stats_post(other, now, "other-id")
    board.board_stats(at: now).should eq({posts: 3, identities: 2})
    board.board_stats(at: now + 2.hours).should eq({posts: 0, identities: 0})
  end

  it "counts distinct stored identities across midnight" do
    now = Time.utc(2026, 9, 25, 0, 30)
    board = Post.create!(message: "stats")
    earlier = now - 45.minutes
    stats_post(board, earlier, PosterIdHelper.for("203.0.113.1", board.id, earlier))
    stats_post(board, now, PosterIdHelper.for("203.0.113.1", board.id, now))
    board.board_stats(at: now).should eq({posts: 2, identities: 2})
  end

  it "counts posts without inventing identities for missing IDs" do
    now = Time.utc(2026, 9, 25, 12)
    board = Post.create!(message: "stats")
    stats_post(board, now, nil)
    stats_post(board, now, "")
    board.board_stats(at: now).should eq({posts: 2, identities: 0})
  end
end
