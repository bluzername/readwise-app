// supabase/functions/extract-article/index.ts
// Extracts article content using Mozilla Readability (primary) with Jina Reader API fallback
// Enriches with Tavily search and analyzes with Claude via OpenRouter

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Readability } from "npm:@mozilla/readability@0.6.0";
import { parseHTML } from "npm:linkedom@0.18.9";

const JINA_API_KEY = Deno.env.get("JINA_API_KEY");
const OPENROUTER_API_KEY = Deno.env.get("OPENROUTER_API_KEY");
const TAVILY_API_KEY = Deno.env.get("TAVILY_API_KEY");
const XAI_API_KEY = Deno.env.get("XAI_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Using Claude Haiku 3.5 via OpenRouter for cost efficiency
const LLM_MODEL = "anthropic/claude-3.5-haiku";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ExtractRequest {
  article_id: string;
  url: string;
  // For pre-extracted content (from on-device authenticated extraction)
  pre_extracted?: boolean;
  content?: string;
  title?: string;
  image_url?: string;
  author?: string;
}

interface ExtractedData {
  title: string;
  description: string;
  content: string;
  images: Array<{ src: string; alt?: string }>;
  siteName?: string;
  author?: string;
}

interface TavilyResult {
  title: string;
  url: string;
  content: string;
  score: number;
}

// Clean extracted content - remove navigation, metrics, and noise
function cleanExtractedContent(content: string): string {
  if (!content) return content;

  let cleaned = content
    // Remove Wikipedia navigation
    .replace(/Toggle the table of contents\s*/gi, '')
    .replace(/\d+\s*languages?\s*[\p{L}\s,]+(?=\s{2}|\n)/giu, '') // Language links
    .replace(/From Wikipedia, the free encyclopedia/gi, '')
    .replace(/\[edit\]/gi, '')
    .replace(/\[\d+\]/g, '') // Citation numbers [1], [2], etc.

    // Remove news site navigation and metadata
    .replace(/\d+\s*(hours?|minutes?|days?|weeks?|months?)\s*ago/gi, '')
    .replace(/Share\s*Save/gi, '')
    .replace(/Share\s*Copy link/gi, '')
    .replace(/Share\s*this\s*(article|post|story)/gi, '')
    .replace(/Getty Images/gi, '')
    .replace(/Reuters/gi, '')
    .replace(/Associated Press/gi, '')
    .replace(/AFP/gi, '')
    .replace(/EPA/gi, '')

    // Remove LinkedIn metrics
    .replace(/\d+\s*(likes?|reactions?|comments?|reposts?|shares?|views?|followers?)/gi, '')
    .replace(/Like\s*Comment\s*Repost\s*Send/gi, '')

    // Remove Twitter/X metrics
    .replace(/\d+\s*(retweets?|quotes?|replies|bookmarks?)/gi, '')

    // Remove Reddit metrics
    .replace(/\d+\s*(upvotes?|downvotes?|points?|awards?)/gi, '')
    .replace(/Posted by\s*u\/\w+/gi, '')

    // Remove generic social/UI patterns
    .replace(/Share this post/gi, '')
    .replace(/Copy link to post/gi, '')
    .replace(/Report this/gi, '')
    .replace(/Follow\s+\d*/gi, '')
    .replace(/Connect\s+\d*/gi, '')
    .replace(/Read more/gi, '')
    .replace(/Continue reading/gi, '')
    .replace(/Advertisement/gi, '')

    // Clean up excessive whitespace
    .replace(/\n{3,}/g, '\n\n')
    .replace(/\s{3,}/g, ' ')
    .trim();

  // If content starts with title repeated, try to skip it
  const lines = cleaned.split('\n');
  if (lines.length > 2 && lines[0].length < 200) {
    // First line might be title, check if second line has substance
    const secondLine = lines.slice(1).join('\n').trim();
    if (secondLine.length > 100) {
      cleaned = secondLine;
    }
  }

  return cleaned;
}

// Clean up messy titles from various sources
function cleanTitle(title: string, url: string): string {
  if (!title || title.length < 3) {
    try {
      return new URL(url).hostname.replace(/^www\./, '');
    } catch {
      return "Untitled";
    }
  }

  return title
    // Remove " | Site Name" suffixes
    .replace(/\s*\|\s*[^|]{1,50}$/, '')
    // Remove " - Site Name" suffixes
    .replace(/\s*[-–—]\s*[^-–—]{1,50}$/, '')
    // Remove Reddit-style metadata "r/subreddit"
    .replace(/\s*:\s*r\/\w+\s*$/, '')
    // Remove comment counts "(123 comments)"
    .replace(/\s*\(\d+\s*comments?\)/gi, '')
    // Remove upvote indicators "[123 upvotes]"
    .replace(/\s*\[\d+\s*(?:upvotes?|points?)\]/gi, '')
    // Remove "by Author" at end
    .replace(/\s+by\s+\w+\s*$/i, '')
    // Clean up multiple spaces
    .replace(/\s+/g, ' ')
    .trim()
    // Limit length
    .slice(0, 200);
}

// Decode HTML entities like &quot; &#x27; &amp; etc.
function decodeHtmlEntities(text: string): string {
  if (!text) return text;
  return text
    .replace(/&quot;/g, '"')
    .replace(/&#x27;/g, "'")
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&')
    .replace(/&nbsp;/g, ' ')
    .replace(/&#(\d+);/g, (_, num) => String.fromCharCode(parseInt(num, 10)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
}

serve(async (req) => {
  // Handle CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Parse request body once and store it
  let article_id: string;
  let url: string;
  let preExtracted = false;
  let preContent: string | undefined;
  let preTitle: string | undefined;
  let preImageUrl: string | undefined;
  let preAuthor: string | undefined;

  try {
    const body = await req.json();
    article_id = body.article_id;
    url = body.url;
    preExtracted = body.pre_extracted === true;
    preContent = body.content;
    preTitle = body.title;
    preImageUrl = body.image_url;
    preAuthor = body.author;
  } catch (e) {
    return new Response(
      JSON.stringify({ error: "Invalid request body" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  try {
    console.log(`[extract] Starting extraction for article: ${article_id}, url: ${url}`);

    // Update status to extracting
    const updateResult = await supabase
      .from("articles")
      .update({ status: "extracting" })
      .eq("id", article_id);

    console.log(`[extract] Status updated to extracting, result:`, updateResult.error ? updateResult.error : 'OK');

    let extracted: ExtractedData;

    // Check for walled-garden sites that block scrapers
    const isLinkedIn = url.includes("linkedin.com");
    const isTwitter = url.includes("twitter.com") || url.includes("x.com");
    const isPaywalled = url.includes("wsj.com") || url.includes("nytimes.com") || url.includes("ft.com");

    // For Twitter/X, use Grok API which has native access
    if (isTwitter) {
      console.log(`[extract] Detected X/Twitter URL: ${url}`);
      console.log(`[extract] XAI_API_KEY available: ${!!XAI_API_KEY}`);

      if (!XAI_API_KEY) {
        console.error("[extract] XAI_API_KEY is not set!");
        extracted = {
          title: "X Post",
          description: "X API key not configured",
          content: "X post extraction is not configured. Tap to open in browser.",
          images: [],
          siteName: "X",
        };
      } else {
        try {
          extracted = await extractWithGrok(url);
          console.log("[extract] Grok extraction successful, content length:", extracted.content?.length);
        } catch (grokError: any) {
          console.error("[extract] Grok extraction failed:", grokError?.message || grokError);
          console.error("[extract] Grok error stack:", grokError?.stack);
          extracted = {
            title: "X Post",
            description: `Extraction failed: ${grokError?.message || 'Unknown error'}`,
            content: "This X post could not be extracted. Tap to open in browser.",
            images: [],
            siteName: "X",
          };
        }
      }
    }
    // Check if we have pre-extracted content (from on-device authenticated extraction)
    else if (preExtracted && preContent && preContent.length > 50) {
      console.log(`Using pre-extracted content for: ${url} (pre-extracted from ${isLinkedIn ? 'LinkedIn' : isTwitter ? 'Twitter' : 'site'})`);

      // Use the pre-extracted content directly
      extracted = {
        title: preTitle || new URL(url).hostname,
        description: preContent.slice(0, 200),
        content: preContent,
        images: preImageUrl ? [{ src: preImageUrl }] : [],
        author: preAuthor,
        siteName: new URL(url).hostname.replace("www.", ""),
      };
      console.log("Pre-extracted content ready for analysis");
    } else {
      // 1. Extract content - try Readability first (cleaner), then Jina (better reach), then basic
      console.log(`Extracting content from: ${url}`);

      // Sites that block direct requests - go straight to Jina
      const jinaFirstSites = [
        "medium.com",
        "bloomberg.com",
        "stackoverflow.com",
        "youtube.com",
        "podcasts.apple.com",
      ];
      const useJinaFirst = jinaFirstSites.some(site => url.includes(site));

      try {
        if (useJinaFirst) {
          console.log("Site typically blocks direct requests, trying Jina first...");
          extracted = await extractWithJina(url);
          console.log("Jina extraction successful");
        } else {
          // Try Readability first - produces cleaner content
          console.log("Trying Readability extraction...");
          extracted = await extractWithReadability(url);
          console.log("Readability extraction successful");
        }

        // Check if LinkedIn returned garbage (login wall)
        if (isLinkedIn && extracted.content &&
            (extracted.content.includes("Sign in") ||
             extracted.content.includes("Join now") ||
             extracted.content.length < 200)) {
          console.log("LinkedIn returned login wall, using fallback");
          throw new Error("LinkedIn login wall detected");
        }

        // Check if Twitter/X returned garbage (login wall)
        if (isTwitter && extracted.content &&
            (extracted.content.includes("Sign in") ||
             extracted.content.includes("Log in") ||
             extracted.content.includes("Something went wrong") ||
             extracted.content.length < 100)) {
          console.log("Twitter/X returned login wall, using fallback");
          throw new Error("Twitter login wall detected");
        }
      } catch (primaryError) {
        console.error("Primary extraction failed:", primaryError);

        // Try the opposite method as fallback
        try {
          if (useJinaFirst) {
            console.log("Jina failed, trying Readability fallback...");
            extracted = await extractWithReadability(url);
            console.log("Readability fallback successful");
          } else {
            console.log("Readability failed, trying Jina fallback...");
            extracted = await extractWithJina(url);
            console.log("Jina fallback successful");
          }

          // Re-check for login walls
          if (isLinkedIn && extracted.content && extracted.content.length < 200) {
            throw new Error("LinkedIn content too short");
          }
          if (isTwitter && extracted.content && extracted.content.length < 100) {
            throw new Error("Twitter content too short");
          }
        } catch (fallbackError) {
          console.error("Fallback extraction failed:", fallbackError);

          // Last resort: basic extraction
          try {
            console.log("Trying basic extraction as last resort...");
            extracted = await extractBasic(url);
            console.log("Basic extraction successful");
          } catch (basicError) {
            console.error("All extraction methods failed:", basicError);

            // Provide helpful fallback for known problematic sites
            let fallbackTitle = new URL(url).hostname;
            let fallbackContent = "";
            let fallbackDescription = "";

            if (isLinkedIn) {
              fallbackTitle = "LinkedIn Post";
              fallbackDescription = "LinkedIn content requires login to view";
              fallbackContent = "This LinkedIn post cannot be extracted automatically. LinkedIn requires authentication to view full content. Tap to open in browser.";
            } else if (isTwitter) {
              fallbackTitle = "X Post";
              fallbackDescription = "X/Twitter content requires login to view";
              fallbackContent = "This post cannot be extracted automatically. X/Twitter requires authentication to view full content. Tap to open in browser.";
            } else if (isPaywalled) {
              fallbackTitle = "Paywalled Article";
              fallbackDescription = "This article is behind a paywall";
              fallbackContent = "This article requires a subscription to read. Tap to open in browser.";
            } else {
              fallbackContent = `Content could not be extracted. Tap to open the original article.`;
            }

            extracted = {
              title: fallbackTitle,
              description: fallbackDescription,
              content: fallbackContent,
              images: [],
              siteName: new URL(url).hostname.replace("www.", ""),
            };
          }
        }
      }
    }

    // Extract comments if it's a discussion site (Reddit, HN, etc.)
    let comments: any[] = [];
    const isDiscussionSite = url.includes("reddit.com") ||
                            url.includes("news.ycombinator.com") ||
                            url.includes("twitter.com") ||
                            url.includes("x.com");

    // 2. Fetch related context using Tavily (optional)
    let relatedContext: TavilyResult[] = [];
    if (TAVILY_API_KEY && extracted.title && extracted.title.length > 5) {
      try {
        console.log("Fetching related context with Tavily...");
        relatedContext = await searchWithTavily(extracted.title);
        console.log(`Found ${relatedContext.length} related articles`);
      } catch (e) {
        console.error("Tavily search failed:", e);
        // Continue without related context
      }
    }

    // 3. Update article with extracted content
    const cleanedTitle = cleanTitle(extracted.title, url);
    console.log(`Cleaned title: "${cleanedTitle}" (from: "${extracted.title?.slice(0, 50)}")`);

    await supabase
      .from("articles")
      .update({
        title: cleanedTitle,
        description: extracted.description,
        content: extracted.content,
        image_url: extracted.images?.[0]?.src,
        site_name: extracted.siteName,
        author: extracted.author,
        images: extracted.images?.map(img => ({
          url: img.src,
          alt: img.alt,
        })) || [],
        comments: comments,
        status: "analyzing",
      })
      .eq("id", article_id);

    // 4. Analyze content with Claude via OpenRouter
    // Skip analysis for fallback/error content
    const isFallbackContent = extracted.content?.includes("cannot be extracted") ||
                              extracted.content?.includes("requires a subscription") ||
                              extracted.content?.includes("requires login");
    let analysis = null;
    console.log(`[extract] About to analyze. OPENROUTER_API_KEY set: ${!!OPENROUTER_API_KEY}, content length: ${extracted.content?.length}, isFallback: ${isFallbackContent}`);

    if (OPENROUTER_API_KEY && extracted.content && extracted.content.length > 200 && !isFallbackContent) {
      try {
        console.log("[extract] Starting Claude analysis via OpenRouter...");
        analysis = await analyzeWithClaude(
          extracted.title,
          extracted.content,
          extracted.images || [],
          comments,
          relatedContext
        );
        console.log("Analysis complete");
        console.log("[extract] Analysis completed successfully");
      } catch (analysisError) {
        console.error("[extract] Analysis failed with error:", analysisError.message || analysisError);
        console.error("[extract] Error stack:", analysisError.stack);
        // Continue without analysis - create meaningful fallback from extracted content
        const fallbackSummary = extracted.description && extracted.description.length > 20
          ? extracted.description
          : `Article from ${extracted.siteName || new URL(url).hostname}`;
        // Create a fallback bullet from title or first 200 chars, finding sentence boundary
        const contentPreview = extracted.content?.slice(0, 300).split(/[.!?]\s/)[0] || "";
        console.log("[extract] Using fallback - contentPreview:", contentPreview.slice(0, 100));
        analysis = {
          summary: fallbackSummary,
          key_points: contentPreview.length > 30 ? [contentPreview.trim() + "."] : [fallbackSummary],
          topics: [],
          sentiment: "neutral",
          reading_time_minutes: Math.ceil((extracted.content?.length || 0) / 1500),
        };
      }
    } else {
      console.log("[extract] Skipping analysis - using fallback");
      // Provide helpful fallback for restricted content
      let fallbackSummary = extracted.description || extracted.content?.slice(0, 200) || "Content could not be analyzed";
      let fallbackPoints: string[] = [];

      if (isFallbackContent) {
        if (url.includes("linkedin.com")) {
          fallbackSummary = "LinkedIn post saved - open in browser to view";
          fallbackPoints = ["LinkedIn requires login to view full content"];
        } else if (url.includes("twitter.com") || url.includes("x.com")) {
          fallbackSummary = "X post saved - open in browser to view";
          fallbackPoints = ["X/Twitter requires login to view full content"];
        } else if (url.includes("wsj.com") || url.includes("nytimes.com") || url.includes("ft.com")) {
          fallbackSummary = "Paywalled article saved - subscription required";
          fallbackPoints = ["This publication requires a subscription"];
        }
      } else {
        // For short content that's not restricted, use the content as the bullet
        if (extracted.content && extracted.content.length > 10) {
          fallbackPoints = [extracted.content.slice(0, 250) + (extracted.content.length > 250 ? "..." : "")];
        } else {
          fallbackPoints = [fallbackSummary];
        }
      }

      analysis = {
        summary: fallbackSummary,
        key_points: fallbackPoints,
        topics: [],
        sentiment: "neutral",
        reading_time_minutes: Math.max(1, Math.ceil((extracted.content?.length || 0) / 1500)),
      };
    }

    // 5. Update article with analysis
    const finalUpdate = await supabase
      .from("articles")
      .update({
        analysis: analysis,
        status: "ready",
      })
      .eq("id", article_id)
      .select();

    console.log(`[extract] Final update result:`, finalUpdate.error ? finalUpdate.error : `OK, ${finalUpdate.data?.length} rows updated`);
    console.log(`Article ${article_id} processed successfully`);

    return new Response(
      JSON.stringify({ success: true, article_id }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Error processing article:", error);
    console.error("Error stack:", error.stack);

    // Mark article as failed with error details
    try {
      await supabase
        .from("articles")
        .update({
          status: "failed",
          // Store error in description for debugging
          description: `Extraction failed: ${error.message}`.slice(0, 500),
        })
        .eq("id", article_id);
    } catch (updateError) {
      console.error("Failed to update article status:", updateError);
    }

    return new Response(
      JSON.stringify({
        error: error.message,
        stack: error.stack,
        article_id: article_id
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      }
    );
  }
});

// Extract images from HTML for Readability results
function extractImagesFromHtml(html: string, baseUrl: string): Array<{ src: string; alt?: string }> {
  const images: Array<{ src: string; alt?: string }> = [];

  // Extract og:image first (usually the best hero image)
  const ogImageMatch = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i) ||
                       html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i);
  if (ogImageMatch?.[1]) {
    try {
      const imgUrl = new URL(ogImageMatch[1], baseUrl).href;
      images.push({ src: imgUrl, alt: "" });
    } catch {}
  }

  // Extract article images
  const imgMatches = html.matchAll(/<img[^>]+src=["']([^"']+)["'][^>]*(?:alt=["']([^"']*?)["'])?/gi);
  for (const match of imgMatches) {
    if (match[1] && !match[1].includes('data:') && !match[1].includes('tracking') && !match[1].includes('pixel')) {
      try {
        const imgUrl = new URL(match[1], baseUrl).href;
        // Skip small tracking pixels and icons
        if (!images.some(img => img.src === imgUrl)) {
          images.push({ src: imgUrl, alt: match[2] || "" });
        }
      } catch {}
    }
    if (images.length >= 5) break; // Limit to 5 images
  }

  return images;
}

// Primary extraction using Mozilla Readability - produces cleaner content
async function extractWithReadability(url: string): Promise<ExtractedData> {
  const response = await fetch(url, {
    headers: {
      "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.5",
    },
    signal: AbortSignal.timeout(20000),
  });

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }

  const html = await response.text();

  // Parse with linkedom
  const { document } = parseHTML(html);

  // Use Readability to extract content
  const reader = new Readability(document, {
    charThreshold: 100,
  });
  const article = reader.parse();

  if (!article || !article.textContent || article.textContent.length < 100) {
    throw new Error("Readability could not parse article or content too short");
  }

  // Extract images from original HTML
  const images = extractImagesFromHtml(html, url);

  // Extract description from meta tags
  const descMatch = html.match(/<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)["']/i) ||
                    html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+name=["']description["']/i) ||
                    html.match(/<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']/i);

  return {
    title: decodeHtmlEntities(article.title || ""),
    description: decodeHtmlEntities(descMatch?.[1] || article.excerpt || ""),
    content: article.textContent,
    images: images,
    siteName: article.siteName || "",
    author: article.byline || "",
  };
}

// Fallback extraction using Jina Reader API - better for sites that block direct requests
async function extractWithJina(url: string): Promise<ExtractedData> {
  const headers: Record<string, string> = {
    "Accept": "application/json",
    "X-With-Images-Summary": "true",
    "X-With-Links-Summary": "true",
  };

  if (JINA_API_KEY) {
    headers["Authorization"] = `Bearer ${JINA_API_KEY}`;
  }

  const response = await fetch(`https://r.jina.ai/${url}`, {
    headers,
    signal: AbortSignal.timeout(30000),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Jina extraction failed: ${response.status} ${response.statusText} - ${errorText}`);
  }

  const data = await response.json();

  if (!data.data) {
    throw new Error("Jina returned empty data");
  }

  return {
    title: decodeHtmlEntities(data.data.title || ""),
    description: decodeHtmlEntities(data.data.description || ""),
    content: decodeHtmlEntities(data.data.content || ""),
    images: (data.data.images || []).map((img: any) => ({
      src: img.src || img.url || img,
      alt: img.alt,
    })),
    siteName: data.data.siteName,
    author: data.data.author,
  };
}

async function extractBasic(url: string): Promise<ExtractedData> {
  const response = await fetch(url, {
    headers: {
      "User-Agent": "Mozilla/5.0 (compatible; ReadwiseBot/1.0)",
      "Accept": "text/html",
    },
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch URL: ${response.status}`);
  }

  const html = await response.text();

  // Extract metadata from HTML
  const titleMatch = html.match(/<title[^>]*>([^<]+)<\/title>/i);
  const descMatch = html.match(/<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)["']/i) ||
                    html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+name=["']description["']/i) ||
                    html.match(/<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']/i);
  const imageMatch = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i) ||
                     html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i);
  const siteMatch = html.match(/<meta[^>]+property=["']og:site_name["'][^>]+content=["']([^"']+)["']/i);

  // Try to extract main content (simplified)
  let content = "";
  const articleMatch = html.match(/<article[^>]*>([\s\S]*?)<\/article>/i);
  const mainMatch = html.match(/<main[^>]*>([\s\S]*?)<\/main>/i);

  if (articleMatch) {
    content = articleMatch[1].replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
  } else if (mainMatch) {
    content = mainMatch[1].replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
  } else {
    // Fallback: extract text from body
    const bodyMatch = html.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
    if (bodyMatch) {
      content = bodyMatch[1]
        .replace(/<script[\s\S]*?<\/script>/gi, "")
        .replace(/<style[\s\S]*?<\/style>/gi, "")
        .replace(/<[^>]+>/g, " ")
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, 10000);
    }
  }

  return {
    title: decodeHtmlEntities(titleMatch?.[1]?.trim() || new URL(url).hostname),
    description: decodeHtmlEntities(descMatch?.[1]?.trim() || ""),
    content: decodeHtmlEntities(content || `Visit the original article at: ${url}`),
    images: imageMatch?.[1] ? [{ src: imageMatch[1], alt: "" }] : [],
    siteName: decodeHtmlEntities(siteMatch?.[1] || ""),
  };
}

// Extract X/Twitter posts using Grok API (xAI) which has native access to X data
async function extractWithGrok(url: string): Promise<ExtractedData> {
  console.log(`[Grok] Starting extraction for URL: ${url}`);
  console.log(`[Grok] XAI_API_KEY set: ${!!XAI_API_KEY}, length: ${XAI_API_KEY?.length || 0}`);

  // Parse the X URL to get username and post ID
  // Format: https://x.com/username/status/1234567890 or https://twitter.com/username/status/1234567890
  const urlMatch = url.match(/(?:twitter\.com|x\.com)\/([^\/]+)\/status\/(\d+)/);
  if (!urlMatch) {
    console.error(`[Grok] Could not parse URL: ${url}`);
    throw new Error("Could not parse X/Twitter URL");
  }

  const username = urlMatch[1];
  const postId = urlMatch[2];
  console.log(`[Grok] Parsed: @${username}, ID: ${postId}`);

  const requestBody = {
    model: "grok-4-1-fast",
    tools: [
      {
        type: "x_search",
        x_search: {
          allowed_x_handles: [username],
        },
      },
    ],
    input: [
      {
        role: "user",
        content: `Find and extract the full content of this specific X post: ${url}

Return the post content in a clean format with author, date, full text (including thread if applicable), and engagement metrics.`,
      },
    ],
  };

  console.log(`[Grok] Sending request to xAI API...`);

  const response = await fetch("https://api.x.ai/v1/responses", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${XAI_API_KEY}`,
    },
    body: JSON.stringify(requestBody),
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error(`[Grok] API error: ${response.status} - ${errorText}`);
    throw new Error(`Grok API error: ${response.status} - ${errorText}`);
  }

  const result = await response.json();
  console.log(`[Grok] Response received, status: ${result.status}`);

  // Extract the content from Grok's response
  // The response has output array with tool calls and assistant message
  // Find the assistant message with the text content
  let outputText = "";
  if (result.output && Array.isArray(result.output)) {
    for (const item of result.output) {
      if (item.type === "message" && item.role === "assistant" && item.content) {
        for (const contentItem of item.content) {
          if (contentItem.type === "output_text" && contentItem.text) {
            outputText = contentItem.text;
            break;
          }
        }
      }
    }
  }

  console.log(`[Grok] Extracted text length: ${outputText.length}`);
  if (!outputText || outputText.length < 20) {
    console.error(`[Grok] Full response: ${JSON.stringify(result).slice(0, 500)}`);
    throw new Error("Grok returned empty or insufficient content");
  }

  // The response is formatted markdown, extract key parts
  const author = `@${username}`;

  // Try to extract a cleaner title from the first meaningful line
  const lines = outputText.split('\n').filter(l => l.trim().length > 0);
  let title = `X post by @${username}`;
  for (const line of lines) {
    // Skip markdown headers and formatting
    const cleanLine = line.replace(/^\*\*.*?\*\*\s*/, '').replace(/^#+\s*/, '').trim();
    if (cleanLine.length > 20 && cleanLine.length < 200) {
      title = cleanLine.slice(0, 120) + (cleanLine.length > 120 ? '...' : '');
      break;
    }
  }

  console.log(`[Grok] Extracted title: ${title.slice(0, 50)}...`);

  return {
    title: title,
    description: outputText.slice(0, 300),
    content: outputText,
    images: [], // X images are described in the content
    siteName: "X",
    author: author,
  };
}

async function searchWithTavily(title: string): Promise<TavilyResult[]> {
  const searchQuery = title.slice(0, 200);

  const response = await fetch("https://api.tavily.com/search", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      api_key: TAVILY_API_KEY,
      query: searchQuery,
      search_depth: "basic",
      include_answer: false,
      include_raw_content: false,
      max_results: 5,
    }),
  });

  if (!response.ok) {
    throw new Error(`Tavily search failed: ${response.statusText}`);
  }

  const data = await response.json();

  return (data.results || []).map((r: any) => ({
    title: r.title,
    url: r.url,
    content: r.content,
    score: r.score,
  }));
}

// Robust JSON extraction from LLM response
function extractJsonFromResponse(text: string): any {
  if (!text) {
    throw new Error("Empty response from LLM");
  }

  // Try direct parse first
  try {
    return JSON.parse(text.trim());
  } catch (e) {
    // Continue to other methods
  }

  // Try extracting from ```json code blocks
  const jsonBlockMatch = text.match(/```json\s*([\s\S]*?)```/);
  if (jsonBlockMatch) {
    try {
      return JSON.parse(jsonBlockMatch[1].trim());
    } catch (e) {
      console.error("Failed to parse JSON from ```json block");
    }
  }

  // Try extracting from plain ``` code blocks
  const codeBlockMatch = text.match(/```\s*([\s\S]*?)```/);
  if (codeBlockMatch) {
    try {
      return JSON.parse(codeBlockMatch[1].trim());
    } catch (e) {
      console.error("Failed to parse JSON from code block");
    }
  }

  // Try finding a JSON object pattern in the text
  const objectMatch = text.match(/\{[\s\S]*\}/);
  if (objectMatch) {
    try {
      return JSON.parse(objectMatch[0]);
    } catch (e) {
      console.error("Failed to parse JSON object pattern");
    }
  }

  throw new Error(`Could not extract valid JSON from response: ${text.slice(0, 300)}...`);
}

// Strip emojis from text
function stripEmojis(text: string): string {
  if (!text) return text;
  // Remove most common emoji ranges
  return text
    .replace(/[\u{1F300}-\u{1F9FF}]/gu, '')
    .replace(/[\u{2600}-\u{26FF}]/gu, '')
    .replace(/[\u{2700}-\u{27BF}]/gu, '')
    .replace(/[\u{1F600}-\u{1F64F}]/gu, '')
    .replace(/[\u{1F680}-\u{1F6FF}]/gu, '')
    .replace(/[\u{1F1E0}-\u{1F1FF}]/gu, '')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

// Validate and ensure analysis has required fields with real content
function validateAnalysis(analysis: any, contentLength: number): any {
  const wordCount = contentLength / 5; // rough estimate
  const readingTime = Math.max(1, Math.ceil(wordCount / 200));

  // Ensure key_points is a non-empty array of strings (strip emojis)
  let keyPoints = analysis.key_points;
  if (Array.isArray(keyPoints) && keyPoints.length > 0) {
    keyPoints = keyPoints
      .filter((p: any) => typeof p === "string" && p.length > 0)
      .map((p: string) => stripEmojis(p))
      .slice(0, 3); // Only take 3 bullets max
  }
  // If still empty after filtering, create default
  if (!Array.isArray(keyPoints) || keyPoints.length === 0) {
    // Use tldr or summary as a single bullet fallback
    const fallbackBullet = analysis.tldr ||
      (typeof analysis.summary === "string" && analysis.summary.length > 20
        ? analysis.summary.slice(0, 150) + (analysis.summary.length > 150 ? "..." : "")
        : "See full article for details");
    keyPoints = [fallbackBullet];
  }

  // Ensure topics is a non-empty array of strings
  let topics = analysis.topics;
  if (!Array.isArray(topics) || topics.length === 0) {
    topics = ["general"];
  } else {
    topics = topics.filter((t: any) => typeof t === "string" && t.length > 0).slice(0, 5);
  }

  // Validate sentiment
  const validSentiments = ["positive", "negative", "neutral", "mixed"];
  const sentiment = validSentiments.includes(analysis.sentiment) ? analysis.sentiment : "neutral";

  // Process detailed_points (5-10 bullets for deeper dive)
  let detailedPoints = analysis.detailed_points;
  if (Array.isArray(detailedPoints) && detailedPoints.length > 0) {
    detailedPoints = detailedPoints
      .filter((p: any) => typeof p === "string" && p.length > 0)
      .map((p: string) => stripEmojis(p))
      .slice(0, 10); // Max 10 bullets
  } else {
    detailedPoints = [];
  }

  return {
    summary: typeof analysis.summary === "string" && analysis.summary.length > 10
      ? stripEmojis(analysis.summary)
      : "Summary unavailable",
    key_points: keyPoints,
    detailed_points: detailedPoints,
    topics: topics,
    sentiment: sentiment,
    reading_time_minutes: typeof analysis.reading_time_minutes === "number"
      ? analysis.reading_time_minutes
      : readingTime,
    tldr: typeof analysis.tldr === "string" ? stripEmojis(analysis.tldr) : null,
    content_type: analysis.content_type || "article",
    comments_summary: analysis.comments_summary ? stripEmojis(analysis.comments_summary) : null,
    broader_context: analysis.broader_context ? stripEmojis(analysis.broader_context) : null,
    related_sources: Array.isArray(analysis.related_sources) ? analysis.related_sources : [],
  };
}

async function analyzeWithClaude(
  title: string,
  content: string,
  images: Array<{ src: string; alt?: string }>,
  comments: any[],
  relatedContext: TavilyResult[]
): Promise<any> {

  let relatedContextText = "";
  if (relatedContext.length > 0) {
    relatedContextText = `
RELATED ARTICLES (for context):
${relatedContext.slice(0, 3).map((r, i) => `${i + 1}. "${r.title}" - ${r.content.slice(0, 150)}`).join("\n")}
`;
  }

  // Clean navigation junk, UI elements, and social media noise from extracted content
  const cleanedContent = cleanExtractedContent(content);

  // Two-level summary prompt: 3-bullet executive summary + 5-10 bullet deep dive
  const textPrompt = `You are extracting insights from an article. Provide TWO levels of summary:
1. key_points: 3 bullets for quick scanning (CLAIM, SIGNIFICANCE, TAKEAWAY)
2. detailed_points: 5-10 bullets for deeper understanding

TITLE: ${title}

CONTENT:
${cleanedContent.slice(0, 10000)}
${relatedContextText}

Return JSON with exactly this structure:

{
  "summary": "One sentence hook - what is this about and why should I care?",
  "tldr": "The single most important takeaway in under 15 words",
  "key_points": [
    "CLAIM: [Main finding/news with specific names, numbers, dates. 30-50 words]",
    "SIGNIFICANCE: [Why this matters, what's new or surprising. 30-50 words]",
    "TAKEAWAY: [What to remember or do with this information. 30-50 words]"
  ],
  "detailed_points": [
    "Background context that helps understand the story",
    "Key fact or data point #1",
    "Key fact or data point #2",
    "Important quote or statement from a key figure",
    "Related development or implication",
    "What experts or analysts are saying",
    "Historical context or comparison",
    "What happens next / what to watch for"
  ],
  "topics": ["topic-1", "topic-2"],
  "sentiment": "positive|negative|neutral|mixed",
  "reading_time_minutes": 5,
  "content_type": "news|opinion|tutorial|research|discussion"
}

CRITICAL RULES:
1. key_points: EXACTLY 3 bullets, each starting with CLAIM:, SIGNIFICANCE:, or TAKEAWAY:
2. detailed_points: 5-10 bullets covering the full story, NO labels needed
3. Include SPECIFIC details: names, numbers, dates, percentages, places
4. Write conversationally - like explaining to a smart friend

BANNED PHRASES (never use):
- "The article discusses/explores/examines..."
- "This is significant because..."
- "Readers will learn..."
- "According to the article..."
- "It is important to note..."

Respond with ONLY valid JSON, no markdown.`;

  console.log("Sending analysis request to OpenRouter...");
  console.log(`[analyze] Content length: ${cleanedContent.length}, Title: ${title.slice(0, 50)}`);

  // Add timeout for OpenRouter request (30 seconds)
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 30000);

  let response;
  try {
    response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${OPENROUTER_API_KEY}`,
        "HTTP-Referer": SUPABASE_URL,
        "X-Title": "ReadZero App",
      },
      body: JSON.stringify({
        model: LLM_MODEL,
        max_tokens: 1024,
        temperature: 0.3,
        messages: [
          {
            role: "system",
            content: "You are a JSON API. You only respond with valid JSON objects, never markdown or explanations."
          },
          { role: "user", content: textPrompt }
        ],
      }),
      signal: controller.signal,
    });
  } catch (fetchError) {
    clearTimeout(timeoutId);
    if (fetchError.name === 'AbortError') {
      console.error("OpenRouter request timed out after 30s");
      throw new Error("Analysis timed out - OpenRouter took too long");
    }
    console.error("OpenRouter fetch error:", fetchError);
    throw fetchError;
  }
  clearTimeout(timeoutId);

  console.log(`[analyze] OpenRouter response status: ${response.status}`);

  if (!response.ok) {
    const error = await response.text();
    console.error("OpenRouter API error:", error);
    throw new Error(`OpenRouter API error: ${response.status} - ${error}`);
  }

  const result = await response.json();

  if (!result.choices || !result.choices[0] || !result.choices[0].message) {
    console.error("Unexpected OpenRouter response structure:", JSON.stringify(result));
    throw new Error("Invalid response structure from OpenRouter");
  }

  const analysisText = result.choices[0].message.content;
  console.log("Raw LLM response (first 1000 chars):", analysisText.slice(0, 1000));

  // Extract and parse JSON
  const rawAnalysis = extractJsonFromResponse(analysisText);
  console.log("Parsed analysis - raw key_points:", JSON.stringify(rawAnalysis.key_points));
  console.log("Parsed analysis - raw summary:", rawAnalysis.summary?.slice(0, 100));

  // Validate and ensure all required fields have real content
  const validatedAnalysis = validateAnalysis(rawAnalysis, content.length);
  console.log("Validated analysis - final key_points count:", validatedAnalysis.key_points.length);
  console.log("Validated analysis - first key_point:", validatedAnalysis.key_points[0]?.slice(0, 100));

  return validatedAnalysis;
}
