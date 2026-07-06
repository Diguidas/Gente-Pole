-- ============================================================
-- GENTE POLE — NOTIFICAÇÕES PUSH (FCM)
-- Execute este arquivo no SQL Editor do Supabase
-- ============================================================

-- 1. Coluna FCM token na tabela de colaboradores
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- ============================================================
-- 2. Função auxiliar para chamar a Edge Function de notificação
--    Usa pg_net (habilitado por padrão no Supabase)
-- ============================================================
CREATE OR REPLACE FUNCTION _enviar_notificacao(
  p_token  TEXT,
  p_title  TEXT,
  p_body   TEXT,
  p_route  TEXT DEFAULT 'feed'
)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_token IS NULL OR p_token = '' THEN RETURN; END IF;

  PERFORM net.http_post(
    url     := 'https://gtwtaowrhrbwnkgmauwr.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd0d3Rhb3dyaHJid25rZ21hdXdyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0NDM0MDAsImV4cCI6MjA5NjAxOTQwMH0.vqRlIQRly4-zyLfgKt6ewwcxMikpLSGAzEQKM6K_lY4'
    ),
    body    := jsonb_build_object(
      'token', p_token,
      'title', p_title,
      'body',  p_body,
      'data',  jsonb_build_object('route', p_route)
    )::text
  );
END;
$$;

-- ============================================================
-- 3. TRIGGER: post direcionado para um colaborador específico
-- ============================================================
CREATE OR REPLACE FUNCTION _trigger_notificar_post()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_dest_id  INT;
  v_token    TEXT;
  v_autor    TEXT;
BEGIN
  -- Só age em posts com destinatário específico (@colaborador:ID|...)
  IF NEW.destinatario NOT LIKE '@colaborador:%' THEN RETURN NEW; END IF;

  -- Extrai o ID do colaborador destinatário
  v_dest_id := CAST(
    SPLIT_PART(SPLIT_PART(NEW.destinatario, ':', 2), '|', 1)
    AS INT
  );

  -- Não notifica a si mesmo
  IF v_dest_id = NEW.autor_id THEN RETURN NEW; END IF;

  SELECT fcm_token INTO v_token FROM colaboradores WHERE id = v_dest_id;
  SELECT primeiro_nome INTO v_autor
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

DROP TRIGGER IF EXISTS trg_notificar_post ON feed_posts;
CREATE TRIGGER trg_notificar_post
  AFTER INSERT ON feed_posts
  FOR EACH ROW EXECUTE FUNCTION _trigger_notificar_post();

