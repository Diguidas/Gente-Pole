-- ============================================================
-- GENTE POLE — CORREÇÃO: trigger de notificação de parabéns
-- Execute este arquivo no SQL Editor do Supabase.
--
-- O trigger original (001_notifications.sql) foi criado em cima da tabela
-- `mensagens_parabens`, que nunca existiu — a tabela real de mensagens de
-- aniversário sempre foi `parabens` (colaboradores.id, destinatario_id,
-- remetente_id, mensagem, criado_em, resposta, respondido_em). Como o
-- trigger apontava pra uma tabela inexistente, ele nunca disparou: nenhum
-- push de "você recebeu parabéns" foi enviado até hoje.
--
-- Esta migration substitui o trigger pela versão correta, na tabela
-- certa, buscando o nome do remetente via join (a tabela `parabens` não
-- guarda o nome, só o id).
-- ============================================================

-- `CREATE OR REPLACE FUNCTION` já troca o corpo da função sem precisar
-- dropá-la antes — e não podemos dropá-la mesmo se quiséssemos: já existe
-- um trigger em `parabens` dependendo dela (ver DROP TRIGGER mais abaixo).
CREATE OR REPLACE FUNCTION _trigger_notificar_parabens()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_token  TEXT;
  v_nome   TEXT;
BEGIN
  SELECT fcm_token INTO v_token
    FROM colaboradores WHERE id = NEW.destinatario_id;

  SELECT primeiro_nome INTO v_nome
    FROM colaboradores WHERE id = NEW.remetente_id;

  PERFORM _enviar_notificacao(
    v_token,
    '🎉 Você recebeu parabéns!',
    COALESCE(v_nome, 'Um colega') || ' te enviou uma mensagem de aniversário!',
    'aniversario'
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_parabens ON parabens;
CREATE TRIGGER trg_notificar_parabens
  AFTER INSERT ON parabens
  FOR EACH ROW EXECUTE FUNCTION _trigger_notificar_parabens();
