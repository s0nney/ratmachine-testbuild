-- +micrate Up
-- Pinning and the Archives board are gone. Neither was finished, and both
-- carried weight through the purge, the tab strip, the mod panel and the
-- routes; they can come back as their own thing when they are wanted.
--
-- The board row goes with the table. Anything filed under Archives is re-homed
-- onto no board at all rather than deleted -- posts are not thrown away here,
-- and a mod can move them somewhere real.
UPDATE posts SET parent = NULL, board = NULL
 WHERE board IN (SELECT id FROM posts WHERE parent IS NULL AND lower(trim(message)) = 'archives');
DELETE FROM posts WHERE parent IS NULL AND lower(trim(message)) = 'archives';
DROP TABLE IF EXISTS pinned_posts;

-- +micrate Down
-- Exactly as 20260920000000002 created it, so a down-up round trip is a no-op.
CREATE TABLE IF NOT EXISTS pinned_posts (
  id BIGSERIAL PRIMARY KEY,
  post_id BIGINT NOT NULL UNIQUE REFERENCES posts(id) ON DELETE CASCADE,
  pinned_by VARCHAR NOT NULL,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
