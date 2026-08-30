(function () {
  const config = window.HMA_SUPABASE_CONFIG;
  if (!config || !config.url || !config.publishableKey || !window.supabase) return;
  const isEmployeeApp = /employee\.html$/i.test(window.location.pathname);
  window.hmaSupabase = window.supabase.createClient(config.url, config.publishableKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      storageKey: isEmployeeApp ? 'hma_employee_auth' : 'hma_admin_auth'
    }
  });
})();
