require "uri"
require "../helpers/captcha/captcha"

class PostController < ApplicationController
  @status_msg : String | Nil

  def create()
    return render("create.ecr") unless check_system_board && check_captcha && check_message_size && check_filters

    # In case we're in a reverse proxy
    if request.headers["X-Forwarded-For"]?
      ip_address = request.headers["X-Forwarded-For"]
    else
      ip_address = request.remote_address
    end

    unless ip_address.nil?
      ip_address = ip_address.to_s.split(":").first

      if Ban.exists?(ip_address: ip_address)
        redirect_to("https://files.catbox.moe/glburl.mp4")
      else
        post = Injector.create_post.call(message: params[:msg], parent: params[:parent].to_i32?, ip_address: ip_address,
          title: params[:title]?, name: params[:name]?, sage: params[:sage]? == "true")
        @status_msg = post[:status]

        if post[:post_id].nil?
          render("create.ecr")
        else
          redirect_to("#{board_path_for(post[:post_id])}/#{post[:post_id]}#reply-#{post[:post_id]}")
        end
      end
    end
  end

  def delete()
    guard do
      @status_msg = Injector.delete_post.call(params[:post_id].to_i)[:status]
      @redirect_url = "/mod"
      render("delete.ecr")
    end
  end

  def check_captcha()
    return true unless CaptchaHelper.enabled?

    filter_check = Injector.check_captcha.call(captcha_id: params[:captcha_id], captcha_value: params[:captcha_value])
    @status_msg = filter_check[:status]
    filter_check[:valid]
  end

  # Archives and Spam are read-only to the public: anyone may browse them, only
  # an authenticated mod may post. Checked here rather than only in the view,
  # since the form can be submitted directly.
  def check_system_board
    parent_id = params[:parent]?.to_s.to_i32?
    return true if parent_id.nil?

    board_id = Post.board_for(parent_id)
    return true if board_id.nil?

    board = Post.find(board_id)
    return true if board.nil?
    return true unless Post.system_board?(board.as(Post))
    return true if authenticate_token[:valid]

    @status_msg = "Only moderators can post to #{board.as(Post).message}"
    false
  end

  # Posts carry their board id, so the redirect can land back on the board the
  # poster was actually looking at.
  def board_path_for(post_id)
    return "" if post_id.nil?
    post = Post.find(post_id)
    return "" if post.nil?
    board_id = post.board
    return "" if board_id.nil?
    board = Post.find(board_id)
    return "" if board.nil?
    "/b/#{board_slug(board)}"
  end

  def render_redirect()
    parent = Post.find(params[:parent]?.to_s.to_i32?)
    path = if parent.nil?
      "/"
    elsif parent.parent.nil?
      "/b/#{board_slug(parent)}"
    else
      "#{board_path_for(parent.id)}/#{parent.id}"
    end
    # A failed submission must never send the tripcode secret back in a URL.
    query = HTTP::Params.encode({"msg" => params[:msg]?.to_s, "title" => params[:title]?.to_s,
      "name" => params[:name]?.to_s.split('#', 2)[0], "sage" => params[:sage]?.to_s})
    "<meta http-equiv=\"REFRESH\" content=\"1;url=#{HTML.escape(path + "?" + query)}\">"
  end

  def check_message_size()
    filter_check = Injector.check_message_size.call(message: params[:msg])
    @status_msg = filter_check[:status]
    filter_check[:valid]
  end

  def check_filters()
    filter_check = Injector.check_filters.call(message: params[:msg])
    if filter_check[:valid] && !params[:title]?.to_s.empty?
      filter_check = Injector.check_filters.call(message: params[:title].to_s)
    end
    if filter_check[:valid]
      filter_check = Injector.check_filters.call(message: params[:name]?.to_s.split('#', 2)[0])
    end
    @status_msg = filter_check[:status]
    filter_check[:valid]
  end
end
