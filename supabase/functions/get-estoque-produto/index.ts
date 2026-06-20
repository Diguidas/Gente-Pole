import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
};

// Recebe: { colaborador_id, materiais: string[] }  (materiais COM zeros à esquerda)
// Retorna: { ok, estoques: [{ material, estoque_disponivel }] }
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        ...CORS,
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  try {
    const { colaborador_id, materiais } = await req.json();

    if (!colaborador_id || !Array.isArray(materiais) || materiais.length === 0) {
      return new Response(
        JSON.stringify({ ok: false, motivo: "parametros_invalidos" }),
        { status: 400, headers: CORS }
      );
    }

    // Estoque cacheado do SAP para cada material
    const { data: produtos, error: prodErr } = await supabase
      .from("lojinha_produtos")
      .select("material, estoque")
      .in("material", materiais);

    if (prodErr) throw prodErr;

    // Soma de reservas ativas de OUTROS usuários, agrupado por material
    const now = new Date().toISOString();
    const { data: reservas, error: resErr } = await supabase
      .from("lojinha_carrinho")
      .select("material, quantidade")
      .in("material", materiais)
      .neq("colaborador_id", colaborador_id)
      .gt("expires_at", now);

    if (resErr) throw resErr;

    const reservaMap: Record<string, number> = {};
    for (const r of reservas ?? []) {
      reservaMap[r.material] = (reservaMap[r.material] ?? 0) + Number(r.quantidade);
    }

    const estoques = (produtos ?? []).map((p) => ({
      material: p.material as string,
      estoque_disponivel: Math.max(
        0,
        Number(p.estoque) - (reservaMap[p.material] ?? 0)
      ),
    }));

    return new Response(
      JSON.stringify({ ok: true, estoques }),
      { headers: CORS }
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, motivo: "erro_interno", detalhe: String(e) }),
      { status: 500, headers: CORS }
    );
  }
});
