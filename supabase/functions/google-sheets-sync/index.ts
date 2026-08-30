import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const token = request.headers.get("Authorization")?.replace("Bearer ", "");
    if (!token) throw new Error("Sesi pengguna tidak ditemukan.");

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) throw new Error("Sesi pengguna tidak valid.");

    const body = await request.json();
    const webAppUrl = Deno.env.get("GOOGLE_SHEETS_WEB_APP_URL");
    const syncToken = Deno.env.get("HMA_SHEETS_SYNC_TOKEN");
    if (!webAppUrl || !syncToken) throw new Error("Koneksi Google Spreadsheet belum dikonfigurasi.");

    const action = body.action === "upsert" ? "upsert" : "pull";
    if (action === "upsert") {
      const { data: profile } = await admin.from("profiles").select("role").eq("id", authData.user.id).single();
      if (!profile || !["admin", "hr", "finance"].includes(profile.role)) {
        throw new Error("Anda tidak memiliki akses untuk memperbarui Spreadsheet.");
      }
    }

    const response = await fetch(webAppUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...body, action, token: syncToken, source: "hma-app" })
    });
    const payload = await response.json();
    if (!response.ok || !payload.ok) throw new Error(payload.error || "Google Spreadsheet menolak sinkronisasi.");
    return Response.json(payload, { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (error) {
    return Response.json({ error: error.message || "Sinkronisasi gagal." }, {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }
});
