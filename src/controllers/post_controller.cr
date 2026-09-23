require "uri"
require "../helpers/captcha/captcha"
require "../core/post_error"

class PostController < ApplicationController
  @status_msg : String | Nil

  def create()
    return redirect_to(refusal_path) unless check_captcha && check_message_size && check_filters

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
          sage: params[:sage]? == "true")
        @status_msg = post[:status]

        if post[:post_id].nil?
          redirect_to(refusal_path)
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

  # Post/Redirect/Get. A refused post goes straight back to the form it came
  # from, carrying what was typed and a code for why it was turned away. The
  # board reopens the composer whenever ?msg= is present and renders the
  # reason inside it, so there is no interstitial page and no meta refresh --
  # and reloading the board afterwards no longer resubmits the post.
  def refusal_path
    query = HTTP::Params.encode({
      "msg"   => params[:msg]?.to_s,
      "sage"  => params[:sage]?.to_s,
      "error" => PostError.code_for(@status_msg).to_s,
    })
    form_path + "?" + query
  end

  # Where the composer that produced this submission lives.
  def form_path
    parent = Post.find(params[:parent]?.to_s.to_i32?)
    return "/" if parent.nil?
    return "/b/#{board_slug(parent)}" if parent.parent.nil?
    "#{board_path_for(parent.id)}/#{parent.id}"
  end

  def check_message_size()
    filter_check = Injector.check_message_size.call(message: params[:msg])
    @status_msg = filter_check[:status]
    filter_check[:valid]
  end

  def check_filters()
    filter_check = Injector.check_filters.call(message: params[:msg])
    @status_msg = filter_check[:status]
    filter_check[:valid]
  end
end
