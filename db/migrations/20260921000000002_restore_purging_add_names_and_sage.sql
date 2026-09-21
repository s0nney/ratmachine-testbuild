-- +micrate Up
ALTER TABLE posts DROP COLUMN purge_enabled;
DROP INDEX posts_board_parent_activity;
ALTER TABLE posts ADD COLUMN author_name VARCHAR(80);
ALTER TABLE posts ADD COLUMN tripcode VARCHAR(16);
ALTER TABLE posts ADD COLUMN sage BOOLEAN NOT NULL DEFAULT FALSE;

-- +micrate Down
ALTER TABLE posts DROP COLUMN sage;
ALTER TABLE posts DROP COLUMN tripcode;
ALTER TABLE posts DROP COLUMN author_name;
ALTER TABLE posts ADD COLUMN purge_enabled BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE posts SET purge_enabled = TRUE WHERE parent IS NULL AND lower(trim(message)) = 'spam';
CREATE INDEX posts_board_parent_activity ON posts (board, parent, updated_at DESC, id DESC);
