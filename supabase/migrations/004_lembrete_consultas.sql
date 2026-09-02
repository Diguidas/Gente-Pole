-- ============================================================
-- GENTE POLE — Lembrete de consulta (push 15min antes + na hora)
-- Massoterapia, Nutricionista e Fisioterapia hoje não avisam ninguém
-- quando o colaborador se inscreve/tem consulta agendada. Este cron
-- roda a cada minuto e dispara push nos dois momentos, usando a mesma
-- infra de notificação (_enviar_notificacao) já criada em 001_notifications.sql.
-- ============================================================

-- Flags pra nunca mandar o mesmo lembrete duas vezes.
ALTER TABLE massoterapia_agendamentos
  ADD COLUMN IF NOT EXISTS lembrete_15min_enviado boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS lembrete_hora_enviado  boolean NOT NULL DEFAULT false;

ALTER TABLE nutricionista_agendamentos
  ADD COLUMN IF NOT EXISTS lembrete_15min_enviado boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS lembrete_hora_enviado  boolean NOT NULL DEFAULT false;

ALTER TABLE fisioterapia_sessoes
  ADD COLUMN IF NOT EXISTS lembrete_15min_enviado boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS lembrete_hora_enviado  boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION _cron_lembrete_consultas()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  rec RECORD;
  v_agendado_ts timestamptz;
  v_minutos_restantes numeric;
BEGIN
  -- ── Massoterapia ─────────────────────────────────────────────────────────
  FOR rec IN
    SELECT m.id, c.fcm_token, m.data, m.horario,
           m.lembrete_15min_enviado, m.lembrete_hora_enviado
      FROM massoterapia_agendamentos m
      JOIN colaboradores c ON c.id = m.colaborador_id
     WHERE m.status = 'AGENDADO'
       AND (m.lembrete_15min_enviado = false OR m.lembrete_hora_enviado = false)
       AND c.fcm_token IS NOT NULL AND c.fcm_token <> ''
  LOOP
    v_agendado_ts := (rec.data::date + rec.horario::time) AT TIME ZONE 'America/Sao_Paulo';
    v_minutos_restantes := EXTRACT(EPOCH FROM (v_agendado_ts - now())) / 60;

    IF NOT rec.lembrete_15min_enviado AND v_minutos_restantes BETWEEN 14 AND 15 THEN
      PERFORM _enviar_notificacao(rec.fcm_token, '💆 Massoterapia em 15 minutos',
        'Sua sessão de massoterapia é às ' || to_char(rec.horario::time, 'HH24:MI') || '.', 'servicos');
      UPDATE massoterapia_agendamentos SET lembrete_15min_enviado = true WHERE id = rec.id;
    ELSIF NOT rec.lembrete_hora_enviado AND v_minutos_restantes BETWEEN 0 AND 1 THEN
      PERFORM _enviar_notificacao(rec.fcm_token, '💆 Sua massoterapia é agora',
        'Dirija-se ao local da sessão.', 'servicos');
      UPDATE massoterapia_agendamentos SET lembrete_hora_enviado = true WHERE id = rec.id;
    END IF;
  END LOOP;

  -- ── Nutricionista ────────────────────────────────────────────────────────
  FOR rec IN
    SELECT n.id, c.fcm_token, n.data, n.horario,
           n.lembrete_15min_enviado, n.lembrete_hora_enviado
      FROM nutricionista_agendamentos n
      JOIN colaboradores c ON c.id = n.colaborador_id
     WHERE n.status = 'AGENDADO'
       AND (n.lembrete_15min_enviado = false OR n.lembrete_hora_enviado = false)
       AND c.fcm_token IS NOT NULL AND c.fcm_token <> ''
  LOOP
    v_agendado_ts := (rec.data::date + rec.horario::time) AT TIME ZONE 'America/Sao_Paulo';
    v_minutos_restantes := EXTRACT(EPOCH FROM (v_agendado_ts - now())) / 60;

    IF NOT rec.lembrete_15min_enviado AND v_minutos_restantes BETWEEN 14 AND 15 THEN
      PERFORM _enviar_notificacao(rec.fcm_token, '🥗 Nutricionista em 15 minutos',
        'Sua consulta é às ' || to_char(rec.horario::time, 'HH24:MI') || '.', 'servicos');
      UPDATE nutricionista_agendamentos SET lembrete_15min_enviado = true WHERE id = rec.id;
    ELSIF NOT rec.lembrete_hora_enviado AND v_minutos_restantes BETWEEN 0 AND 1 THEN
      PERFORM _enviar_notificacao(rec.fcm_token, '🥗 Sua consulta com o nutricionista é agora',
        'Dirija-se ao local da consulta.', 'servicos');
      UPDATE nutricionista_agendamentos SET lembrete_hora_enviado = true WHERE id = rec.id;
    END IF;
  END LOOP;

  -- ── Fisioterapia ─────────────────────────────────────────────────────────
  FOR rec IN
    SELECT s.id, c.fcm_token, s.data, s.horario,
           s.lembrete_15min_enviado, s.lembrete_hora_enviado
      FROM fisioterapia_sessoes s
      JOIN fisioterapia_casos fc ON fc.id = s.caso_id
      JOIN colaboradores c ON c.id = fc.colaborador_id
     WHERE s.status = 'AGENDADO'
       AND (s.lembrete_15min_enviado = false OR s.lembrete_hora_enviado = false)
       AND c.fcm_token IS NOT NULL AND c.fcm_token <> ''
  LOOP
    v_agendado_ts := (rec.data::date + rec.horario::time) AT TIME ZONE 'America/Sao_Paulo';
    v_minutos_restantes := EXTRACT(EPOCH FROM (v_agendado_ts - now())) / 60;

    IF NOT rec.lembrete_15min_enviado AND v_minutos_restantes BETWEEN 14 AND 15 THEN
      PERFORM _enviar_notificacao(rec.fcm_token, '🏃 Fisioterapia em 15 minutos',
        'Sua sessão é às ' || to_char(rec.horario::time, 'HH24:MI') || '.', 'servicos');
      UPDATE fisioterapia_sessoes SET lembrete_15min_enviado = true WHERE id = rec.id;
    ELSIF NOT rec.lembrete_hora_enviado AND v_minutos_restantes BETWEEN 0 AND 1 THEN
      PERFORM _enviar_notificacao(rec.fcm_token, '🏃 Sua fisioterapia é agora',
        'Dirija-se ao local da sessão.', 'servicos');
      UPDATE fisioterapia_sessoes SET lembrete_hora_enviado = true WHERE id = rec.id;
    END IF;
  END LOOP;
END;
$$;

SELECT cron.schedule(
  'lembrete-consultas',
  '* * * * *',
  'SELECT _cron_lembrete_consultas()'
);
