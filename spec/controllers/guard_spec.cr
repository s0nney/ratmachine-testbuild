require "../spec_helper"

private def guard_context(cookie : String? = nil)
  headers = HTTP::Headers.new
  headers["Cookie"] = cookie unless cookie.nil?
  HTTP::Server::Context.new(HTTP::Request.new("POST", "/pin/create", headers), HTTP::Server::Response.new(IO::Memory.new))
end

describe "Moderator guard" do
  it "redirects anonymous users without executing the protected action" do
    context = guard_context
    ran = false
    ApplicationController.new(context).guard { ran = true }
    ran.should be_false
    context.response.headers["Location"].should eq("/mod/login")
  end

  it "rejects a malformed session without executing the protected action" do
    context = guard_context("session=not-a-token")
    ran = false
    ApplicationController.new(context).guard { ran = true }
    ran.should be_false
    context.response.headers["Location"].should eq("/mod/login")
  end

  it "executes the protected action for an authenticated moderator" do
    token = JWT.encode({username: "mod", privilege: :admin}, Authentication.secret, JWT::Algorithm::HS256)
    context = guard_context("session=#{token}")
    ran = false
    ApplicationController.new(context).guard { ran = true }
    ran.should be_true
  end
end
