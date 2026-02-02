-- Add unique constraint to prevent duplicate articles for same user+URL
-- First, delete duplicates keeping only the oldest one

DELETE FROM articles a
USING articles b
WHERE a.user_id = b.user_id
  AND a.url = b.url
  AND a.created_at > b.created_at;

-- Now add the unique constraint
ALTER TABLE articles ADD CONSTRAINT articles_user_url_unique UNIQUE (user_id, url);
