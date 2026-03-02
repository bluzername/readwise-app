-- ============================================
-- Query: Articles sent by users in the past 40 hours
-- Run this in the Supabase SQL Editor (https://supabase.com/dashboard)
-- ============================================

-- 1. All articles created in the past 40 hours (with user info)
SELECT
    a.id AS article_id,
    a.user_id,
    au.email AS user_email,
    a.url,
    a.title,
    a.site_name,
    a.author,
    a.status,
    a.created_at,
    a.read_at,
    a.is_archived
FROM public.articles a
LEFT JOIN auth.users au ON au.id = a.user_id
WHERE a.created_at >= NOW() - INTERVAL '40 hours'
ORDER BY a.created_at DESC;

-- 2. Summary: count of articles per user in the past 40 hours
SELECT
    a.user_id,
    au.email AS user_email,
    COUNT(*) AS article_count,
    COUNT(*) FILTER (WHERE a.status = 'ready') AS ready_count,
    COUNT(*) FILTER (WHERE a.status = 'pending') AS pending_count,
    COUNT(*) FILTER (WHERE a.status = 'failed') AS failed_count,
    MIN(a.created_at) AS earliest_article,
    MAX(a.created_at) AS latest_article
FROM public.articles a
LEFT JOIN auth.users au ON au.id = a.user_id
WHERE a.created_at >= NOW() - INTERVAL '40 hours'
GROUP BY a.user_id, au.email
ORDER BY article_count DESC;

-- 3. Processing queue status for recent articles
SELECT
    pq.id AS queue_id,
    pq.article_id,
    a.url,
    a.title,
    pq.job_type,
    pq.status AS queue_status,
    pq.attempts,
    pq.last_error,
    pq.created_at AS queued_at,
    pq.started_at,
    pq.completed_at
FROM public.processing_queue pq
JOIN public.articles a ON a.id = pq.article_id
WHERE a.created_at >= NOW() - INTERVAL '40 hours'
ORDER BY pq.created_at DESC;
