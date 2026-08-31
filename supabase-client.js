(function () {
  const config = window.HMA_SUPABASE_CONFIG;
  if (!config || !config.url || !config.publishableKey || !window.supabase) return;
  window.hmaSupabase = window.supabase.createClient(config.url, config.publishableKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      storageKey: 'hma_operations_auth'
    }
  });
})();
