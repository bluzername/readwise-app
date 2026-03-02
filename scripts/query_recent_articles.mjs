#!/usr/bin/env node

/**
 * Query recent articles sent by users in the past 40 hours.
 *
 * Usage:
 *   SUPABASE_SERVICE_ROLE_KEY=your_key node scripts/query_recent_articles.mjs
 *
 * Or set the env var in your shell:
 *   export SUPABASE_SERVICE_ROLE_KEY=your_key
 *   node scripts/query_recent_articles.mjs
 */

const SUPABASE_URL = 'https://bioiacixxauufpvswlxe.supabase.co';
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SERVICE_ROLE_KEY) {
  console.error('Error: SUPABASE_SERVICE_ROLE_KEY environment variable is required.');
  console.error('Usage: SUPABASE_SERVICE_ROLE_KEY=your_key node scripts/query_recent_articles.mjs');
  process.exit(1);
}

const FORTY_HOURS_AGO = new Date(Date.now() - 40 * 60 * 60 * 1000).toISOString();

async function queryArticles() {
  console.log(`\nSearching for articles created since: ${FORTY_HOURS_AGO}\n`);

  const url = new URL(`${SUPABASE_URL}/rest/v1/articles`);
  url.searchParams.set('select', 'id,user_id,url,title,site_name,author,status,created_at,read_at,is_archived');
  url.searchParams.set('created_at', `gte.${FORTY_HOURS_AGO}`);
  url.searchParams.set('order', 'created_at.desc');

  const response = await fetch(url.toString(), {
    headers: {
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error(`API Error (${response.status}): ${errorText}`);
    process.exit(1);
  }

  const articles = await response.json();

  if (articles.length === 0) {
    console.log('No articles found in the past 40 hours.');
    return;
  }

  console.log(`Found ${articles.length} article(s) in the past 40 hours:\n`);
  console.log('='.repeat(100));

  for (const article of articles) {
    console.log(`  Article ID:  ${article.id}`);
    console.log(`  User ID:     ${article.user_id}`);
    console.log(`  URL:         ${article.url}`);
    console.log(`  Title:       ${article.title || '(no title yet)'}`);
    console.log(`  Site:        ${article.site_name || '(unknown)'}`);
    console.log(`  Author:      ${article.author || '(unknown)'}`);
    console.log(`  Status:      ${article.status}`);
    console.log(`  Created At:  ${article.created_at}`);
    console.log(`  Read At:     ${article.read_at || '(unread)'}`);
    console.log(`  Archived:    ${article.is_archived}`);
    console.log('-'.repeat(100));
  }

  // Summary by user
  const byUser = {};
  for (const article of articles) {
    if (!byUser[article.user_id]) {
      byUser[article.user_id] = [];
    }
    byUser[article.user_id].push(article);
  }

  console.log(`\nSummary by user:`);
  console.log('='.repeat(60));
  for (const [userId, userArticles] of Object.entries(byUser)) {
    console.log(`  User ${userId}: ${userArticles.length} article(s)`);
    for (const a of userArticles) {
      console.log(`    - [${a.status}] ${a.title || a.url}`);
    }
  }
}

queryArticles().catch((err) => {
  console.error('Unexpected error:', err);
  process.exit(1);
});
