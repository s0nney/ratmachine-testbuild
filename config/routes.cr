Amber::Server.configure do
  pipeline :web do
    # Plug is the method to use connect a pipe (middleware)
    # A plug accepts an instance of HTTP::Handler
    plug Amber::Pipe::PoweredByAmber.new
    # plug Amber::Pipe::ClientIp.new(["X-Forwarded-For"])
    #plug Citrine::I18n::Handler.new
    #plug Amber::Pipe::Error.new
    # Name may contain a tripcode secret; redact it from request parameter logs.
    plug Amber::Pipe::Logger.new(filter: Amber.settings.logging.filter + ["name"])
    plug Amber::Pipe::Session.new
    plug Amber::Pipe::Flash.new
    plug Amber::Pipe::CSRF.new
  end

  pipeline :api do
    plug Amber::Pipe::PoweredByAmber.new
    #plug Amber::Pipe::Error.new
    plug Amber::Pipe::Logger.new
    plug Amber::Pipe::Session.new
    plug Amber::Pipe::CORS.new
  end

  # All static content will run these transformations
  pipeline :static do
    plug Amber::Pipe::PoweredByAmber.new
    #plug Amber::Pipe::Error.new
    plug Amber::Pipe::Static.new("./public")
  end

  routes :static do
    get "/robots.txt", Amber::Controller::Static, :index
    get "/favicon.ico", Amber::Controller::Static, :index
    get "/favicon.png", Amber::Controller::Static, :index
  end

  routes :web do
    delete "/post/delete", PostController, :delete
    delete "/filter/delete", FilterController, :delete

    get "/style/:name", ThemeController, :set
    
    get "/mod", ModController, :mod
    get "/mod/login", ModController, :login_page
    post "/mod/authenticate", ModController, :authenticate
    get "/mod/delete", ModController, :delete
    get "/mod/filter", ModController, :filter
    get "/mod/user", ModController, :user
    get "/mod/ban", ModController, :ban
    get "/mod/board", ModController, :board
    get "/mod/pin", PinController, :manage
    get "/mod/move", MoveController, :manage
    post "/move/create", MoveController, :create
    post "/mod/logout", ModController, :logout
    post "/pin/create", PinController, :create
    delete "/pin/delete", PinController, :delete

    post "/post/create/:id", PostController, :create
    post "/filter/create", FilterController, :create
    post "/post/create", PostController, :create

    post "/user/create", UserController, :create
    delete "/user/delete", UserController, :delete

    post "/board/create", BoardController, :create
    delete "/board/delete", BoardController, :delete

    post "/ban/create", BanController, :create
    delete "/ban/delete", BanController, :delete

    get "/b/:board", IndexController, :index
    get "/b/:board/:id", IndexController, :index

    get "/pinned", IndexController, :index
    get "/:id", IndexController, :index
    get "/", IndexController, :index
  end

  routes :static do
    get "/*", Amber::Controller::Static, :index
  end

  routes :api do
  end
end
