-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ============================================
-- ARTICLES TABLE
-- ============================================
create table if not exists articles (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users not null,
  url text not null,
  title text,
  description text,
  content text,
  image_url text,
  site_name text,
  author text,
  images jsonb default '[]'::jsonb,
  comments jsonb default '[]'::jsonb,
  analysis jsonb,
  status text default 'pending' check (status in ('pending', 'extracting', 'analyzing', 'ready', 'failed')),
  created_at timestamptz default now(),
  read_at timestamptz,
  is_archived boolean default false
);

-- Index for faster queries
create index if not exists articles_user_id_idx on articles(user_id);
create index if not exists articles_created_at_idx on articles(created_at desc);
create index if not exists articles_status_idx on articles(status);

-- RLS for articles
alter table articles enable row level security;

drop policy if exists "Users can view own articles" on articles;
create policy "Users can view own articles" on articles
  for select using (auth.uid() = user_id);

drop policy if exists "Users can insert own articles" on articles;
create policy "Users can insert own articles" on articles
  for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own articles" on articles;
create policy "Users can update own articles" on articles
  for update using (auth.uid() = user_id);

drop policy if exists "Users can delete own articles" on articles;
create policy "Users can delete own articles" on articles
  for delete using (auth.uid() = user_id);

-- ============================================
-- DIGESTS TABLE
-- ============================================
create table if not exists digests (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users not null,
  date date not null,
  overall_summary text not null,
  top_themes jsonb default '[]'::jsonb,
  articles jsonb default '[]'::jsonb,
  ai_insights text,
  created_at timestamptz default now(),
  is_read boolean default false,

  unique(user_id, date)
);

-- Index for faster queries
create index if not exists digests_user_id_idx on digests(user_id);
create index if not exists digests_date_idx on digests(date desc);

-- RLS for digests
alter table digests enable row level security;

drop policy if exists "Users can view own digests" on digests;
create policy "Users can view own digests" on digests
  for select using (auth.uid() = user_id);

drop policy if exists "Users can insert own digests" on digests;
create policy "Users can insert own digests" on digests
  for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own digests" on digests;
create policy "Users can update own digests" on digests
  for update using (auth.uid() = user_id);

drop policy if exists "Users can delete own digests" on digests;
create policy "Users can delete own digests" on digests
  for delete using (auth.uid() = user_id);

-- ============================================
-- USER SETTINGS TABLE
-- ============================================
create table if not exists user_settings (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users not null unique,
  digest_time time default '08:00:00',
  timezone text default 'America/Los_Angeles',
  analyze_images boolean default true,
  include_comments boolean default true,
  push_notifications boolean default true,
  fcm_token text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Index for faster queries
create index if not exists user_settings_user_id_idx on user_settings(user_id);

-- RLS for user_settings
alter table user_settings enable row level security;

drop policy if exists "Users can view own settings" on user_settings;
create policy "Users can view own settings" on user_settings
  for select using (auth.uid() = user_id);

drop policy if exists "Users can insert own settings" on user_settings;
create policy "Users can insert own settings" on user_settings
  for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own settings" on user_settings;
create policy "Users can update own settings" on user_settings
  for update using (auth.uid() = user_id);

-- ============================================
-- SERVICE ROLE POLICIES (for Edge Functions)
-- ============================================
-- Allow service role to update articles (for extraction/analysis)
drop policy if exists "Service role can update all articles" on articles;
create policy "Service role can update all articles" on articles
  for update using (auth.jwt()->>'role' = 'service_role');

drop policy if exists "Service role can insert digests" on digests;
create policy "Service role can insert digests" on digests
  for insert with check (auth.jwt()->>'role' = 'service_role');

-- ============================================
-- REALTIME SUBSCRIPTIONS
-- ============================================
alter publication supabase_realtime add table articles;
alter publication supabase_realtime add table digests;
alter publication supabase_realtime add table user_settings;
