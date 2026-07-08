-- Suporte aos fluxos de Candidato (busca em `candidatos`/`candidaturas`) e à
-- confirmação por data de nascimento no fluxo de Funcionário.
alter table polebot_telegram_users
  add column if not exists candidato_id int references candidatos(id),
  add column if not exists verificacao_pendente jsonb;

update polebot_telegram_users set estado = 'navegando' where estado = 'aguardando_nascimento' and verificacao_pendente is null;
