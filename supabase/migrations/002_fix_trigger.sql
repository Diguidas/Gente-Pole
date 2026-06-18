-- ============================================================
-- DIAGNÓSTICO — rode primeiro para checar o estado atual
-- ============================================================

-- 1. Verifica se a coluna fcm_token existe
SELECT column_name FROM information_schema.columns
WHERE table_name = 'colaboradores' AND column_name = 'fcm_token';

-- 2. Verifica se pg_net está habilitado
SELECT * FROM pg_extension WHERE extname = 'pg_net';

-- 3. Verifica se os triggers foram criados
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_name IN ('trg_notificar_post', 'trg_notificar_parabens', 'trg_notificar_pesquisa');

-- 4. Verifica se algum colaborador tem fcm_token salvo
SELECT id, nome, LEFT(fcm_token, 20) AS token_preview
FROM colaboradores
WHERE fcm_token IS NOT NULL
LIMIT 5;

-- ============================================================
-- CORREÇÃO: recria o trigger com coluna correta (nome, não primeiro_nome)
-- ============================================================

CREATE OR REPLACE FUNCTION _trigger_notificar_post()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_dest_id  INT;
  v_token    TEXT;
  v_autor    TEXT;
BEGIN
  IF NEW.destinatario NOT LIKE '@colaborador:%' THEN RETURN NEW; END IF;

  v_dest_id := CAST(
    SPLIT_PART(SPLIT_PART(NEW.destinatario, ':', 2), '|', 1)
    AS INT
  );

  IF v_dest_id = NEW.autor_id THEN RETURN NEW; END IF;

  SELECT fcm_token INTO v_token FROM colaboradores WHERE id = v_dest_id;
  -- Usa SPLIT_PART(nome, ' ', 1) em vez de primeiro_nome (não existe como coluna)
  SELECT SPLIT_PART(nome, ' ', 1) INTO v_autor
    FROM colaboradores WHERE id = NEW.autor_id;

  PERFORM _enviar_notificacao(
    v_token,
    'Nova mensagem para você 💬',
    COALESCE(v_autor, 'Alguém') || ' enviou uma mensagem para você.',
    'feed'
  );

  RETURN NEW;
END;
$$;

-- Recria as funções de cron também com a coluna correta
CREATE OR REPLACE FUNCTION _cron_notificar_aniversarios()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT c.fcm_token, SPLIT_PART(c.nome, ' ', 1) AS primeiro_nome
      FROM colaboradores c
     WHERE fcm_token IS NOT NULL
       AND fcm_token <> ''
       AND data_nascimento IS NOT NULL
       AND EXTRACT(MONTH FROM data_nascimento::DATE) = EXTRACT(MONTH FROM NOW() AT TIME ZONE 'America/Sao_Paulo')
       AND EXTRACT(DAY   FROM data_nascimento::DATE) = EXTRACT(DAY   FROM NOW() AT TIME ZONE 'America/Sao_Paulo')
  LOOP
    PERFORM _enviar_notificacao(
      rec.fcm_token,
      '🎂 Feliz aniversário, ' || rec.primeiro_nome || '!',
      'A Pole Alimentos deseja um dia incrível para você! 🎉',
      'aniversario'
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION _cron_notificar_aniversario_empresa()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT c.fcm_token,
           SPLIT_PART(c.nome, ' ', 1) AS primeiro_nome,
           EXTRACT(YEAR FROM NOW() AT TIME ZONE 'America/Sao_Paulo')
           - EXTRACT(YEAR FROM c.data_admissao::DATE) AS anos
      FROM colaboradores c
     WHERE fcm_token IS NOT NULL
       AND fcm_token <> ''
       AND data_admissao IS NOT NULL
       AND EXTRACT(MONTH FROM c.data_admissao::DATE) = EXTRACT(MONTH FROM NOW() AT TIME ZONE 'America/Sao_Paulo')
       AND EXTRACT(DAY   FROM c.data_admissao::DATE) = EXTRACT(DAY   FROM NOW() AT TIME ZONE 'America/Sao_Paulo')
       AND c.data_admissao::DATE < (NOW() AT TIME ZONE 'America/Sao_Paulo')::DATE
  LOOP
    PERFORM _enviar_notificacao(
      rec.fcm_token,
      '🏆 Parabéns pelo aniversário de empresa, ' || rec.primeiro_nome || '!',
      CAST(rec.anos AS TEXT) || ' ano(s) com a Pole Alimentos. Obrigado por fazer parte desta história! 🧡',
      'feed'
    );
  END LOOP;
END;
$$;
