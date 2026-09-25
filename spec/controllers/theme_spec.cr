require "../spec_helper"

describe ThemeController do
  it "preserves board and reply destinations with query strings" do
    ThemeController.return_path("/b/tech/57?msg=hello%20world").should eq("/b/tech/57?msg=hello%20world")
    ThemeController.return_path("/b/general").should eq("/b/general")
    ThemeController.return_path("/mod/login").should eq("/mod/login")
  end

  it "defaults missing destinations to the overboard" do
    ThemeController.return_path(nil).should eq("/")
    ThemeController.return_path("").should eq("/")
  end

  it "rejects external and malformed redirect destinations" do
    ["https://example.com", "//example.com", "/\\example.com", "/b/general\r\nLocation: https://example.com"].each do |target|
      ThemeController.return_path(target).should eq("/")
    end
  end

  it "does not redirect into another theme action" do
    ThemeController.return_path("/style/main").should eq("/")
  end
end

# The cookie's value is interpolated into a stylesheet path, so anything not
# named in ApplicationController::THEMES has to fall back rather than pass
# through. One list now serves the cookie check, the <link> href and the
# switcher labels; these pin the check itself.
describe "Theme allow-list" do
  it "accepts every theme the switcher offers" do
    ApplicationController::THEMES.each do |theme|
      ApplicationController.theme_name(theme[:name]).should eq(theme[:name])
    end
  end

  it "falls back to main for anything else" do
    ApplicationController.theme_name(nil).should eq("main")
    ApplicationController.theme_name("").should eq("main")
    ApplicationController.theme_name("ANGELIC").should eq("main")
    ApplicationController.theme_name("../../etc/passwd").should eq("main")
    ApplicationController.theme_name("main.bundle.css").should eq("main")
  end

  it "offers angelic" do
    ApplicationController::THEMES.map { |theme| theme[:name] }.should contain("angelic")
  end
end
