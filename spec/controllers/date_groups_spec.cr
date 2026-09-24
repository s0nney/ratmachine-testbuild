require "../spec_helper"

private def controller
  request = HTTP::Request.new("GET", "/", HTTP::Headers{"X-Forwarded-For" => "203.0.113.11"})
  IndexController.new(HTTP::Server::Context.new(request, HTTP::Server::Response.new(IO::Memory.new)))
end

private def dated(at : Time)
  post = Post.new
  post.updated_at = at
  post
end

# Granite's timestamps overwrite updated_at on save, so an older day has to be
# set behind its back.
private def backdate(post_id, at : Time)
  Post.exec("UPDATE posts SET updated_at = '#{at.to_s("%Y-%m-%d %H:%M:%S")}' WHERE id = #{post_id}")
end

private def page(path : String)
  request = HTTP::Request.new("GET", path, HTTP::Headers{"X-Forwarded-For" => "203.0.113.11"})
  IndexController.new(HTTP::Server::Context.new(request, HTTP::Server::Response.new(IO::Memory.new))).index.to_s
end

describe "Date grouping" do
  Spec.before_each { Post.clear }

  describe "#date_group" do
    it "names today with the weekday spelled out" do
      key, label = controller.date_group(dated(Time.utc))
      key.should eq(Time.utc.to_s("%Y-%m-%d"))
      label.should start_with("Today - ")
      label.should match(/Today - \w+day, \w+ \d{1,2}, \d{4}/)
    end

    it "names yesterday" do
      _, label = controller.date_group(dated(Time.utc - 1.day))
      label.should start_with("Yesterday - ")
    end

    it "gives an older day the date alone, with no prefix" do
      _, label = controller.date_group(dated(Time.utc(2026, 9, 21, 12, 0, 0)))
      label.should eq("Monday, September 21, 2026")
      label.should_not contain(" - ")
    end

    it "keys on the day, so two posts from one day share a group" do
      morning = controller.date_group(dated(Time.utc(2026, 9, 21, 1, 0, 0)))
      evening = controller.date_group(dated(Time.utc(2026, 9, 21, 23, 0, 0)))
      morning[0].should eq(evening[0])
    end

    # Grouping on creation would scatter the order: threads are sorted by last
    # activity, so a bumped thread has to move to the day it was bumped.
    it "groups on last activity rather than creation" do
      post = Post.new
      post.created_at = Time.utc(2026, 9, 21, 12, 0, 0)
      post.updated_at = Time.utc(2026, 9, 24, 12, 0, 0)
      controller.date_group(post)[0].should eq("2026-09-24")
    end
  end

  describe "rendering" do
    it "files a top-level thread under a date heading" do
      board = Post.create!(message: "grouped")
      Post.reply("a thread", nil, board.id.not_nil!.to_i32)
      html = page("/?board=grouped")
      html.should contain("class=\"post_group\"")
      html.should contain("id=\"group-#{Time.utc.to_s("%Y-%m-%d")}\"")
      html.should contain("Today - ")
    end

    it "counts the threads a day holds" do
      board = Post.create!(message: "grouped")
      2.times { |n| Post.reply("thread #{n}", nil, board.id.not_nil!.to_i32) }
      page("/?board=grouped").should contain("class=\"post_group_count\">2<")
    end

    # A board this long is why the grouping exists; leaving every day expanded
    # would put it right back.
    it "opens only the newest day" do
      board = Post.create!(message: "grouped")
      old_thread = Post.reply("old", nil, board.id.not_nil!.to_i32).not_nil!
      backdate(old_thread, Time.utc - 3.days)
      Post.reply("new", nil, board.id.not_nil!.to_i32)

      html = page("/?board=grouped")
      html.scan(/<details class="post_group"[^>]*>/).size.should eq(2)
      html.scan(/<details class="post_group"[^>]*\sopen/).size.should eq(1)
      # ...and it is the first one, which is the newest: threads are sorted
      # by last activity, so the newest day leads.
      html.should contain("id=\"group-#{Time.utc.to_s("%Y-%m-%d")}\" open")
    end

    # `open="false"` is still open; the attribute has to be absent.
    it "writes no open attribute at all on an older day" do
      board = Post.create!(message: "grouped")
      old_thread = Post.reply("old", nil, board.id.not_nil!.to_i32).not_nil!
      backdate(old_thread, Time.utc - 3.days)
      Post.reply("new", nil, board.id.not_nil!.to_i32)
      page("/?board=grouped").should_not contain("open=\"false\"")
    end

    # Nesting a date group inside every thread would bury the conversation it
    # is meant to organise.
    it "does not group replies, only top-level threads" do
      board = Post.create!(message: "grouped")
      root = Post.reply("root", nil, board.id.not_nil!.to_i32).not_nil!
      Post.reply("reply", nil, root.to_i32)
      page("/?board=grouped").scan(/class="post_group"/).size.should eq(1)
    end
  end
end
