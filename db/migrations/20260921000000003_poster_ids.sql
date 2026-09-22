-- +micrate Up
-- Every post carries a poster ID: eight characters derived from the address it
-- was sent from, the board it was sent to, and the day. The board's own rows
-- (parent IS NULL) are containers rather than messages and carry none.
--
-- Stored rather than computed at render, and that is the whole reason this is
-- a column. The ID rotates daily, so deriving it again tomorrow would give a
-- different answer and yesterday's conversation would stop making sense; and
-- the address it came from may be cleared long before the post is.
ALTER TABLE posts ADD COLUMN poster_id VARCHAR(8);

-- +micrate Down
ALTER TABLE posts DROP COLUMN poster_id;
