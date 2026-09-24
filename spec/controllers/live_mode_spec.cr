require "../spec_helper"

private def page(path : String, cookie : String? = nil)
  headers = HTTP::Headers{"X-Forwarded-For" => "203.0.113.9"}
  headers["Cookie"] = "live_mode=#{cookie}" unless cookie.nil?
  request = HTTP::Request.new("GET", path, headers)
  context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(IO::Memory.new))
  IndexController.new(context).index.to_s
end

describe "Live mode" do
  Spec.before_each { Post.clear }

  # The point of the toggle is that "off" ships nothing. These assert the
  # ABSENCE, which is the only kind of assertion that keeps it true: a stray
  # attribute added to the wrong branch is invisible in a browser and would
  # otherwise go unnoticed for months.
  describe "when off" do
    it "emits no script tag at all" do
      Post.create!(message: "quiet")
      html = page("/?board=quiet")
      html.should_not contain("<script")
      html.should_not contain("live.js")
    end

    it "gives the body no live scope, so the runtime has nothing to attach to" do
      Post.create!(message: "quiet")
      page("/?board=quiet").should_not contain("data-live-scope")
    end

    it "still renders the toggle, so live mode is reachable without JavaScript" do
      Post.create!(message: "quiet")
      html = page("/?board=quiet")
      html.should contain("live_toggle_off")
      html.should contain("/live/on?")
    end
  end

  describe "when on" do
    it "ships the runtime and names the board it should stream" do
      Post.create!(message: "loud")
      html = page("/?board=loud", "on")
      html.should contain("/js/live.js")
      html.should contain("data-live-scope=\"loud\"")
      html.should contain("live_toggle_on")
    end

    it "streams the whole overboard as an empty scope" do
      page("/", "on").should contain("data-live-scope=\"\"")
    end

    # A reply page renders the same board with one post selected, so it gets
    # the same stream -- plus the id of the selected post, without which a
    # re-rendered thread would lose the highlight the reader is looking at.
    it "streams a reply page and names the selected post" do
      board = Post.create!(message: "loud")
      root = Post.reply("root", nil, board.id.not_nil!.to_i32).not_nil!
      html = page("/?board=loud&id=#{root}", "on")
      html.should contain("data-live-scope=\"loud\"")
      html.should contain("data-live-reply=\"#{root}\"")
    end

    it "gives a board page no reply attribute, so the root stays selected" do
      Post.create!(message: "loud")
      page("/?board=loud", "on").should_not contain("data-live-reply")
    end

    it "does not treat an unrecognised cookie value as on" do
      Post.create!(message: "loud")
      page("/?board=loud", "yes").should_not contain("live.js")
    end
  end
end
