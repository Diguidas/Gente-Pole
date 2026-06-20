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
    const { colaborador_id, material, quantidade } = await req.json();

    if (!colaborador_id || !material || quantidade == null) {
      return new Response(
        JSON.stringify({ ok: false, motivo: "parametros_invalidos" }),
        { status: 400, headers: CORS }
      );
    }

    // Quantidade 0 = remover do carrinho
    if (Number(quantidade) === 0) {
      await supabase
        .from("lojinha_carrinho")
        .delete()
        .eq("colaborador_id", colaborador_id)
        .eq("material", material);
      return new Response(JSON.stringify({ ok: true }), { headers: CORS });
    }

    // Estoque cacheado do SAP
    const { data: produto } = await supabase
      .from("lojinha_produtos")
      .select("estoque")
      .eq("material", material)
      .single();

    if (!produto) {
      return new Response(
        JSON.stringify({ ok: false, motivo: "produto_nao_encontrado" }),
        { status: 404, headers: CORS }
      );
    }

    // Soma das reservas ativas de OUTROS usuários para este material
    const { data: reservas } = await supabase
      .from("lojinha_carrinho")
      .select("quantidade")
      .eq("material", material)
      .neq("colaborador_id", colaborador_id)
      .gt("expires_at", new Date().toISOString());

    const totalReservado = (reservas ?? []).reduce(
      (sum: number, r: { quantidade: number }) => sum + Number(r.quantidade),
      0
    );

    const estoqueVisivel = Number(produto.estoque) - totalReservado;

    if (Number(quantidade) > estoqueVisivel) {
      return new Response(
        JSON.stringify({
          ok: false,
          motivo: "estoque_insuficiente",
          estoque_disponivel: Math.max(0, estoqueVisivel),
        }),
        { headers: CORS }
      );
    }

    // Upsert: insere ou atualiza, renovando o prazo de expiração
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    const { error } = await supabase.from("lojinha_carrinho").upsert(
      { colaborador_id, material, quantidade: Number(quantidade), expires_at: expiresAt },
      { onConflict: "colaborador_id,material" }
    );

    if (error) throw error;

    return new Response(
      JSON.stringify({ ok: true, estoque_disponivel: estoqueVisivel }),
      { headers: CORS }
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, motivo: "erro_interno", detalhe: String(e) }),
      { status: 500, headers: CORS }
    );
  }
});
