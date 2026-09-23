require "../spec_helper"
require "../../src/core/post_error"

describe PostError do
  describe ".code_for" do
    it "maps a known status to its code" do
      PostError.code_for("Incorrect or expired CAPTCHA").should eq("captcha")
      PostError.code_for("Message empty").should eq("empty")
      PostError.code_for("Message too long").should eq("long")
    end

    it "maps an unknown status to invalid rather than passing it through" do
      PostError.code_for("PG::Error: connection refused at 10.0.0.1").should eq("invalid")
    end

    it "is nil for no status" do
      PostError.code_for(nil).should be_nil
      PostError.code_for("").should be_nil
    end
  end

  describe ".message_for" do
    it "maps a code back to its message" do
      PostError.message_for("captcha").should eq("Incorrect or expired CAPTCHA")
    end

    it "renders nothing for a code it does not know" do
      PostError.message_for("<script>alert(1)</script>").should be_nil
      PostError.message_for("").should be_nil
      PostError.message_for(nil).should be_nil
    end
  end

  it "round-trips every message it can emit" do
    PostError::MESSAGES.each do |code, message|
      PostError.message_for(PostError.code_for(message)).should eq(message)
    end
  end
end
