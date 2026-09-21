class ThemeController < ApplicationController
  def set
    name = params[:name] == "cyb" ? "cyb" : "main"
    response.cookies["theme_name"] = name
    redirect_to(self.class.return_path(params[:return_to]?))
  end

  # Theme links may return only to application pages, never an external URL
  # or another theme action. Query strings preserve a restored draft message.
  def self.return_path(target : String?)
    return "/" if target.nil? || target.includes?('\\') || target.includes?('\r') || target.includes?('\n')
    uri = URI.parse(target)
    return "/" unless uri.scheme.nil? && uri.host.nil?
    return "/" unless uri.path.matches?(/\A\/(?:b\/[a-z0-9-]+(?:\/[0-9]+)?|pinned|[0-9]+|mod(?:\/[a-z]+)?)?\z/)
    target
  rescue URI::Error
    "/"
  end
end
