-- +micrate Up
CREATE TABLE pinned_posts (
  id BIGSERIAL PRIMARY KEY,
  post_id BIGINT NOT NULL UNIQUE REFERENCES posts(id) ON DELETE CASCADE,
  pinned_by VARCHAR NOT NULL,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

-- +micrate Down
DROP TABLE IF EXISTS pinned_posts;
