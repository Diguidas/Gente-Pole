-- Sessão/vínculo de cada chat do Telegram com o Polebot.
-- Uma linha por chat_id: guarda quem é (tipo + colaborador vinculado por CPF)
-- e em que ponto da árvore de opções a conversa está (estado + node atual).
create table if not exists polebot_telegram_users (
  chat_id bigint primary key,
  tipo text, -- 'cliente' | 'candidato' | 'funcionario' | 'outro'
  colaborador_id int references colaboradores(id),
  nome text,
  estado text not null default 'perguntando_tipo',
  -- estados: perguntando_tipo | perguntando_cpf | navegando | aguardando_mensagem
  node_atual_id int references polebot_nodes(id),
  caminho_ids jsonb not null default '[]', -- pilha de node ids p/ "Voltar"
  chamado_pendente jsonb, -- {categoria, caminho} enquanto aguarda a mensagem do chamado
  atualizado_em timestamptz not null default now()
);
