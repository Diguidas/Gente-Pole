import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const SAP_GET_ESTOQUE_URL = Deno.env.get("SAP_GET_ESTOQUE_PRODUTO_URL")!;
const SAP_POST_PEDIDO_URL = Deno.env.get("SAP_POST_PEDIDO_URL")!;
const SAP_USER = Deno.env.get("SAP_USER")!;
const SAP_PASS = Deno.env.get("SAP_PASS")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
};

function basicAuth() {
  return `Basic ${btoa(`${SAP_USER}:${SAP_PASS}`)}`;
}

async function fetchCsrf(url: string): Promise<{ token: string; cookie: string }> {
  const res = await fetch(url, {
    method: "GET",
    headers: { Authorization: basicAuth(), "x-csrf-token": "fetch" },
  });

  const token = res.headers.get("x-csrf-token") ?? "";

  // getSetCookie() retorna cada Set-Cookie como item separado (Deno 1.35+)
  // fallback para get() que junta tudo numa string separada por vírgula
  const setCookies: string[] =
    typeof (res.headers as any).getSetCookie === "function"
      ? (res.headers as any).getSetCookie()
      : (res.headers.get("set-cookie") ?? "").split(/,(?=[^ ])/);

  // Extrai só "nome=valor" (antes do primeiro ";") de cada diretiva Set-Cookie
  const cookie = setCookies
    .map((c) => c.split(";")[0].trim())
    .filter(Boolean)
    .join("; ");

  return { token, cookie };
}

interface SapItem {
  produto: string;
  unidvenda: string;
  quantidade: string;
  preco: string;
}

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
    const { colaborador_id, cliente_sap, datacriacao, itens } = await req.json();

    if (!colaborador_id || !cliente_sap || !itens?.length) {
      return new Response(
        JSON.stringify({ ok: false, retorno: "Parâmetros inválidos.", numeroPedido: null, remessa: null }),
        { status: 400, headers: CORS }
      );
    }

    const materiais: string[] = itens.map((i: SapItem) => i.produto); // sem zeros à esquerda

    // ── 1. Um único CSRF fetch reutilizado nas duas chamadas POST ────────────
    const { token: csrfToken, cookie } = await fetchCsrf(SAP_GET_ESTOQUE_URL);

    // ── 2. Revalidar estoque em tempo real via SAP ────────────────────────────
    const estoqueRes = await fetch(SAP_GET_ESTOQUE_URL, {
      method: "POST",
      headers: {
        Authorization: basicAuth(),
        "x-csrf-token": csrfToken,
        Cookie: cookie,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ materiais }),
    });

    if (!estoqueRes.ok) {
      const errBody = await estoqueRes.text().catch(() => "(sem body)");
      return new Response(
        JSON.stringify({
          ok: false,
          retorno: `SAP GET_ESTOQUE_PRODUTO retornou ${estoqueRes.status}: ${errBody}`,
          numeroPedido: null,
          remessa: null,
        }),
        { headers: CORS }
      );
    }

    const estoqueData = await estoqueRes.json();
    const estoqueMap: Record<string, number> = {};
    for (const m of (estoqueData.MATERIAIS ?? estoqueData.materiais ?? [])) {
      const code = String(m.MATERIAL ?? m.material).replace(/^0+/, "");
      estoqueMap[code] = Number(m.ESTOQUE ?? m.estoque);
    }

    // Reservas ativas de OUTROS usuários (material armazenado COM zeros no carrinho)
    const materiaisComZeros = materiais.map((m) => m.padStart(18, "0"));
    const now = new Date().toISOString();
    const { data: reservas } = await supabase
      .from("lojinha_carrinho")
      .select("material, quantidade")
      .in("material", materiaisComZeros)
      .neq("colaborador_id", colaborador_id)
      .gt("expires_at", now);

    const reservaMap: Record<string, number> = {};
    for (const r of (reservas ?? [])) {
      const code = String(r.material).replace(/^0+/, "");
      reservaMap[code] = (reservaMap[code] ?? 0) + Number(r.quantidade);
    }

    // Verificar disponibilidade de cada item
    for (const item of itens as SapItem[]) {
      const code = item.produto;
      const dispSap = estoqueMap[code] ?? 0;
      const reservado = reservaMap[code] ?? 0;
      const disponivel = dispSap - reservado;
      if (Number(item.quantidade) > disponivel) {
        return new Response(
          JSON.stringify({
            ok: false,
            retorno: `Estoque insuficiente para o material ${code}. Disponível: ${Math.max(0, disponivel)}.`,
            numeroPedido: null,
            remessa: null,
          }),
          { headers: CORS }
        );
      }
    }

    // ── 3. Criar Ordem de Venda + Remessa no SAP (mesmo token/cookie) ────────
    const sapRes = await fetch(SAP_POST_PEDIDO_URL, {
      method: "POST",
      headers: {
        Authorization: basicAuth(),
        "x-csrf-token": csrfToken,
        Cookie: cookie,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ codcliente: cliente_sap, datacriacao, itens }),
    });

    const sapData = await sapRes.json();
    const statusSap: string = sapData.STATUS ?? sapData.status ?? "E";
    const numeroPedido: string | null = sapData.PEDIDO || sapData.pedido || null;
    const remessa: string | null = sapData.REMESSA || sapData.remessa || null;
    const retorno: string = sapData.RETURN ?? sapData.return ?? "";
    const ok = statusSap === "S";

    // ── 4. Persistir resultado ────────────────────────────────────────────────
    const { error: insertError } = await supabase.from("lojinha_pedidos").insert({
      colaborador_id,
      cliente_sap,
      numero_pedido: numeroPedido,
      remessa,
      status: ok ? "ENVIADO" : "ERRO",
      status_sap: statusSap,
      resposta_sap: retorno,
      itens,
    });

    if (insertError) {
      return new Response(
        JSON.stringify({ ok: false, retorno: `Erro ao salvar pedido: ${insertError.message}`, numeroPedido, remessa }),
        { headers: CORS }
      );
    }

    // ── 5. Liberar carrinho e atualizar cache de estoque em caso de sucesso ───
    if (ok) {
      await supabase
        .from("lojinha_carrinho")
        .delete()
        .eq("colaborador_id", colaborador_id)
        .in("material", materiaisComZeros);

      // Decrementa o cache local para refletir o pedido até o próximo sync
      for (const item of itens as SapItem[]) {
        const materialComZeros = item.produto.padStart(18, "0");
        await supabase.rpc("decrementar_estoque_lojinha", {
          p_material: materialComZeros,
          p_quantidade: Number(item.quantidade),
        });
      }
    }

    return new Response(
      JSON.stringify({ ok, retorno, numeroPedido, remessa }),
      { headers: CORS }
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, retorno: `Erro interno: ${String(e)}`, numeroPedido: null, remessa: null }),
      { status: 500, headers: CORS }
    );
  }
});
