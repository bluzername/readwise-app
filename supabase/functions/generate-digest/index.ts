// supabase/functions/generate-digest/index.ts
// Generates daily digest summaries using Claude via OpenRouter

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const OPENROUTER_API_KEY = Deno.env.get("OPENROUTER_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Using Claude Haiku 4.5 via OpenRouter for cost efficiency
const LLM_MODEL = "anthropic/claude-3.5-haiku";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface DigestRequest {
  user_id?: string; // Optional: generate for specific user
  date?: string;    // Optional: specific date (defaults to yesterday)
  test_all?: boolean; // Optional: include ALL ready articles regardless of date (for testing)
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body: DigestRequest = req.method === "POST"
      ? await req.json()
      : {};

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Determine date range (yesterday by default)
    const targetDate = body.date
      ? new Date(body.date)
      : new Date(Date.now() - 24 * 60 * 60 * 1000);

    const startOfDay = new Date(targetDate);
    startOfDay.setHours(0, 0, 0, 0);

    const endOfDay = new Date(targetDate);
    endOfDay.setHours(23, 59, 59, 999);

    // TEST MODE: If test_all is true, get all unique users with ready articles
    const results: any[] = [];

    if (body.test_all) {
      console.log("[digest] Running in TEST MODE - processing all ready articles");

      // Get all unique users who have ready articles
      const { data: articleUsers, error: articlesError } = await supabase
        .from("articles")
        .select("user_id")
        .eq("status", "ready");

      if (articlesError) throw articlesError;

      // Get unique user IDs
      const uniqueUserIds = [...new Set((articleUsers || []).map((a: any) => a.user_id))];
      console.log(`[digest] Found ${uniqueUserIds.length} users with ready articles`);

      for (const userId of uniqueUserIds) {
        try {
          const digest = await generateUserDigest(
            supabase,
            userId,
            null, // No date filter in test mode
            null,
            targetDate,
            true // testAll flag
          );

          if (digest) {
            results.push({ user_id: userId, success: true, digest_id: digest.id });
          } else {
            results.push({ user_id: userId, success: true, skipped: "no articles" });
          }
        } catch (e: any) {
          console.error(`Failed to generate digest for user ${userId}:`, e);
          results.push({ user_id: userId, success: false, error: e.message });
        }
      }
    } else {
      // NORMAL MODE: Get users from user_settings
      let usersQuery = supabase.from("user_settings").select("user_id");
      if (body.user_id) {
        usersQuery = usersQuery.eq("user_id", body.user_id);
      }

      const { data: users, error: usersError } = await usersQuery;
      if (usersError) throw usersError;

      for (const user of users || []) {
        try {
          const digest = await generateUserDigest(
            supabase,
            user.user_id,
            startOfDay,
            endOfDay,
            targetDate,
            false
          );

          if (digest) {
            results.push({ user_id: user.user_id, success: true, digest_id: digest.id });

            // Send push notification if enabled
            await sendPushNotification(supabase, user.user_id, digest);
          } else {
            results.push({ user_id: user.user_id, success: true, skipped: "no articles" });
          }
        } catch (e: any) {
          console.error(`Failed to generate digest for user ${user.user_id}:`, e);
          results.push({ user_id: user.user_id, success: false, error: e.message });
        }
      }
    }

    return new Response(
      JSON.stringify({ success: true, results }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Error generating digests:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      }
    );
  }
});

