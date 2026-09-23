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

  def get_theme()
    theme_name = "main"
    theme_name = "cyb" if cookies["theme_name"] == "cyb"
    content(element_name: :link, options: {rel: "stylesheet", type: "text/css", href: "/dist/#{theme_name}.bundle.css"}.to_h) do
    end
  end
  
  @redirect_url : String | Nil

  def render_theme_switcher
    current = cookies["theme_name"] == "cyb" ? "cyb" : "main"
    destination = HTTP::Params.encode({"return_to" => request.resource})
    content(element_name: :details, options: {class: "theme_switcher"}.to_h) do
      content(element_name: :summary, content: "", options: {:class => "theme_handle", :"aria-label" => "Themes", :title => "Themes"}) +
      content(element_name: :div, options: {class: "theme_drawer"}.to_h) do
        content(element_name: :div, content: "Appearance", options: {class: "theme_drawer_title"}.to_h) +
        ["main", "cyb"].map do |name|
          active = current == name ? " current_theme" : ""
          label = name == "main" ? "Main" : "Cyb"
          content(element_name: :a, content: label, options: {
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
            " is an anonymous AGPL'd javascriptless single board textboard inspired by " +
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
