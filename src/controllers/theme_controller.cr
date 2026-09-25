class ThemeController < ApplicationController
  def set
    # Validated against ApplicationController::THEMES rather than a list of
    # its own: the value ends up in a stylesheet path, and two allow-lists
    # that can drift is how a path-traversal hole gets reintroduced.
    response.cookies["theme_name"] = ApplicationController.theme_name(params[:name]?)
    redirect_to(self.class.return_path(params[:return_to]?))
  end

  # Theme links may return only to application pages, never an external URL
  # or another theme action. Query strings preserve a restored draft message.
  def self.return_path(target : String?)
    return "/" if target.nil? || target.includes?('\\') || target.includes?('\r') || target.includes?('\n')
    uri = URI.parse(target)
    return "/" unless uri.scheme.nil? && uri.host.nil?
    return "/" unless uri.path.matches?(/\A\/(?:b\/[a-z0-9-]+(?:\/[0-9]+)?|[0-9]+|mod(?:\/[a-z]+)?)?\z/)
    target
  rescue URI::Error
    "/"
  end
end
