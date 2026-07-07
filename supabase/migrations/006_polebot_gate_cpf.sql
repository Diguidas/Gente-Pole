-- Suporte ao nó de tipo 'gate_cpf' (pergunta o CPF e só libera os filhos se
-- achar um colaborador). Antes essa lógica era hardcoded no bot do Telegram;
-- agora é um nó normal em polebot_nodes, editável visualmente no admin.
alter table polebot_telegram_users
  drop column if exists chamado_pendente;

alter table polebot_telegram_users
  alter column estado set default 'navegando';

update polebot_telegram_users set estado = 'navegando' where estado in ('perguntando_tipo', 'perguntando_cpf');

alter table polebot_telegram_users
  add column if not exists gate_pendente_id int references polebot_nodes(id),
  add column if not exists chamado_pendente jsonb;
