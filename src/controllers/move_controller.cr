class MoveController < ApplicationController
  # Mod-only screens: same chrome-free layout as the rest of /mod.
  LAYOUT = "mod.ecr"

  @status_msg : String | Nil

  def manage
    guard do
      @status_msg = nil
      render("manage.ecr")
    end
  end

  # Send a post -- and everything filed under it -- to Spam.
  def create
    guard do
      post = find_post
      destination = move_target(params[:destination]?.to_s.strip.downcase)

      if post.nil?
        @status_msg = "No such post"
      elsif post.parent.nil?
        @status_msg = "That is a board, not a post"
      elsif destination.nil?
        @status_msg = "Choose a destination"
      elsif post.id == destination.id
        @status_msg = "A board can't be moved into itself"
      else
        moved = post.as(Post)
        moved.move_to_board(destination.as(Post))
        @status_msg = "Post #{moved.id} moved to #{destination.as(Post).message}"
      end

      render("manage.ecr")
    end
  end

  def find_post
    id = params[:post_id]?.to_s.to_i64?
    id.nil? ? nil : Post.find(id)
  end

  def render_move_form
    destinations = move_targets_list
    buttons = destinations.map do |board|
      form(action: "/move/create", method: "post") do
        csrf_tag() +
          text_field(:post_id, type: :number, placeholder: "post ID", value: params[:post_id]?) +
          hidden_field(:destination, value: board_slug(board)) +
          submit("Send to #{board.message}")
      end.as(String)
    end.join

    content(element_name: :div, options: {class: "panel"}.to_h) do
      content(element_name: :p, content: @status_msg.to_s, options: {class: "move_status"}.to_h) +
        buttons +
        destinations.map do |board|
          content(element_name: :a, content: "View #{board.message}", options: {
            href: "/b/#{board_slug(board)}"}.to_h).as(String) + " "
        end.join
    end
  end
end
