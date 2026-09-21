-- +micrate Up
ALTER TABLE posts ADD COLUMN title VARCHAR(120);
ALTER TABLE posts ADD COLUMN purge_enabled BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE posts SET purge_enabled = TRUE WHERE parent IS NULL AND lower(trim(message)) = 'spam';
CREATE INDEX posts_board_parent_activity ON posts (board, parent, updated_at DESC, id DESC);

-- +micrate Down
DROP INDEX posts_board_parent_activity;
ALTER TABLE posts DROP COLUMN purge_enabled;
ALTER TABLE posts DROP COLUMN title;