-- ============================================================
-- 4. TRIGGER: parabéns recebidos (aniversário)
-- ============================================================
CREATE OR REPLACE FUNCTION _trigger_notificar_parabens()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_token TEXT;
BEGIN
  SELECT fcm_token INTO v_token
    FROM colaboradores WHERE id = NEW.destinatario_id;

  PERFORM _enviar_notificacao(
    v_token,
    '🎉 Você recebeu parabéns!',
    COALESCE(NEW.remetente_nome, 'Um colega') || ' te enviou uma mensagem de aniversário!',
    'aniversario'
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_parabens ON mensagens_parabens;
CREATE TRIGGER trg_notificar_parabens
  AFTER INSERT ON mensagens_parabens
  FOR EACH ROW EXECUTE FUNCTION _trigger_notificar_parabens();

-- ============================================================
-- 5. TRIGGER: pesquisa ENCAMINHADA (envio criado) → notifica o público-alvo
--    Importante: dispara em `pesquisa_envios`, não em `pesquisas` — criar
--    a pesquisa não deve notificar ninguém, só encaminhá-la deve.
-- ============================================================
CREATE OR REPLACE FUNCTION _trigger_notificar_envio_pesquisa()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  rec RECORD;
BEGIN
  IF NEW.tipo_destinatario = 'todos' THEN
    FOR rec IN
      SELECT fcm_token FROM colaboradores
      WHERE fcm_token IS NOT NULL AND fcm_token <> ''
    LOOP
      PERFORM _enviar_notificacao(rec.fcm_token, '📋 Nova pesquisa disponível',
        'Você tem uma nova pesquisa para responder. Acesse Serviços → Pesquisas.', 'pesquisas');
    END LOOP;

  ELSIF NEW.tipo_destinatario = 'setor' THEN
    FOR rec IN
      SELECT fcm_token FROM colaboradores
      WHERE fcm_token IS NOT NULL AND fcm_token <> ''
        AND setor = ANY (SELECT jsonb_array_elements_text(NEW.setores_alvo))
    LOOP
      PERFORM _enviar_notificacao(rec.fcm_token, '📋 Nova pesquisa disponível',
        'Você tem uma nova pesquisa para responder. Acesse Serviços → Pesquisas.', 'pesquisas');
    END LOOP;

  ELSIF NEW.tipo_destinatario = 'agrupamentos' THEN
    FOR rec IN
      SELECT c.fcm_token FROM colaboradores c
      JOIN agrupamento_membros am ON am.colaborador_id = c.id
      WHERE c.fcm_token IS NOT NULL AND c.fcm_token <> ''
        AND am.agrupamento_id = ANY (SELECT jsonb_array_elements_text(NEW.agrupamentos_alvo)::int)
    LOOP
      PERFORM _enviar_notificacao(rec.fcm_token, '📋 Nova pesquisa disponível',
        'Você tem uma nova pesquisa para responder. Acesse Serviços → Pesquisas.', 'pesquisas');
    END LOOP;
  END IF;
  -- tipo 'colaboradores': tratado no trigger de `pesquisa_envio_colaboradores`
  -- abaixo, pois essa lista só existe numa segunda tabela, inserida depois.

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_pesquisa ON pesquisas;
DROP FUNCTION IF EXISTS _trigger_notificar_pesquisa();

DROP TRIGGER IF EXISTS trg_notificar_envio_pesquisa ON pesquisa_envios;
CREATE TRIGGER trg_notificar_envio_pesquisa
  AFTER INSERT ON pesquisa_envios
  FOR EACH ROW EXECUTE FUNCTION _trigger_notificar_envio_pesquisa();

-- Encaminhamento a colaboradores específicos (tipo_destinatario = 'colaboradores')
CREATE OR REPLACE FUNCTION _trigger_notificar_envio_colaborador()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_token TEXT;
BEGIN
  SELECT fcm_token INTO v_token FROM colaboradores WHERE id = NEW.colaborador_id;
  PERFORM _enviar_notificacao(v_token, '📋 Nova pesquisa disponível',
    'Você tem uma nova pesquisa para responder. Acesse Serviços → Pesquisas.', 'pesquisas');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_envio_colaborador ON pesquisa_envio_colaboradores;
CREATE TRIGGER trg_notificar_envio_colaborador
  AFTER INSERT ON pesquisa_envio_colaboradores
  FOR EACH ROW EXECUTE FUNCTION _trigger_notificar_envio_colaborador();

-- ============================================================
-- 6. Funções chamadas pelos crons (evita $$-aninhado no schedule)
-- ============================================================
CREATE OR REPLACE FUNCTION _cron_notificar_aniversarios()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT c.fcm_token, c.primeiro_nome
      FROM colaboradores c
     WHERE fcm_token IS NOT NULL
       AND fcm_token <> ''
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
    SELECT c.fcm_token, c.primeiro_nome,
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

-- ============================================================
-- 7. CRON: agenda as chamadas diárias às 08h Brasília (11h UTC)
-- ============================================================
SELECT cron.schedule(
  'notify-aniversarios',
  '0 11 * * *',
  'SELECT _cron_notificar_aniversarios()'
);

SELECT cron.schedule(
  'notify-aniversario-empresa',
  '0 11 * * *',
  'SELECT _cron_notificar_aniversario_empresa()'
);
