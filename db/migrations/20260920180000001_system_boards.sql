-- +micrate Up
-- Archives and Spam are ordinary boards (posts with no parent); they are
-- singled out only by slug, so mods can move posts into them and they get
-- their own tabs rather than sitting in the normal board strip.
INSERT INTO posts (message, created_at, updated_at)
SELECT 'Archives', NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM posts WHERE parent IS NULL AND lower(message) = 'archives');

INSERT INTO posts (message, created_at, updated_at)
SELECT 'Spam', NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM posts WHERE parent IS NULL AND lower(message) = 'spam');

-- +micrate Down
DELETE FROM posts WHERE board IN (SELECT id FROM posts WHERE parent IS NULL AND lower(message) IN ('archives','spam'));
DELETE FROM posts WHERE parent IS NULL AND lower(message) IN ('archives','spam');