async function generateUserDigest(
  supabase: any,
  userId: string,
  startOfDay: Date | null,
  endOfDay: Date | null,
  targetDate: Date,
  testAll: boolean = false
): Promise<any> {

  // Get articles - either from target day or ALL ready articles (test mode)
  let query = supabase
    .from("articles")
    .select("*")
    .eq("user_id", userId)
    .eq("status", "ready");

  // Only apply date filter in normal mode
  if (!testAll && startOfDay && endOfDay) {
    query = query
      .gte("created_at", startOfDay.toISOString())
      .lte("created_at", endOfDay.toISOString());
  }

  const { data: articles, error } = await query.order("created_at", { ascending: false });

  if (error) throw error;
  if (!articles || articles.length === 0) return null;

  console.log(`[digest] Processing ${articles.length} articles for user ${userId} (testAll: ${testAll})`);

  console.log(`Generating digest for user ${userId} with ${articles.length} articles`);

  // Prepare article summaries for Claude
  const articleSummaries = articles.map((article: any) => ({
    id: article.id,
    title: article.title,
    url: article.url,
    summary: article.analysis?.summary || article.description,
    key_points: article.analysis?.key_points || [],
    topics: article.analysis?.topics || [],
    broader_context: article.analysis?.broader_context || null,
    image_url: article.image_url,
  }));

  // Generate digest with Claude via OpenRouter - "Curious Explorer" conversational style
  const prompt = `You are a curious, insightful friend summarizing what someone saved to read yesterday. Your job is to find patterns, surface connections, and make their reading feel worthwhile.

Articles saved (${articles.length} total):
${JSON.stringify(articleSummaries, null, 2)}

Write a digest in this JSON format:
{
  "overall_summary": "A conversational 150-300 word summary written like a thoughtful friend who read everything for them. Start with any patterns or themes you noticed. Group related articles and explain connections. Highlight the most surprising or important thing across all saves. Mention 'random' saves that don't fit patterns with a light touch. End with a thought-provoking observation or question. Use 'you' and 'I noticed' - this is a personal note, not a formal report.",
  "top_themes": ["Theme 1", "Theme 2", "Theme 3"],
  "articles": [
    {
      "article_id": "uuid",
      "title": "Article title",
      "image_url": "url or null",
      "summary": "1 sentence capturing the key insight from this specific article",
      "highlights": ["Most important fact or takeaway", "Second key point if relevant"],
      "url": "original url"
    }
  ],
  "ai_insights": "One specific, thought-provoking connection or pattern you noticed that the reader might not have seen themselves. Be concrete - reference specific articles and what links them."
}

STYLE GUIDE for overall_summary:
- Write like a smart friend texting you, not a news anchor
- "You saved 6 articles yesterday, and I noticed something interesting..."
- "Three of them touched on AI regulation - seems like you're tracking..."
- "The common thread: everyone agrees X, but nobody agrees on Y"
- "That random Wikipedia deep-dive? No pattern there, but genuinely fascinating"
- Curious explorer energy - you find this stuff genuinely interesting

AVOID:
- "This digest covers..." or "Today's articles include..."
- Formal, report-style language
- Generic observations that could apply to any set of articles
- Bullet points in the overall_summary (save those for highlights)

Return ONLY valid JSON, no other text.`;

  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${OPENROUTER_API_KEY}`,
      "HTTP-Referer": SUPABASE_URL,
      "X-Title": "Readwise App",
    },
    body: JSON.stringify({
      model: LLM_MODEL,
      max_tokens: 2048,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`OpenRouter API error: ${error}`);
  }

  const result = await response.json();
  let digestText = result.choices[0].message.content;

  // Parse JSON from response (handle potential markdown code blocks)
  if (digestText.includes("```json")) {
    digestText = digestText.split("```json")[1].split("```")[0];
  } else if (digestText.includes("```")) {
    digestText = digestText.split("```")[1].split("```")[0];
  }

  const digestContent = JSON.parse(digestText.trim());

  // Save digest to database
  const dateStr = targetDate.toISOString().split('T')[0];

  const { data: digest, error: insertError } = await supabase
    .from("digests")
    .upsert({
      user_id: userId,
      date: dateStr,
      overall_summary: digestContent.overall_summary,
      top_themes: digestContent.top_themes,
      articles: digestContent.articles,
      ai_insights: digestContent.ai_insights,
    }, {
      onConflict: "user_id,date",
    })
    .select()
    .single();

  if (insertError) throw insertError;

  return digest;
}

async function sendPushNotification(
  supabase: any,
  userId: string,
  digest: any
): Promise<void> {
  try {
    // Get user's FCM token
    const { data: settings } = await supabase
      .from("user_settings")
      .select("fcm_token, push_notifications")
      .eq("user_id", userId)
      .single();

    if (!settings?.push_notifications || !settings?.fcm_token) return;

    // Log notification (in production, integrate with Firebase Admin SDK)
    console.log(`Would send push notification to user ${userId}:`, {
      title: "Your Daily Digest is Ready",
      body: `${digest.articles?.length || 0} articles summarized. ${(digest.top_themes || []).slice(0, 2).join(", ")}`,
    });

  } catch (e) {
    console.error("Failed to send push notification:", e);
  }
}
