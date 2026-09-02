-- ============================================================
-- GENTE POLE — Notificações push para o GESTOR
-- Reaproveita a mesma infra de 001_notifications.sql (_enviar_notificacao).
-- ============================================================

-- Setores que um gestor efetivamente enxerga: o setor do próprio cadastro
-- SEMPRE conta, somado aos setores extras associados em `gestor_setores`.
-- Mesma regra já usada no client (buscarSetoresEfetivosDoGestor).
CREATE OR REPLACE FUNCTION _eh_gestor_do_setor(p_colaborador_id INT, p_setor TEXT)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM colaboradores c
    WHERE c.id = p_colaborador_id
      AND c.eh_gestor = true
      AND (
        c.setor = p_setor
        OR EXISTS (
          SELECT 1 FROM gestor_setores gs
          WHERE gs.matricula_gestor = c.matricula
            AND gs.empresa = c.empresa
            AND gs.setor = p_setor
        )
      )
  );
$$;

-- ============================================================
-- 1. Exame agendado pelo SESMT aguardando confirmação do gestor
-- ============================================================
CREATE OR REPLACE FUNCTION _trigger_notificar_exame_aguardando_gestor()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  rec RECORD;
  v_colaborador_nome TEXT;
  v_colaborador_setor TEXT;
BEGIN
  IF NEW.status_confirmacao <> 'AGUARDANDO_GESTOR' THEN RETURN NEW; END IF;

  SELECT nome, setor INTO v_colaborador_nome, v_colaborador_setor
    FROM colaboradores WHERE id = NEW.colaborador_id;
  IF v_colaborador_setor IS NULL THEN RETURN NEW; END IF;

  FOR rec IN
    SELECT c.fcm_token FROM colaboradores c
    WHERE c.eh_gestor = true
      AND c.fcm_token IS NOT NULL AND c.fcm_token <> ''
      AND _eh_gestor_do_setor(c.id, v_colaborador_setor)
  LOOP
    PERFORM _enviar_notificacao(rec.fcm_token,
      '🩺 Exame aguardando sua confirmação',
      COALESCE(v_colaborador_nome, 'Um colaborador da sua equipe') || ' tem um exame agendado pelo SESMT. Confirme em Painel do Gestor → Exames.',
      'gestor_exames');
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_exame_aguardando_gestor ON exames;
CREATE TRIGGER trg_notificar_exame_aguardando_gestor
  AFTER INSERT ON exames
  FOR EACH ROW EXECUTE FUNCTION _trigger_notificar_exame_aguardando_gestor();

-- ============================================================
-- 2. Vaga aprovada / recusada / preenchida pelo RH
--    vagas.status_requisicao: AGUARDANDO_APROVACAO_RH | APROVADA | RECUSADA
--    vagas.status: vira 'ENCERRADA' tanto quando é recusada quanto quando
--    enche de aprovados — por isso o "preenchida" só dispara se a vaga
--    continua APROVADA (não RECUSADA) na hora que status vira ENCERRADA.
-- ============================================================
CREATE OR REPLACE FUNCTION _trigger_notificar_status_vaga()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_token TEXT;
BEGIN
  IF NEW.requisitado_por_id IS NULL THEN RETURN NEW; END IF;

  SELECT fcm_token INTO v_token FROM colaboradores WHERE id = NEW.requisitado_por_id;
  IF v_token IS NULL OR v_token = '' THEN RETURN NEW; END IF;

  IF NEW.status_requisicao = 'APROVADA' AND OLD.status_requisicao IS DISTINCT FROM 'APROVADA' THEN
    PERFORM _enviar_notificacao(v_token, '✅ Vaga aprovada',
      'Sua solicitação "' || NEW.titulo || '" foi aprovada pelo RH.', 'gestor_vagas');

  ELSIF NEW.status_requisicao = 'RECUSADA' AND OLD.status_requisicao IS DISTINCT FROM 'RECUSADA' THEN
    PERFORM _enviar_notificacao(v_token, '❌ Vaga recusada',
      'Sua solicitação "' || NEW.titulo || '" foi recusada pelo RH.', 'gestor_vagas');

  ELSIF NEW.status = 'ENCERRADA' AND OLD.status IS DISTINCT FROM 'ENCERRADA'
        AND NEW.status_requisicao = 'APROVADA' THEN
    PERFORM _enviar_notificacao(v_token, '🎉 Vaga preenchida',
      'A vaga "' || NEW.titulo || '" atingiu o número de aprovados e foi encerrada.', 'gestor_vagas');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_status_vaga ON vagas;
