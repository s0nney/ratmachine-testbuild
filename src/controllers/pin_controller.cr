class PinController < ApplicationController
  @status_msg : String | Nil

  def manage
    guard do
      @status_msg = nil
      render("manage.ecr")
    end
  end

  def create
    guard do |token|
      post = find_post
      if post.nil? || post.parent.nil?
        @status_msg = "Choose an existing post, not a board"
      elsif PinnedPost.find_by(post_id: post.id)
        @status_msg = "Post is already pinned"
      else
        pin = PinnedPost.create(post_id: post.id.not_nil!, pinned_by: token[:username].to_s)
        @status_msg = pin.persisted? ? "Post pinned" : "Could not pin post"
      end
      render("manage.ecr")
    end
  end

  def delete
    guard do
      id = params[:post_id]?.to_s.to_i64?
      pin = id.nil? ? nil : PinnedPost.find_by(post_id: id)
      if pin.nil?
        @status_msg = "Post is not pinned"
      else
        pin.destroy
        @status_msg = "Post unpinned"
      end
      render("manage.ecr")
    end
  end

  def find_post
    id = params[:post_id]?.to_s.to_i64?
    id.nil? ? nil : Post.find(id)
  end

  def render_pin_form
    content(element_name: :div, options: {class: "panel"}.to_h) do
      content(element_name: :p, content: @status_msg.to_s, options: {class: "pin_status"}.to_h) +
      form(action: "/pin/create", method: "post") do
        csrf_tag() + text_field(:post_id, type: :number, placeholder: "post ID", value: params[:post_id]?) + submit("Pin post")
      end +
      form(action: "/pin/delete", method: "delete") do
        csrf_tag() + text_field(:post_id, type: :number, placeholder: "post ID", value: params[:post_id]?) + submit("Unpin post")
      end +
      content(element_name: :a, content: "View pinned posts", options: {href: "/pinned"}.to_h)
    end
  end
end
