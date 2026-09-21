-- +micrate Up
-- A board is a post with no parent; threads hang off it through the existing
-- parent column. `board` is a denormalised pointer to that root, so a post's
-- board is known in O(1) (needed for the per-board post cap).
ALTER TABLE posts ADD COLUMN board INT;

-- Every existing top-level post becomes a thread on a new default board.
-- The UPDATE cannot see the row the CTE inserts, so the new board keeps its
-- NULL parent and is not re-parented under itself.
WITH new_board AS (
  INSERT INTO posts (message, created_at, updated_at)
  VALUES ('general', NOW(), NOW())
  RETURNING id
)
UPDATE posts SET parent = (SELECT id FROM new_board) WHERE parent IS NULL;

-- Point every non-board post at that board.
UPDATE posts SET board = (SELECT id FROM posts WHERE parent IS NULL ORDER BY id ASC LIMIT 1)
WHERE parent IS NOT NULL;

CREATE INDEX posts_board_idx ON posts (board);

-- +micrate Down
DROP INDEX IF EXISTS posts_board_idx;
UPDATE posts SET parent = NULL WHERE parent IN (SELECT id FROM posts WHERE parent IS NULL);
DELETE FROM posts WHERE parent IS NULL AND message = 'general';
ALTER TABLE posts DROP COLUMN board;