CREATE TRIGGER trg_notificar_status_vaga
  AFTER UPDATE ON vagas
  FOR EACH ROW EXECUTE FUNCTION _trigger_notificar_status_vaga();

-- ============================================================
-- 3. Candidato avança para "Entrevista com Gestor" no Kanban
-- ============================================================
CREATE OR REPLACE FUNCTION _trigger_notificar_entrevista_gestor()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_token TEXT;
  v_vaga_titulo TEXT;
BEGIN
  IF NEW.status <> 'ENTREV_GESTOR' OR OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  SELECT c.fcm_token, v.titulo INTO v_token, v_vaga_titulo
    FROM vagas v
    JOIN colaboradores c ON c.id = v.requisitado_por_id
   WHERE v.id = NEW.vaga_id;

  IF v_token IS NULL OR v_token = '' THEN RETURN NEW; END IF;

  PERFORM _enviar_notificacao(v_token, '📋 Candidato pronto para entrevista',
    'Um candidato para "' || COALESCE(v_vaga_titulo, 'sua vaga') || '" está aguardando sua entrevista.', 'gestor_vagas');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_entrevista_gestor ON candidaturas;
CREATE TRIGGER trg_notificar_entrevista_gestor
  AFTER UPDATE ON candidaturas
  FOR EACH ROW EXECUTE FUNCTION _trigger_notificar_entrevista_gestor();

-- ============================================================
-- 4. Pedido de feedback recebido (colaborador pediu feedback ao gestor)
-- ============================================================
CREATE OR REPLACE FUNCTION _trigger_notificar_pedido_feedback()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_token TEXT;
  v_nome_solicitante TEXT;
BEGIN
  SELECT fcm_token INTO v_token FROM colaboradores WHERE id = NEW.destinatario_id;
  IF v_token IS NULL OR v_token = '' THEN RETURN NEW; END IF;

  SELECT primeiro_nome INTO v_nome_solicitante
    FROM colaboradores WHERE id = NEW.solicitante_id;

  PERFORM _enviar_notificacao(v_token, '💬 Pedido de feedback recebido',
    COALESCE(v_nome_solicitante, 'Alguém da sua equipe') || ' pediu um feedback seu.', 'gestor_feedback');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_pedido_feedback ON feedback_solicitacoes;
CREATE TRIGGER trg_notificar_pedido_feedback
  AFTER INSERT ON feedback_solicitacoes
  FOR EACH ROW EXECUTE FUNCTION _trigger_notificar_pedido_feedback();

-- ============================================================
-- 5. Colaborador da equipe perto do fim do período de experiência
--    (90 dias após admissão — avisa o gestor exatamente 10 dias antes,
--    uma única vez, via cron diário às 08h Brasília).
-- ============================================================
CREATE OR REPLACE FUNCTION _cron_notificar_fim_experiencia_gestor()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  colab RECORD;
  gestor RECORD;
BEGIN
  FOR colab IN
    SELECT id, nome, setor
      FROM colaboradores
     WHERE data_admissao IS NOT NULL
       AND (CURRENT_DATE - data_admissao::date) = 80
  LOOP
    IF colab.setor IS NULL THEN CONTINUE; END IF;

    FOR gestor IN
      SELECT c.fcm_token FROM colaboradores c
      WHERE c.eh_gestor = true
        AND c.fcm_token IS NOT NULL AND c.fcm_token <> ''
        AND _eh_gestor_do_setor(c.id, colab.setor)
    LOOP
      PERFORM _enviar_notificacao(gestor.fcm_token,
        '⏳ Fim de experiência se aproximando',
        COALESCE(colab.nome, 'Um colaborador da sua equipe') || ' completa 90 dias de experiência em 10 dias.',
        'gestor_equipe');
    END LOOP;
  END LOOP;
END;
$$;

SELECT cron.schedule(
  'notify-fim-experiencia-gestor',
  '0 11 * * *',
  'SELECT _cron_notificar_fim_experiencia_gestor()'
);
