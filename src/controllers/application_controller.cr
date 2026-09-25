require "jasper_helpers"

class ApplicationController < Amber::Controller::Base
  include JasperHelpers
  LAYOUT = "application.ecr"

  # A board is a post with no parent; its message is its name, and the slug is
  # that name reduced to something URL-safe.
  def board_slug(board : Post)
    board_slug(board.message.to_s)
  end

  def board_slug(name : String)
    name.strip.downcase.gsub(/[^a-z0-9]+/, "-").strip('-')
  end

  # The board strip: every board there is. There are no longer any the strip
  # holds back -- Archives was the only one, and it went with pinning.
  def boards_list
    boards = [] of Post
    Post.boards.each { |board| boards << board }
    boards
  end

  # Boards a mod may file a post into; ordinary boards that sit in the strip
  # with the rest.
  def move_targets_list
    boards = [] of Post
    Post.boards.each { |board| boards << board if Post.move_target?(board) }
    boards
  end

  def move_target(slug : String)
    move_targets_list.find { |board| board_slug(board) == slug }
  end

  # Every theme, in the order the drawer lists them. ONE list: the cookie
  # allow-list, the stylesheet path and the switcher labels all read it, so
  # adding a theme is a line here rather than three edits in two files that
  # can silently disagree.
  #
  # It is an allow-list, not a convenience. The cookie value goes into a
  # stylesheet path, so anything not named here must fall back rather than be
  # interpolated -- see theme_name.
  THEMES = [
    {name: "main", label: "Main"},
    {name: "cyb", label: "Cyb"},
    {name: "angelic", label: "Angelic"},
    {name: "macos", label: "MacOS"},
  ]

  # The cookie's value if it names a real theme, "main" otherwise.
  def self.theme_name(value : String?)
    THEMES.find { |theme| theme[:name] == value }.try(&.[](:name)) || "main"
  end

  def current_theme
    self.class.theme_name(cookies["theme_name"])
  end

  def get_theme()
    content(element_name: :link, options: {rel: "stylesheet", type: "text/css", href: "/dist/#{current_theme}.bundle.css"}.to_h) do
    end
  end
  
  @redirect_url : String | Nil

  def render_theme_switcher
    current = current_theme
    destination = HTTP::Params.encode({"return_to" => request.resource})
    content(element_name: :details, options: {class: "theme_switcher"}.to_h) do
      content(element_name: :summary, content: "", options: {:class => "theme_handle", :"aria-label" => "Themes", :title => "Themes"}) +
      content(element_name: :div, options: {class: "theme_drawer"}.to_h) do
        content(element_name: :div, content: "Appearance", options: {class: "theme_drawer_title"}.to_h) +
        THEMES.map do |theme|
          name = theme[:name]
          active = current == name ? " current_theme" : ""
          content(element_name: :a, content: theme[:label], options: {
            href: "/style/#{name}?#{destination}",
            class: "theme_choice theme_choice_#{name}#{active}"}.to_h).as(String)
        end.join
      end
    end
  end

  # Home again. The mod pages and the login screen are both outside the board
  # chrome -- no banner, no tabs -- so without this the only way back is the
  # browser's own back button or editing the URL.
  def render_home_link
    content(element_name: :a, content: "\u{2190} Back to the board",
      options: {href: "/", class: "back_link"}.to_h)
  end

  # --- live mode ------------------------------------------------------------
  # Off unless the cookie says otherwise, and the cookie is the ONLY thing that
  # decides. Nothing below ships when it is off: no script tag, no attributes,
  # no live CSS class. "Javascriptless" stays literally true by default, and
  # spec/controllers/live_mode_spec.cr asserts the absence rather than trusting
  # this comment.
  def live_enabled?
    cookies["live_mode"] == "on"
  end

  # The toggle is a plain link, so switching modes needs no JavaScript either
  # -- the same trick the theme switcher uses. Rendered in both the desktop
  # corner and the handheld nav bar; CSS shows whichever fits.
  def render_live_toggle(mobile = false)
    on = live_enabled?
    destination = HTTP::Params.encode({"return_to" => request.resource})
    classes = "live_toggle #{on ? "live_toggle_on" : "live_toggle_off"}"
    classes += " mobile_live_toggle" if mobile
    content(element_name: :a, content: "LIVE", options: {
      :href => "/live/#{on ? "off" : "on"}?#{destination}",
      :class => classes,
      :title => on ? "Live updates on -- click to turn off" : "Live updates off -- click to turn on",
      :"aria-pressed" => on.to_s}.to_h)
  end

  # The whole client side, and the only <script> this application ever emits.
  def live_runtime
    return "" unless live_enabled?
    "<script src=\"/js/live.js\" defer></script>"
  end

  # Which stream this page wants, as a body attribute. Absent entirely when
  # live mode is off or the page has nothing to update, which is also how
  # live.js decides whether to open a connection at all.
  def live_body_attribute
    scope = live_scope
    return "" if scope.nil?
    attributes = " data-live-scope=\"#{HTML.escape(scope)}\""
    reply = live_reply
    attributes += " data-live-reply=\"#{reply}\"" unless reply.nil?
    attributes
  end

  # nil means "not a live page". Overridden by IndexController; every other
  # controller -- the mod area, the redirects -- inherits nil.
  def live_scope : String?
    nil
  end

  # The post a reply page is pointed at. The stream needs it so a re-rendered
  # thread keeps `selected_post` on the right post rather than losing the
  # highlight the reader is looking at.
  def live_reply : Int32?
    nil
  end

  def redirector()
    "<meta http-equiv=\"REFRESH\" content=\"1;url=#{@redirect_url}\">" unless @redirect_url.nil?
  end

  def banner_board_tabs
    ""
  end

  def render_banner()
    content(element_name: :div, options: {class: "banner"}.to_h) do
      content(element_name: :h4, options: {id: "main info"}.to_h) do
        "Bitcoin: 1LseDRH9dywzfpW6vGpkaNYpQWSpaqwz44 " +
        content(element_name: :a, content: "TOR", options: {href: "http://6bjckqi7h3cm2bfseh63ukg5ptr77czwm53cfqv7gjwcm6bmvehaaeqd.onion/"}.to_h)
      end +
      content(element_name: :details, options: {id: "about_opener"}.to_h) do
        content(element_name: :summary, options: {id: "about_button"}.to_h) do
          "About"
        end +
        content(element_name: :p, options: {id: "about"}.to_h) do
          content(element_name: :a, content: "Ratwires", options: {href: "https://github.com/faissaloo/Ratmachine"}.to_h) +
            " is an anonymous AGPL'd javascriptless-by-default single board textboard inspired by " +
            content(element_name: :a, content: "Make Frontend Shit Again", options: {href: "https://makefrontendshitagain.party/"}.to_h) +
            " and " +
            content(element_name: :a, content: "2channel", options: {href: "https://5ch.net/"}.to_h) +
            " written in " +
            content(element_name: :a, content: "Crystal", options: {href: "https://crystal-lang.org"}.to_h) +
            " with the " +
            content(element_name: :a, content: "Amber Framework", options: {href: "https://github.com/amberframework/amber"}.to_h) +
            ". Boards automatically purge their oldest posts at the 254-post limit."
        end
      end + banner_board_tabs
    end
  end

  def guard(&block)
    token = authenticate_token

    unless token[:valid]
      return redirect_to("/mod/login")
    end
    yield token
  end

  def authenticate_token
    Injector.authenticate_token.call(token: request.cookies["session"]?)
  end
end
