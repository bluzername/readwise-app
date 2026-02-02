// Test function to debug Grok extraction
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const XAI_API_KEY = Deno.env.get("XAI_API_KEY");

serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { url } = await req.json();

    console.log("[test-grok] Starting test");
    console.log("[test-grok] XAI_API_KEY set:", !!XAI_API_KEY);
    console.log("[test-grok] XAI_API_KEY length:", XAI_API_KEY?.length || 0);
    console.log("[test-grok] URL:", url);

    if (!XAI_API_KEY) {
      return new Response(
        JSON.stringify({ error: "XAI_API_KEY not set" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const urlMatch = url.match(/(?:twitter\.com|x\.com)\/([^\/]+)\/status\/(\d+)/);
    if (!urlMatch) {
      return new Response(
        JSON.stringify({ error: "Could not parse URL", url }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const username = urlMatch[1];
    const postId = urlMatch[2];
    console.log("[test-grok] Username:", username, "PostID:", postId);

    const response = await fetch("https://api.x.ai/v1/responses", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${XAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: "grok-4-1-fast",
        tools: [{ type: "x_search", x_search: { allowed_x_handles: [username] } }],
        input: [{ role: "user", content: `Extract this X post: ${url}` }],
      }),
    });

    console.log("[test-grok] Response status:", response.status);

    if (!response.ok) {
      const errorText = await response.text();
      console.error("[test-grok] API error:", errorText);
      return new Response(
        JSON.stringify({ error: `API error: ${response.status}`, details: errorText }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const result = await response.json();
    console.log("[test-grok] Got response, status:", result.status);

    // Extract text from response
    let outputText = "";
    if (result.output && Array.isArray(result.output)) {
      for (const item of result.output) {
        if (item.type === "message" && item.role === "assistant" && item.content) {
          for (const c of item.content) {
            if (c.type === "output_text" && c.text) {
              outputText = c.text;
              break;
            }
          }
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        username,
        postId,
        outputLength: outputText.length,
        outputPreview: outputText.slice(0, 500),
        fullResponse: result,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    console.error("[test-grok] Error:", error);
    return new Response(
      JSON.stringify({ error: error.message, stack: error.stack }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
