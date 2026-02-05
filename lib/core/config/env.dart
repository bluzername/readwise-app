/// Environment configuration
/// Replace these values with your actual credentials
class Env {
  // Supabase
  static const String supabaseUrl = 'https://bioiacixxauufpvswlxe.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJpb2lhY2l4eGF1dWZwdnN3bHhlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk2OTc2MzAsImV4cCI6MjA4NTI3MzYzMH0.rALzbiI5ggIQYOrcPC8VeRVyJO_0KNVtQCaVKz7d9cQ';
  
  // Jina Reader API (for article extraction)
  static const String jinaApiKey = 'YOUR_JINA_API_KEY';
  
  // Claude API (stored in Supabase Edge Function secrets, not here)
  // Set via: supabase secrets set ANTHROPIC_API_KEY=your_key

  // Legal URLs (hosted on GitHub Pages)
  static const String privacyPolicyUrl = 'https://bluzername.github.io/ReadZero/privacy-policy';
  static const String termsOfServiceUrl = 'https://bluzername.github.io/ReadZero/terms-of-service';
}
