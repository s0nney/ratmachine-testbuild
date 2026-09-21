class BoardController < ApplicationController
  def create()
    guard do
      name = params[:board_name].to_s.strip
      slug = board_slug(name)

      if name.empty?
        @status_msg = "Board name can't be empty"
      elsif slug.empty?
        @status_msg = "Board name needs at least one letter or digit"
      elsif boards_list.any? { |board| board_slug(board) == slug }
        @status_msg = "A board called /#{slug}/ already exists"
      else
        # A board is just a post with no parent.
        Post.create(message: name)
        @status_msg = "Board /#{slug}/ created"
      end

      @redirect_url = "/mod"
      render("create.ecr")
    end
  end

  def delete()
    guard do
      board = Post.find(params[:board_id].to_i)

      if board.nil? || !board.parent.nil?
        @status_msg = "No such board"
      elsif boards_list.size <= 1
        @status_msg = "Can't delete the last board"
      else
        # Takes the board's threads with it.
        board.as(Post).delete_board()
        @status_msg = "Board deleted"
      end

      @redirect_url = "/mod"
      render("delete.ecr")
    end
  end
end
