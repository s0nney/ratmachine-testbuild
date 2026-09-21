require "../spec_helper"

describe ThemeController do
  it "preserves board and reply destinations with query strings" do
    ThemeController.return_path("/b/tech/57?msg=hello%20world").should eq("/b/tech/57?msg=hello%20world")
    ThemeController.return_path("/pinned").should eq("/pinned")
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
