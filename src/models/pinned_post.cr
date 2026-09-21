class PinnedPost < Granite::Base
  connection pg
  table pinned_posts

  column id : Int64, primary: true
  column post_id : Int64
  column pinned_by : String
  timestamps

  def self.posts
    Post.all("INNER JOIN pinned_posts ON pinned_posts.post_id = posts.id ORDER BY pinned_posts.created_at DESC, pinned_posts.id DESC")
  end
end
