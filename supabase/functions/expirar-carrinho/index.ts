import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

// Chamada por job agendado (ex: a cada 2 minutos via pg_cron ou Supabase Cron Jobs)
serve(async (_req) => {
  const { error, count } = await supabase
    .from("lojinha_carrinho")
    .delete({ count: "exact" })
    .lt("expires_at", new Date().toISOString());

  if (error) {
    return new Response(
      JSON.stringify({ ok: false, erro: error.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ ok: true, removidos: count ?? 0 }),
    { headers: { "Content-Type": "application/json" } }
  );
});
