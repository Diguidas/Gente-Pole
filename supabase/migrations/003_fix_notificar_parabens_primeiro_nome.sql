-- ============================================================
-- GENTE POLE — CORREÇÃO: coluna inexistente no trigger de parabéns
-- Execute este arquivo no SQL Editor do Supabase.
--
-- 002_fix_notificar_parabens.sql recriou o trigger `trg_notificar_parabens`
-- mas manteve `SELECT primeiro_nome ...`, coluna que nunca existiu em
-- `colaboradores` (só existe `nome`). Isso quebrava com
-- PostgrestException: column "primeiro_nome" does not exist
-- em TODO INSERT na tabela `parabens` — ou seja, ninguém conseguia
-- enviar parabéns.
-- ============================================================

CREATE OR REPLACE FUNCTION _trigger_notificar_parabens()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_token  TEXT;
  v_nome   TEXT;
BEGIN
  SELECT fcm_token INTO v_token
    FROM colaboradores WHERE id = NEW.destinatario_id;

  SELECT SPLIT_PART(nome, ' ', 1) INTO v_nome
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
