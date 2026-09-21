require "../spec_helper"

private def with_env(amber_env : String?, flag : String?)
  old_env = ENV["AMBER_ENV"]?
  old_flag = ENV["RATMACHINE_CAPTCHA_ENABLED"]?

  amber_env ? (ENV["AMBER_ENV"] = amber_env) : ENV.delete("AMBER_ENV")
  flag ? (ENV["RATMACHINE_CAPTCHA_ENABLED"] = flag) : ENV.delete("RATMACHINE_CAPTCHA_ENABLED")

  begin
    yield
  ensure
    old_env ? (ENV["AMBER_ENV"] = old_env) : ENV.delete("AMBER_ENV")
    old_flag ? (ENV["RATMACHINE_CAPTCHA_ENABLED"] = old_flag) : ENV.delete("RATMACHINE_CAPTCHA_ENABLED")
  end
end

describe CaptchaHelper do
  describe ".enabled?" do
    it "is off in development when unset" do
      with_env(nil, nil) { CaptchaHelper.enabled?.should be_false }
    end

    it "is off in test when unset" do
      with_env("test", nil) { CaptchaHelper.enabled?.should be_false }
    end

    it "is on in production when unset" do
      with_env("production", nil) { CaptchaHelper.enabled?.should be_true }
    end

    it "can be forced on in development" do
      with_env(nil, "true") { CaptchaHelper.enabled?.should be_true }
    end

    it "can be forced off in production" do
      with_env("production", "false") { CaptchaHelper.enabled?.should be_false }
    end

    it "accepts 1 and yes as truthy" do
      with_env(nil, "1") { CaptchaHelper.enabled?.should be_true }
      with_env(nil, "YES") { CaptchaHelper.enabled?.should be_true }
    end

    it "treats an unrecognised value as off" do
      with_env("production", "banana") { CaptchaHelper.enabled?.should be_false }
    end
  end

  describe ".captcha_form" do
    it "renders nothing when disabled" do
      with_env(nil, "false") { CaptchaHelper.captcha_form.should eq("") }
    end
  end
end
