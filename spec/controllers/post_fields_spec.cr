require "../spec_helper"

private def post_fields_context(path)
  HTTP::Server::Context.new(HTTP::Request.new("GET", path), HTTP::Server::Response.new(IO::Memory.new))
end

describe "Original board view with optional post fields" do
  it "renders all nested messages and safely displays titles, names, tripcodes and sage" do
    board = Post.create!(message: "general")
    root = Post.reply("first body", nil, board.id.not_nil!.to_i32, title: "<b>Title</b>", name: "<i>Alice</i>#secret")
    reply = Post.reply("nested body", nil, root.not_nil!.to_i32, sage: true)
    Post.reply("another root", nil, board.id.not_nil!.to_i32)
    page = IndexController.new(post_fields_context("/b/general?board=general&id=#{reply}")).index.to_s
    ["first body", "nested body", "another root", "&lt;b&gt;Title&lt;/b&gt;", "&lt;i&gt;Alice&lt;/i&gt;", "Anonymous", "post_tripcode", "post_sage"].each { |text| page.should contain(text) }
    page.should_not contain("<i>Alice</i>")
    page.should_not contain("thread_preview")
    page.should contain("name=\"name\"")
    page.should contain("name=\"sage\"")
    page.should_not contain("name=\"title\"")
    board_page = IndexController.new(post_fields_context("/b/general?board=general")).index.to_s
    board_page.should contain("name=\"title\"")
  end

  it "preserves safe failed-submission fields without putting the trip secret in a URL" do
    board = Post.create!(message: "general")
    query = HTTP::Params.encode({"parent" => board.id.to_s, "msg" => "body", "title" => "title", "name" => "Alice#private-test-secret", "sage" => "true"})
    html = PostController.new(post_fields_context("/post/create?#{query}")).render_redirect
    html.should contain("name=Alice")
    html.should contain("sage=true")
    html.should contain("title=title")
    html.should_not contain("private-test-secret")
  end

  it "restores the 1024-character message limit" do
    check = Usecase::CheckMessageSize.new
    check.call("x" * 1024)[:valid].should be_true
    check.call("x" * 1025)[:valid].should be_false
  end
end
