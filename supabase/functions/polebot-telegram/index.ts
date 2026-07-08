import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN")!;
const TG_API = `https://api.telegram.org/bot${BOT_TOKEN}`;
const APP_CONTEXTO = "telegram";
const PORTAL_VAGAS_URL = "https://vemserpolevalente.web.app";

const STATUS_LABEL: Record<string, string> = {
  INSCRITO: "Inscrito",
  TRIAGEM: "Em triagem",
  AVALIACAO_COMP: "Avaliação comportamental",
  ENTREV_RH: "Entrevista com o RH",
  ENTREV_GESTOR: "Entrevista com o gestor",
  PROPOSTA: "Proposta enviada",
  APROVADO: "Aprovado",
  REPROVADO: "Não seguiu no processo",
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// ── Helpers Telegram ──────────────────────────────────────────────────────

async function sendMessage(
  chatId: number,
  text: string,
  buttons?: { label: string; data: string }[][],
) {
  const reply_markup = buttons
    ? { inline_keyboard: buttons.map((row) => row.map((b) => ({ text: b.label, callback_data: b.data }))) }
    : undefined;

  await fetch(`${TG_API}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, text, reply_markup }),
  });
}

async function answerCallback(callbackQueryId: string) {
  await fetch(`${TG_API}/answerCallbackQuery`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ callback_query_id: callbackQueryId }),
  });
}

// ── Sessão ─────────────────────────────────────────────────────────────────
// Todo o fluxo (perguntar tipo, pedir CPF, submenus, chamados) mora na árvore
// polebot_nodes — a sessão só guarda em que ponto da árvore o chat está.

type VerificacaoPendente = {
  colaborador_id: number;
  nome: string;
  data_nascimento: string; // yyyy-mm-dd, vindo da tabela colaboradores
};

type Sessao = {
  chat_id: number;
  colaborador_id: number | null;
  candidato_id: number | null;
  nome: string | null;
  estado: string; // 'navegando' | 'aguardando_cpf' | 'aguardando_nascimento' | 'aguardando_mensagem'
  node_atual_id: number | null;
  caminho_ids: number[];
  gate_pendente_id: number | null;
  verificacao_pendente: VerificacaoPendente | null;
  chamado_pendente: { categoria: string; caminho: string | null } | null;
};

async function getSessao(chatId: number): Promise<Sessao> {
  const { data } = await supabase
    .from("polebot_telegram_users")
    .select()
    .eq("chat_id", chatId)
    .maybeSingle();

  if (data) return data as Sessao;

  const nova: Sessao = {
    chat_id: chatId,
    colaborador_id: null,
    candidato_id: null,
    nome: null,
    estado: "navegando",
    node_atual_id: null,
    caminho_ids: [],
    gate_pendente_id: null,
    verificacao_pendente: null,
    chamado_pendente: null,
  };
  await supabase.from("polebot_telegram_users").insert(nova);
  return nova;
}

async function salvarSessao(s: Sessao) {
  await supabase
    .from("polebot_telegram_users")
    .update({ ...s, atualizado_em: new Date().toISOString() })
    .eq("chat_id", s.chat_id);
}

async function resetarSessao(s: Sessao) {
  s.estado = "navegando";
  s.node_atual_id = null;
  s.caminho_ids = [];
  s.gate_pendente_id = null;
  s.verificacao_pendente = null;
  s.chamado_pendente = null;
  await salvarSessao(s);
}

// ── Árvore de opções (mesma lógica do PolebotService.listarFilhos) ─────────

async function listarFilhos(parentId: number | null) {
  let query = supabase
    .from("polebot_nodes")
    .select()
    .eq("ativo", true)
    .in("app_contexto", [APP_CONTEXTO, "todos"]);

  query = parentId == null ? query.is("parent_id", null) : query.eq("parent_id", parentId);

  const { data } = await query.order("ordem", { ascending: true });
  return data ?? [];
}

async function buscarNode(id: number) {
  const { data } = await supabase.from("polebot_nodes").select().eq("id", id).single();
  return data;
}

async function enviarMenu(chatId: number, s: Sessao) {
  const filhos = await listarFilhos(s.node_atual_id);
  const botoes = filhos.map((n: any) => [{ label: n.label, data: `n:${n.id}` }]);
  if (s.caminho_ids.length > 0) botoes.push([{ label: "⬅️ Voltar", data: "v" }]);

  const titulo = s.node_atual_id ? (await buscarNode(s.node_atual_id))?.label : "Como posso ajudar?";
  await sendMessage(chatId, titulo ?? "Escolha uma opção:", botoes);
}

// ── Entrar num nó — decide o que fazer conforme o tipo ─────────────────────

async function entrarNoNode(chatId: number, s: Sessao, node: any) {
  const destino = node.destino ?? "colaborador"; // 'colaborador' | 'candidato'
  const jaIdentificado = destino === "candidato" ? !!s.candidato_id : !!s.colaborador_id;

  if (node.tipo === "gate_cpf" && !jaIdentificado) {
    s.estado = "aguardando_cpf";
    s.gate_pendente_id = node.id;
    await salvarSessao(s);
    const pergunta = destino === "candidato"
      ? "Digite seu CPF (só números) pra eu buscar sua inscrição:"
      : "Digite seu CPF (só números) pra confirmar que você é colaborador:";
    await sendMessage(chatId, pergunta);
    return;
  }

  if (node.tipo === "submenu" || node.tipo === "gate_cpf") {
    s.caminho_ids = [...s.caminho_ids, s.node_atual_id].filter((x) => x != null) as number[];
    s.node_atual_id = node.id;
    await salvarSessao(s);
    await enviarMenu(chatId, s);
    return;
  }

  if (node.tipo === "navegar") {
    await sendMessage(chatId, "Essa opção só está disponível dentro do app 📱");
    await enviarMenu(chatId, s);
    return;
  }

  // tipo === 'chamado'
  if (node.pedir_mensagem) {
    s.estado = "aguardando_mensagem";
    s.chamado_pendente = { categoria: node.destino ?? node.label, caminho: node.label };
    await salvarSessao(s);
    await sendMessage(chatId, "Digite sua mensagem:");
    return;
  }

  await criarChamado(s, node.destino ?? node.label, node.label, null);
  await sendMessage(chatId, "✅ Chamado registrado! Alguém vai te responder em breve.");
  await resetarSessao(s);
  await enviarMenu(chatId, s);
}

async function tratarCpf(chatId: number, s: Sessao, textoRecebido: string) {
  const cpf = textoRecebido.replace(/\D/g, "");
  const gateNode = s.gate_pendente_id ? await buscarNode(s.gate_pendente_id) : null;
  const destino = gateNode?.destino ?? "colaborador";

  if (destino === "candidato") {
    await tratarCpfCandidato(chatId, s, cpf);
    return;
  }

  const { data: colaborador } = await supabase
    .from("colaboradores")
    .select("id, nome, data_nascimento")
    .eq("cpf", cpf)
    .maybeSingle();

  if (!colaborador) {
    await sendMessage(chatId, "Não encontrei esse CPF. Confere e digita novamente:");
    return;
  }

  s.estado = "aguardando_nascimento";
  s.verificacao_pendente = {
    colaborador_id: colaborador.id,
    nome: colaborador.nome,
    data_nascimento: colaborador.data_nascimento,
  };
  await salvarSessao(s);
  await sendMessage(chatId, "Pra confirmar sua identidade, digite sua data de nascimento (dd/mm/aaaa):");
}

async function tratarDataNascimento(chatId: number, s: Sessao, textoRecebido: string) {
  const pendente = s.verificacao_pendente;
  if (!pendente) {
    s.estado = "navegando";
    await salvarSessao(s);
    await enviarMenu(chatId, s);
    return;
  }

  const digitado = textoRecebido.replace(/\D/g, ""); // ddmmaaaa
  const real = new Date(`${pendente.data_nascimento}T00:00:00Z`);
  const realFmt =
    String(real.getUTCDate()).padStart(2, "0") +
    String(real.getUTCMonth() + 1).padStart(2, "0") +
    String(real.getUTCFullYear());

  if (digitado !== realFmt) {
    await sendMessage(chatId, "Essa data não confere com o que temos aqui. Tenta de novo (dd/mm/aaaa):");
    return;
  }

  s.colaborador_id = pendente.colaborador_id;
  s.nome = pendente.nome;
  s.estado = "navegando";
  s.verificacao_pendente = null;
  const gateId = s.gate_pendente_id;
  s.gate_pendente_id = null;
  await salvarSessao(s);
  await sendMessage(chatId, `Identidade confirmada, ${pendente.nome.split(" ")[0]}! 👋`);

  const gate = gateId ? await buscarNode(gateId) : null;
  if (gate) await entrarNoNode(chatId, s, gate);
  else await enviarMenu(chatId, s);
}

async function tratarCpfCandidato(chatId: number, s: Sessao, cpf: string) {
  const { data: candidato } = await supabase
    .from("candidatos")
    .select("id, nome")
    .eq("cpf", cpf)
    .maybeSingle();

  if (!candidato) {
    await sendMessage(
      chatId,
      `Não encontrei nenhuma inscrição com esse CPF.\nConfira nossas vagas abertas aqui: ${PORTAL_VAGAS_URL}`,
    );
    s.estado = "navegando";
    s.gate_pendente_id = null;
    await salvarSessao(s);
    await enviarMenu(chatId, s);
    return;
  }

  s.candidato_id = candidato.id;
  s.nome = candidato.nome;
  s.estado = "navegando";
  const gateId = s.gate_pendente_id;
  s.gate_pendente_id = null;
  await salvarSessao(s);

  await mostrarCandidaturas(chatId, candidato.id, candidato.nome);

  const gate = gateId ? await buscarNode(gateId) : null;
  if (gate) await entrarNoNode(chatId, s, gate);
  else await enviarMenu(chatId, s);
}

async function mostrarCandidaturas(chatId: number, candidatoId: number, nome: string) {
  const primeiroNome = nome.split(" ")[0];
  const { data: candidaturas } = await supabase
    .from("candidaturas")
    .select("status, vagas(titulo)")
    .eq("candidato_id", candidatoId);

  if (!candidaturas || candidaturas.length === 0) {
    await sendMessage(
      chatId,
      `Oi, ${primeiroNome}! Não encontrei nenhuma candidatura sua no momento.\nConfira nossas vagas abertas aqui: ${PORTAL_VAGAS_URL}`,
    );
    return;
  }

  const linhas = candidaturas.map((c: any) => {
    const titulo = c.vagas?.titulo ?? "Vaga";
    const status = STATUS_LABEL[c.status] ?? c.status;
    return `• ${titulo} — ${status}`;
  });

  await sendMessage(chatId, `Oi, ${primeiroNome}! Aqui estão suas candidaturas:\n\n${linhas.join("\n")}`);
}

async function tratarVoltar(chatId: number, s: Sessao) {
  const novoCaminho = [...s.caminho_ids];
  s.node_atual_id = novoCaminho.pop() ?? null;
  s.caminho_ids = novoCaminho;
  await salvarSessao(s);
  await enviarMenu(chatId, s);
}

async function tratarMensagemChamado(chatId: number, s: Sessao, mensagem: string) {
  if (!s.chamado_pendente) return;
  await criarChamado(s, s.chamado_pendente.categoria, s.chamado_pendente.caminho, mensagem);
  await sendMessage(chatId, "✅ Chamado registrado! Alguém vai te responder em breve.");
  await resetarSessao(s);
  await enviarMenu(chatId, s);
}

async function criarChamado(s: Sessao, categoria: string, caminho: string | null, mensagem: string | null) {
  await supabase.from("polebot_chamados").insert({
    origem_app: "telegram",
    solicitante_tipo: s.colaborador_id ? "colaborador" : "outro",
    colaborador_id: s.colaborador_id,
    categoria,
    caminho,
    mensagem,
  });
}

// ── Webhook ────────────────────────────────────────────────────────────────

serve(async (req) => {
  try {
    const update = await req.json();

    if (update.callback_query) {
      const cq = update.callback_query;
      const chatId = cq.message.chat.id;
      const data = cq.data as string;
      const s = await getSessao(chatId);

      await answerCallback(cq.id);

      if (data === "v") {
        await tratarVoltar(chatId, s);
      } else if (data.startsWith("n:")) {
        const node = await buscarNode(Number(data.slice(2)));
        if (node) await entrarNoNode(chatId, s, node);
      }
      return new Response("ok");
    }

    if (update.message) {
      const chatId = update.message.chat.id;
      const texto = (update.message.text ?? "").trim();
      const s = await getSessao(chatId);

      if (texto === "/start") {
        await resetarSessao(s);
        await sendMessage(chatId, "Oi! Eu sou o Polebot 👋 Como posso ajudar?");
        await enviarMenu(chatId, s);
      } else if (s.estado === "aguardando_cpf") {
        await tratarCpf(chatId, s, texto);
      } else if (s.estado === "aguardando_nascimento") {
        await tratarDataNascimento(chatId, s, texto);
      } else if (s.estado === "aguardando_mensagem") {
        await tratarMensagemChamado(chatId, s, texto);
      } else {
        await enviarMenu(chatId, s);
      }
      return new Response("ok");
    }

    return new Response("ok");
  } catch (e) {
    console.error(e);
    return new Response("ok"); // sempre 200 p/ o Telegram não ficar re-tentando
  }
});
