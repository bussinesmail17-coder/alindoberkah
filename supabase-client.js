(function () {
  const config = window.COMPANY_SUPABASE_CONFIG || window.HMA_SUPABASE_CONFIG;
  const company = window.COMPANY_CONFIG || {};
  if (!config || !config.url || !config.publishableKey || !window.supabase) return;
  window.hmaSupabase = window.supabase.createClient(config.url, config.publishableKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      storageKey: company.authStorageKey || 'hma_operations_auth'
    }
  });
})();
