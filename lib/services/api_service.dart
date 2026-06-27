import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:gentepole/models/comunicado_model.dart';
import 'package:gentepole/models/feed_post_model.dart';
import 'package:gentepole/models/lojinha_model.dart';
import 'package:gentepole/models/massoterapia_model.dart';
import 'package:gentepole/models/vaga_model.dart';
import 'package:gentepole/screens/nutricionista/nutricionista_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/colaborador_model.dart';
import '../models/aniversariante_model.dart';

/// Serviço central de API.
/// TODA comunicação com o banco passa por aqui.
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _client = Supabase.instance.client;

  // Horário de Brasília (UTC-3, sem DST desde 2019) — independe do fuso do dispositivo
  static DateTime _brasilia() =>
      DateTime.now().toUtc().subtract(const Duration(hours: 3));

  // O app admin salva o horário de Brasília sem converter para UTC.
  // O PostgreSQL armazena como UTC-3h (3h a menos do real).
  // Compensamos adicionando 3h ao valor lido.
  static DateTime _parseComunicadoTs(String s) {
    final dt = DateTime.parse(s);
    if (dt.isUtc) return dt.add(const Duration(hours: 3));
    return dt.toUtc().add(const Duration(hours: 3));
  }

  // ─── Sessão ──────────────────────────────────────────────────────────────────

  static const _kMatriculaKey = 'sessao_matricula';

  ColaboradorModel? colaboradorAtual;

  Future<void> salvarSessao(String matricula) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMatriculaKey, matricula);
  }

  Future<void> limparSessao() async {
    colaboradorAtual = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMatriculaKey);
  }

  /// Tenta restaurar a sessão salva. Retorna true se conseguiu.
  Future<bool> restaurarSessao() async {
    final prefs = await SharedPreferences.getInstance();
    final matricula = prefs.getString(_kMatriculaKey);
    if (matricula == null) return false;

    final data = await _client
        .from('colaboradores')
        .select()
        .eq('matricula', matricula)
        .maybeSingle();
    if (data == null) {
      await prefs.remove(_kMatriculaKey);
      return false;
    }
    colaboradorAtual = ColaboradorModel.fromJson(data);
    return true;
  }

  // ─── Auth ─────────────────────────────────────────────────────────────────────

  Future<({String status, ColaboradorModel? colaborador})> verificarCpf(
    String cpf,
  ) async {
    final cpfLimpo = cpf.replaceAll(RegExp(r'[^0-9]'), '');

    final resultColaborador = await _client
        .from('colaboradores')
        .select()
        .eq('cpf', cpfLimpo)
        .maybeSingle();

    if (resultColaborador == null) {
      // Verifica se é um fornecedor cadastrado em usuarios_app (usa matricula)
      final resultFornecedor = await _client
          .from('usuarios_app')
          .select('id')
          .eq('matricula', cpf.trim())
          .eq('ativo', true)
          .maybeSingle();
      if (resultFornecedor != null) {
        return (status: 'FORNECEDOR', colaborador: null);
      }
      return (status: 'NAO_ENCONTRADO', colaborador: null);
    }

    final colaborador = ColaboradorModel.fromJson(resultColaborador);
    colaboradorAtual = colaborador;

    final resultAuth = await _client
        .from('usuarios_auth')
        .select('id')
        .eq('matricula', colaborador.matricula)
        .maybeSingle();

    return resultAuth == null
        ? (status: 'PRIMEIRO_ACESSO', colaborador: colaborador)
        : (status: 'CADASTRADO', colaborador: colaborador);
  }

  Future<bool> criarConta({
    required String matricula,
    required String senha,
    required String dataNascimento,
  }) async {
    try {
      await _client.from('usuarios_auth').insert({
        'matricula': matricula,
        'senha_hash': _hash(senha),
        'data_nascimento_verificacao': dataNascimento,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> validarLogin({
    required String matricula,
    required String senha,
  }) async {
    final data = await _client
        .from('usuarios_auth')
        .select('senha_hash')
        .eq('matricula', matricula)
        .maybeSingle();
    if (data == null) return false;
    return data['senha_hash'] == _hash(senha);
  }

  /// Salva (ou atualiza) o FCM token do colaborador logado no banco.
  Future<void> salvarFcmToken(String token) async {
    final id = colaboradorAtual?.id;
    if (id == null) return;
    try {
      await _client
          .from('colaboradores')
          .update({'fcm_token': token})
          .eq('id', id);
    } catch (_) {}
  }

  // ─── Aniversariantes ──────────────────────────────────────────────────────────

  /// Todos os aniversariantes do mês — hoje primeiro, depois por dia crescente.
  Future<List<AniversarianteModel>> buscarAniversariantesMes() async {
    final data = await _client
        .from('v_aniversariantes_mes')
        .select()
        .order('eh_hoje', ascending: false)
        .order('dia_nascimento', ascending: true);

    return (data as List)
        .map((e) => AniversarianteModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Parabéns recebidos por um colaborador no ano corrente.
  Future<List<ParabensModel>> buscarParabens(int destinatarioId) async {
    final data = await _client
        .from('parabens')
        .select('*, remetente:remetente_id(nome)')
        .eq('destinatario_id', destinatarioId)
        .gte('criado_em', '${DateTime.now().year}-01-01')
        .order('criado_em', ascending: false);

    return (data as List)
        .map((e) => ParabensModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Envia parabéns. Retorna true se salvou.
  Future<bool> enviarParabens({
    required int destinatarioId,
    required String mensagem,
  }) async {
    try {
      await _client.from('parabens').insert({
        'destinatario_id': destinatarioId,
        'remetente_id': colaboradorAtual?.id,
        'mensagem': mensagem.trim(),
      });
      return true;
    } catch (e) {
      debugPrint('ERRO enviarParabens: $e');
      return false;
    }
  }

  // ─── Colaboradores ────────────────────────────────────────────────────────────

  Future<ColaboradorModel?> buscarSupervisor(int supervisorId) async {
    final data = await _client
        .from('colaboradores')
        .select()
        .eq('id', supervisorId)
        .maybeSingle();
    if (data == null) return null;
    return ColaboradorModel.fromJson(data);
  }

  // Adicione este método dentro da classe ApiService,
  // na seção "── Colaboradores ──"

  /// Retorna todos os colaboradores do mesmo setor (CENTROCUSTO) do usuário logado.
  /// Ordenados por nome, excluindo o próprio usuário.
  Future<List<ColaboradorModel>> buscarColegasDoSetor() async {
    final meuSetor = colaboradorAtual?.setor;
    if (meuSetor == null || meuSetor.isEmpty) return [];

    final data = await _client
        .from('colaboradores')
        .select()
        .eq('setor', meuSetor)
        .neq('id', colaboradorAtual!.id) // exclui o próprio usuário
        .order('nome', ascending: true);

    return (data as List)
        .map((e) => ColaboradorModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────────

  String _hash(String s) => sha256.convert(utf8.encode(s)).toString();

  // PASSO 2 — Adicione estes métodos dentro da classe ApiService:

  // ─── Comunicados ─────────────────────────────────────────────────────────────

  /// Últimos 4 comunicados (para o card de destaque + lista na Home)
  /// Filtra localmente uma lista de registros pelo campo tipo_destinatario,
  /// usando os dados do colaborador logado e seus agrupamentos.
  Future<List<Map<String, dynamic>>> _filtrarDestinatarios(
    List<Map<String, dynamic>> lista,
  ) async {
    final colab = colaboradorAtual;
    if (colab == null) return [];

    // Busca os agrupamentos do colaborador uma única vez
    final membros = await _client
        .from('agrupamento_membros')
        .select('agrupamento_id')
        .eq('colaborador_id', colab.id);
    final meusAgrupamentos =
        (membros as List).map((e) => e['agrupamento_id'] as int).toSet();

    List<dynamic> _parseList(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) return raw;
      if (raw is String) {
        try {
          final decoded = jsonDecode(raw);
          return decoded is List ? decoded : [];
        } catch (_) {
          return [];
        }
      }
      return [];
    }

    return lista.where((item) {
      final tipo = item['tipo_destinatario'] as String? ?? 'todos';
      switch (tipo) {
        case 'todos':
          return true;
        case 'setor':
          return _parseList(item['setores_alvo']).contains(colab.setor);
        case 'colaboradores':
          final colabs = _parseList(item['colaboradores_alvo']);
          return colabs.contains(colab.id) ||
              colabs.contains(colab.id.toString());
        case 'agrupamentos':
          final grupos = _parseList(item['agrupamentos_alvo']);
          return grupos.any((g) => meusAgrupamentos.contains(
              g is int ? g : int.tryParse(g.toString()) ?? -1));
        default:
          return true;
      }
    }).toList();
  }

  Future<List<ComunicadoModel>> buscarUltimosComunicados() async {
    final data = await _client
        .from('comunicados')
        .select()
        .order('criado_em', ascending: false);

    final filtrados = await _filtrarDestinatarios(
      (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );

    return filtrados
        .take(4)
        .map((e) => ComunicadoModel.fromJson(e))
        .toList();
  }

  /// Todos os comunicados (para a tela de Comunicados)
  Future<List<ComunicadoModel>> buscarTodosComunicados() async {
    final data = await _client
        .from('comunicados')
        .select()
        .order('criado_em', ascending: false);

    final filtrados = await _filtrarDestinatarios(
      (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );

    return filtrados.map((e) => ComunicadoModel.fromJson(e)).toList();
  }

  // ─── Auth — Alterar senha ─────────────────────────────────────────────────

  /// Valida a senha atual e, se correta, salva a nova.
  /// Retorna true se alterou com sucesso.
  Future<bool> alterarSenha({
    required String senhaAtual,
    required String novaSenha,
  }) async {
    final matricula = colaboradorAtual?.matricula;
    if (matricula == null) return false;

    // Verifica senha atual
    final ok = await validarLogin(matricula: matricula, senha: senhaAtual);
    if (!ok) return false;

    try {
      await _client
          .from('usuarios_auth')
          .update({'senha_hash': _hash(novaSenha)})
          .eq('matricula', matricula);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── FASE 5 — Gestor ──────────────────────────────────────────────────────────
  // Adicione estes métodos dentro da classe ApiService, em api_service.dart
  // Imports necessários no topo do arquivo:
  //   import '../models/vaga_model.dart';

  // ─── Vagas do gestor ──────────────────────────────────────────────────────────

  /// Cria requisição de vaga. Envia com status_requisicao = AGUARDANDO_APROVACAO_RH
  /// Retorna os templates ativos cadastrados pelo RH.
  Future<List<Map<String, dynamic>>> listarTemplatesGestor() async {
    final res = await _client
        .from('ats_templates')
        .select('id, titulo, departamento, tipo_contrato, tipo_vaga, teste_pratico, descricao')
        .eq('ativo', true)
        .order('titulo');
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<String?> uploadDocAprovacaoDiretoria({
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final path = 'aprovacoes_diretoria/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      await _client.storage.from('documentos').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: _mimeType(fileName), upsert: true),
      );
      return _client.storage.from('documentos').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  String _mimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => 'application/octet-stream',
    };
  }

  Future<bool> solicitarVaga(VagaModel vaga) async {
    try {
      await _client.from('vagas').insert(vaga.toInsertMap());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Lista as requisições do gestor logado (por supervisorId ou pelo id direto)
  Future<List<VagaModel>> listarMinhasRequisicoes(int gestorId) async {
    final data = await _client
        .from('vagas')
        .select()
        .eq('requisitado_por_id', gestorId)
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => VagaModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Candidaturas — visão do gestor ──────────────────────────────────────────

  /// Candidatos na fase ENTREV_GESTOR de uma vaga
  Future<List<CandidaturaGestorModel>> listarCandidatosGestor(
    int vagaId,
  ) async {
    final data = await _client
        .from('candidaturas')
        .select('*, candidatos(*), admissoes(id, status)')
        .eq('vaga_id', vagaId)
        .inFilter('status', [
          'INSCRITO', 'TRIAGEM', 'AVALIACAO_COMP', 'ENTREV_RH',
          'ENTREV_GESTOR', 'PROPOSTA', 'APROVADO',
        ])
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => CandidaturaGestorModel.fromJson(e as Map<String, dynamic>))
        .where((c) => c.admissaoStatus != 'CONCLUIDO')
        .toList();
  }

  /// Gestor aprova candidato na entrevista (move para PROPOSTA)
  Future<bool> aprovarEntrevistaGestor({
    required int candidaturaId,
    required int gestorId,
    String? observacao,
  }) async {
    try {
      await _client
          .from('candidaturas')
          .update({'status': 'PROPOSTA'})
          .eq('id', candidaturaId);

      await _client.from('candidatura_historico').insert({
        'candidatura_id': candidaturaId,
        'status_anterior': 'ENTREV_GESTOR',
        'status_novo': 'PROPOSTA',
        'movido_por_id': gestorId.toString(),
        'movido_por_tipo': 'GESTOR',
        'observacao': observacao,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Gestor reprova candidato na entrevista (exige motivo)
  Future<bool> reprovarEntrevistaGestor({
    required int candidaturaId,
    required int gestorId,
    required String motivo,
  }) async {
    try {
      await _client
          .from('candidaturas')
          .update({'status': 'REPROVADO', 'motivo_reprovacao': motivo})
          .eq('id', candidaturaId);

      await _client.from('candidatura_historico').insert({
        'candidatura_id': candidaturaId,
        'status_anterior': 'ENTREV_GESTOR',
        'status_novo': 'REPROVADO',
        'movido_por_id': gestorId.toString(),
        'movido_por_tipo': 'GESTOR',
        'observacao': motivo,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Gestor lança resultado de teste prático
  Future<bool> lancarResultadoTeste({
    required int candidaturaId,
    required String resultado, // 'APROVADO' | 'REPROVADO'
  }) async {
    try {
      await _client
          .from('candidaturas')
          .update({'teste_pratico_status': resultado})
          .eq('id', candidaturaId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Gestor aprova proposta salarial (move para APROVADO)
  Future<bool> aprovarProposta({
    required int candidaturaId,
    required int gestorId,
    String? observacao,
  }) async {
    try {
      await _client
          .from('candidaturas')
          .update({'status': 'APROVADO'})
          .eq('id', candidaturaId);

      await _client.from('candidatura_historico').insert({
        'candidatura_id': candidaturaId,
        'status_anterior': 'PROPOSTA',
        'status_novo': 'APROVADO',
        'movido_por_id': gestorId.toString(),
        'movido_por_tipo': 'GESTOR',
        'observacao': observacao,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Retorna true se o colaborador logado está no agrupamento "Integração".
  Future<bool> verificarSeEhIntegracao() async {
    final colaborador = colaboradorAtual;
    if (colaborador == null) return false;
    try {
      final ag = await _client
          .from('agrupamentos')
          .select('id')
          .eq('nome', 'Integração')
          .maybeSingle();
      if (ag == null) return false;

      final membro = await _client
          .from('agrupamento_membros')
          .select('id')
          .eq('agrupamento_id', ag['id'] as int)
          .eq('colaborador_id', colaborador.id)
          .maybeSingle();
      return membro != null;
    } catch (_) {
      return false;
    }
  }

  /// Busca todas as admissões com status INTEGRACAO, com dados do candidato.
  Future<List<Map<String, dynamic>>> buscarAdmisoesIntegracao() async {
    final res = await _client
        .from('admissoes')
        .select('*, candidatos(nome, email, telefone, cidade, estado)')
        .eq('status', 'INTEGRACAO')
        .order('criado_em', ascending: true);
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Marca a integração como concluída, mudando o status para CONCLUIDO.
  Future<bool> concluirIntegracao(int admissaoId) async {
    try {
      await _client
          .from('admissoes')
          .update({'status': 'CONCLUIDO'})
          .eq('id', admissaoId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Busca o próximo exame agendado e não realizado do colaborador logado.
  Future<Map<String, dynamic>?> buscarProximoExame() async {
    final id = colaboradorAtual?.id;
    if (id == null) return null;
    final hoje = DateTime.now().toIso8601String().substring(0, 10);
    final res = await _client
        .from('exames')
        .select('id, tipo, clinica, data_agendamento')
        .eq('colaborador_id', id)
        .isFilter('data_realizacao', null)
        .gte('data_agendamento', hoje)
        .order('data_agendamento', ascending: true)
        .limit(1)
        .maybeSingle();
    return res;
  }

  /// Acompanhamento da admissão de um candidato aprovado
  Future<Map<String, dynamic>?> buscarStatusAdmissao(int candidaturaId) async {
    final data = await _client
        .from('admissoes')
        .select(
          'status, cargo_admitido, setor_admitido, data_inicio, salario_acordado',
        )
        .eq('candidatura_id', candidaturaId)
        .maybeSingle();
    return data;
  }

  // ─── Lojinha ──────────────────────────────────────────────────────────────────

  /// Busca produtos ativos com estoque > 0

  // ─── Massoterapia ─────────────────────────────────────────────────────────────
  // Adicione estes métodos dentro da classe ApiService, em api_service.dart
  // Import necessário no topo do arquivo:
  //   import '../models/massoterapia_model.dart';

  /// Retorna APENAS o próximo dia disponível para massoterapia.
  /// Inclui hoje se o dia da semana estiver ativo.
  Future<List<String>> buscarDiasDisponiveisMassoterapia() async {
    final configDias = await _client
        .from('massoterapia_dias_disponiveis')
        .select('dia_semana')
        .eq('ativo', true);

    final diasAtivos = (configDias as List)
        .map((e) => e['dia_semana'] as int)
        .toSet();

    if (diasAtivos.isEmpty) return [];

    final agora = _brasilia();
    final hoje = DateTime(agora.year, agora.month, agora.day);

    for (var i = 0; i < 14; i++) {
      final d = hoje.add(Duration(days: i));
      if (diasAtivos.contains(d.weekday)) {
        final str =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        return [str];
      }
    }
    return [];
  }

  /// Todos os agendamentos com status AGENDADO nas próximas 4 semanas.
  /// Inclui join com colaboradores para exibir nome, matrícula e setor.
  Future<List<MassoterapiaAgendamentoModel>>
  buscarAgendamentosMassoterapia() async {
    final hoje = _brasilia();
    final fim = hoje.add(const Duration(days: 27));
    final hojeStr =
        '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';
    final fimStr =
        '${fim.year}-${fim.month.toString().padLeft(2, '0')}-${fim.day.toString().padLeft(2, '0')}';

    final data = await _client
        .from('massoterapia_agendamentos')
        .select('*, colaboradores(nome, matricula, setor)')
        .neq('status', 'CANCELADO')
        .gte('data', hojeStr)
        .lte('data', fimStr)
        .order('data', ascending: true)
        .order('horario', ascending: true);

    return (data as List)
        .map(
          (e) =>
              MassoterapiaAgendamentoModel.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  /// Configuração de vagas por setor. Retorna null se o setor não tiver config.
  Future<MassoterapiaConfigSetorModel?> buscarConfigSetorMassoterapia(
    String setor,
  ) async {
    final data = await _client
        .from('massoterapia_config_setor')
        .select()
        .eq('setor', setor)
        .eq('ativo', true)
        .maybeSingle();
    if (data == null) return null;
    return MassoterapiaConfigSetorModel.fromJson(data);
  }

  /// Cria um agendamento para o colaborador logado.
  /// Retorna false se o slot já estiver ocupado ou o setor estiver lotado.
  Future<bool> agendarMassoterapia({
    required String data,
    required String horario,
  }) async {
    final colaborador = colaboradorAtual;
    if (colaborador == null) return false;
    try {
      await _client.from('massoterapia_agendamentos').insert({
        'colaborador_id': colaborador.id,
        'data': data,
        'horario': horario,
        'status': 'AGENDADO',
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cancela um agendamento (muda status para CANCELADO).
  Future<bool> cancelarMassoterapia(int agendamentoId) async {
    try {
      await _client
          .from('massoterapia_agendamentos')
          .update({'status': 'CANCELADO'})
          .eq('id', agendamentoId)
          .eq('colaborador_id', colaboradorAtual!.id); // segurança: só o dono
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Retorna true se o colaborador logado está no agrupamento "Gestores".
  Future<bool> verificarSeEhGestor() async {
    final colaborador = colaboradorAtual;
    if (colaborador == null) return false;
    try {
      // 1. Busca o id do agrupamento "Gestores"
      final ag = await _client
          .from('agrupamentos')
          .select('id')
          .eq('nome', 'Gestores')
          .maybeSingle();
      if (ag == null) return false;

      final agrupamentoId = ag['id'] as int;

      // 2. Verifica se o colaborador está nesse agrupamento
      final membro = await _client
          .from('agrupamento_membros')
          .select('id')
          .eq('agrupamento_id', agrupamentoId)
          .eq('colaborador_id', colaborador.id)
          .maybeSingle();
      return membro != null;
    } catch (_) {
      return false;
    }
  }

  /// Busca todos os colaboradores do mesmo setor do usuário logado.
  Future<List<ColaboradorModel>> buscarMinhaEquipe() async {
    final setor = colaboradorAtual?.setor;
    if (setor == null || setor.isEmpty) return [];
    final res = await _client
        .from('colaboradores')
        .select()
        .eq('setor', setor)
        .order('nome');
    return (res as List)
        .map((e) => ColaboradorModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Busca a mensagem institucional da empresa para o aniversariante.
  /// Retorna o registro ativo mais recente da tabela
  /// [mensagens_empresa_aniversario], ou null se não houver nenhum.
  Future<Map<String, dynamic>?> buscarMensagemEmpresaAniversario() async {
    final res = await _client
        .from('mensagens_empresa_aniversario')
        .select('titulo, corpo')
        .eq('ativo', true)
        .order('id', ascending: false)
        .limit(1)
        .maybeSingle();
    return res;
  }

  /// Busca as mensagens de parabéns recebidas pelo colaborador logado hoje.
  Future<List<Map<String, dynamic>>> buscarMensagensParabens() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return [];

    final res = await _client
        .from('parabens')
        .select('*, colaboradores!remetente_id(nome, setor, foto_url)')
        .eq('destinatario_id', meuId)
        .order('criado_em', ascending: true);

    return (res as List).map((m) {
      final map = Map<String, dynamic>.from(m as Map); // ← cast aqui
      final col = map['colaboradores'] as Map?;
      return {
        ...map,
        'remetente_nome': col?['nome'] ?? 'Colega',
        'remetente_setor': col?['setor'],
        'remetente_foto_url': col?['foto_url'],
      };
    }).toList();
  }

  // Cole estes métodos dentro da classe ApiService, na seção de Lojinha.
  // Imports necessários no topo do api_service.dart:
  //   import '../models/lojinha_model.dart';

  // ─── Lojinha ──────────────────────────────────────────────────────────────────

  /// Busca produtos ativos com estoque > 0, filtrando pelos centros visíveis do funcionário.
  Future<List<LojinhaProdutoModel>> buscarProdutosLojinha({
    List<String> centros = const [],
  }) async {
    var query = _client
        .from('lojinha_produtos')
        .select()
        .eq('ativo', true)
        .gt('estoque', 0);

    if (centros.isNotEmpty) {
      query = query.inFilter('centro', centros);
    }

    final results = await Future.wait([
      query.order('descricao', ascending: true),
      _client.from('lojinha_fotos').select('material, foto_url'),
      _client.from('lojinha_regras').select('material, dias_semana, limite_qtd, periodo_limite'),
    ]);

    final fotos = <String, String>{
      for (final f in (results[1] as List))
        (f['material'] as String): (f['foto_url'] as String),
    };

    final regras = <String, Map<String, dynamic>>{
      for (final r in (results[2] as List))
        (r['material'] as String): Map<String, dynamic>.from(r as Map),
    };

    return (results[0] as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final matSemZeros = (m['material'] as String).replaceAll(RegExp(r'^0+'), '');
      m['foto_url'] = fotos[matSemZeros];
      final regra = regras[matSemZeros] ?? regras[m['material'] as String? ?? ''];
      m['dias_semana'] = regra?['dias_semana'];
      m['limite_qtd'] = regra?['limite_qtd'];
      m['periodo_limite'] = regra?['periodo_limite'];
      return LojinhaProdutoModel.fromJson(m);
    }).toList();
  }

  /// Dados do funcionário no SAP: limites + histórico de pedidos
  Future<LojinhaFuncionarioModel?> buscarDadosFuncionarioLojinha() async {
    final clienteSap = colaboradorAtual?.clienteSap;
    if (clienteSap == null) return null;

    try {
      // Remove zeros à esquerda para o parâmetro da URL
      final codCliente = clienteSap.replaceAll(RegExp(r'^0+'), '');
      final res = await _client.functions.invoke(
        'lojinha-funcionario',
        method: HttpMethod.get,
        queryParameters: {'codcliente': codCliente},
      );
      final map = res.data as Map<String, dynamic>;
      if (map['ok'] != true) return null;
      return LojinhaFuncionarioModel.fromJson(
        map['data'] as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Itens de um pedido específico
  Future<LojinhaPedidoDetalheModel?> buscarItensPedido(String ordem) async {
    try {
      final res = await _client.functions.invoke(
        'lojinha-itens-pedido',
        method: HttpMethod.get,
        queryParameters: {'ordem': ordem},
      );
      final map = res.data as Map<String, dynamic>;
      if (map['ok'] != true) return null;
      return LojinhaPedidoDetalheModel.fromJson(
        map['data'] as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Estoque visível de uma lista de produtos (cache SAP − carrinhos ativos de outros)
  Future<Map<String, int>> buscarEstoqueVisivel(List<LojinhaProdutoModel> produtos) async {
    final colaborador = colaboradorAtual!;
    try {
      final res = await _client.functions.invoke(
        'get-estoque-produto',
        body: {
          'colaborador_id': colaborador.id,
          'materiais': produtos.map((p) => {
            'material': p.material,
            'centro':   p.centro ?? '',
            'deposito': p.deposito ?? '',
          }).toList(),
        },
      );
      debugPrint('buscarEstoqueVisivel raw: ${res.data}');
      final data = res.data as Map<String, dynamic>;
      debugPrint('buscarEstoqueVisivel ok=${data['ok']} estoques=${data['estoques']}');
      if (data['ok'] != true) return {};
      final map = {
        for (final e in (data['estoques'] as List))
          e['material'] as String: (e['estoque_disponivel'] as num).toInt(),
      };
      debugPrint('buscarEstoqueVisivel map=$map');
      return map;
    } catch (e) {
      debugPrint('buscarEstoqueVisivel erro: $e');
      return {};
    }
  }

  /// Adiciona/atualiza item no carrinho ativo (quantidade=0 remove)
  Future<({bool ok, String? motivo, int? estoqueDisponivel})>
  adicionarAoCarrinho({
    required String material,
    required int quantidade,
  }) async {
    final colaborador = colaboradorAtual!;
    try {
      final res = await _client.functions.invoke(
        'adicionar-carrinho',
        body: {
          'colaborador_id': colaborador.id,
          'material': material,
          'quantidade': quantidade,
        },
      );
      final data = res.data as Map<String, dynamic>;
      return (
        ok: data['ok'] as bool,
        motivo: data['motivo'] as String?,
        estoqueDisponivel: data['estoque_disponivel'] != null
            ? (data['estoque_disponivel'] as num).toInt()
            : null,
      );
    } catch (_) {
      return (ok: true, motivo: null, estoqueDisponivel: null);
    }
  }

  /// Envia pedido via Edge Function — pode gerar múltiplos pedidos (um por centro)
  Future<({bool ok, String retorno, List<LojinhaPedidoCentroResult> pedidos})>
  finalizarPedidoLojinha({required List<CarrinhoItem> itens}) async {
    final colaborador = colaboradorAtual!;
    final hoje = DateTime.now();
    final datacriacao =
        '${hoje.year}${hoje.month.toString().padLeft(2, '0')}${hoje.day.toString().padLeft(2, '0')}';

    final res = await _client.functions.invoke(
      'lojinha-pedido',
      body: {
        'colaborador_id': colaborador.id,
        'cliente_sap': colaborador.clienteSap,
        'datacriacao': datacriacao,
        'itens': itens.map((i) => i.toSapItem()).toList(),
      },
    );

    final data = res.data as Map<String, dynamic>;
    final pedidosRaw = data['pedidos'] as List? ?? [];
    final pedidos = pedidosRaw
        .map((p) => LojinhaPedidoCentroResult.fromJson(p as Map<String, dynamic>))
        .toList();
    return (
      ok: data['ok'] as bool,
      retorno: data['retorno'] as String,
      pedidos: pedidos,
    );
  }

  // ─── Cole estes métodos no api_service.dart DO APP, dentro da classe ApiService ───
  // Substitua também o método atualizarPresencaMassoterapia existente (se houver)

  /// Busca agendamentos de um dia pelo formato 'yyyy-MM-dd'.
  /// Requer a view v_massoterapia_agenda no Supabase (veja SQL de migração).
  Future<List<Map<String, dynamic>>> buscarAgendamentosData(String data) async {
    final res = await _client
        .from('v_massoterapia_agenda')
        .select()
        .eq('data', data)
        .order('horario', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Atualiza status de presença e, opcionalmente, salva a URL da assinatura.
  Future<bool> atualizarPresencaMassoterapia({
    required int id,
    required String status, // 'VEIO' | 'NAO_VEIO'
    String? assinaturaUrl,
  }) async {
    assert(status == 'VEIO' || status == 'NAO_VEIO');
    try {
      await _client
          .from('massoterapia_agendamentos')
          .update({
            'status': status,
            if (assinaturaUrl != null) 'assinatura_url': assinaturaUrl,
          })
          .eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Faz upload da assinatura PNG no Storage e retorna a URL pública.
  /// Bucket: 'assinaturas-massoterapia' (crie no Supabase com acesso público).
  Future<String> uploadAssinaturaMassoterapia({
    required int agendamentoId,
    required Uint8List bytes,
  }) async {
    final path =
        'massoterapia/$agendamentoId/${DateTime.now().millisecondsSinceEpoch}.png';
    await _client.storage
        .from('assinaturas-massoterapia')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        );
    return _client.storage.from('assinaturas-massoterapia').getPublicUrl(path);
  }

  /// Login pela matrícula do fornecedor (massoterapeuta).
  /// Retorna o map do usuário se válido, null caso contrário.
  Future<Map<String, dynamic>?> loginFornecedor({
    required String matricula, // ex: '9999'
    required String senha,
  }) async {
    final senhaHash = _hash(senha);
    final res = await _client
        .from('usuarios_app')
        .select()
        .eq('matricula', matricula.trim())
        .eq('senha_hash', senhaHash)
        .eq('ativo', true)
        .maybeSingle();
    return res;
  }

  // ─── Foto de perfil ──────────────────────────────────────────────────────────

  /// Faz upload da foto, salva a URL no banco e atualiza o colaboradorAtual.
  /// Retorna a URL pública ou null em caso de erro.
  Future<String?> uploadFotoPerfil(Uint8List bytes) async {
    final id = colaboradorAtual?.id;
    if (id == null) return null;

    try {
      final path = 'colaboradores/$id.jpg';
      await _client.storage
          .from('fotos-colaboradores')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final url = _client.storage
          .from('fotos-colaboradores')
          .getPublicUrl(path);

      // Força cache-bust para que o app recarregue a imagem nova
      final urlFinal = '$url?t=${DateTime.now().millisecondsSinceEpoch}';

      await _client
          .from('colaboradores')
          .update({'foto_url': urlFinal})
          .eq('id', id);

      // Atualiza instância local
      colaboradorAtual = ColaboradorModel(
        id: colaboradorAtual!.id,
        matricula: colaboradorAtual!.matricula,
        nome: colaboradorAtual!.nome,
        setor: colaboradorAtual!.setor,
        cargo: colaboradorAtual!.cargo,
        cpf: colaboradorAtual!.cpf,
        dataNascimento: colaboradorAtual!.dataNascimento,
        dataAdmissao: colaboradorAtual!.dataAdmissao,
        supervisorId: colaboradorAtual!.supervisorId,
        clienteSap: colaboradorAtual!.clienteSap,
        fotoUrl: urlFinal,
      );

      return urlFinal;
    } catch (_) {
      return null;
    }
  }

  // ─── Humor do Dia ────────────────────────────────────────────

  /// Retorna o registro de humor do colaborador para hoje, ou null se não registrou.
  Future<Map<String, dynamic>?> buscarHumorHoje() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return null;
    final hoje = DateTime.now();
    final dataStr =
        '${hoje.year}-${hoje.month.toString().padLeft(2, "0")}-${hoje.day.toString().padLeft(2, "0")}';
    return await _client
        .from('humor_registros')
        .select()
        .eq('colaborador_id', meuId)
        .eq('data', dataStr)
        .maybeSingle();
  }

  /// Salva o humor do dia. Retorna false se já registrado ou erro.
  Future<bool> registrarHumor({required int nivel, String? motivo}) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return false;
    try {
      final hoje = DateTime.now();
      final dataStr =
          '${hoje.year}-${hoje.month.toString().padLeft(2, "0")}-${hoje.day.toString().padLeft(2, "0")}';
      await _client.from('humor_registros').insert({
        'colaborador_id': meuId,
        'nivel': nivel,
        'data': dataStr,
        if (motivo != null && motivo.isNotEmpty) 'motivo': motivo,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Retorna o próximo exame periódico agendado para o colaborador (sem realização).
  Future<Map<String, dynamic>?> buscarProximoExamePeriodico() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return null;
    try {
      final hoje = DateTime.now();
      final hojeStr =
          '${hoje.year}-${hoje.month.toString().padLeft(2, "0")}-${hoje.day.toString().padLeft(2, "0")}';
      final res = await _client
          .from('exames')
          .select('id, tipo, clinica, data_agendamento, observacoes')
          .eq('colaborador_id', meuId)
          .eq('tipo', 'periodico')
          .gte('data_agendamento', hojeStr)
          .isFilter('data_realizacao', null)
          .order('data_agendamento', ascending: true)
          .limit(1)
          .maybeSingle();
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Busca o banner configurado para o nível informado.
  Future<Map<String, dynamic>?> buscarBannerHumor(int nivel) async {
    return await _client
        .from('humor_banners')
        .select()
        .eq('nivel', nivel)
        .eq('ativo', true)
        .maybeSingle();
  }

  // ─── Feedback ─────────────────────────────────────────────────────

  /// Envia feedback para um colaborador.
  Future<bool> enviarFeedback({
    required int destinatarioId,
    required String texto,
    required bool anonimo,
  }) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return false;
    if (meuId == destinatarioId) return false; // sem auto-feedback
    try {
      await _client.from('feedbacks').insert({
        'remetente_id': meuId,
        'destinatario_id': destinatarioId,
        'texto': texto.trim(),
        'anonimo': anonimo,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Feedbacks recebidos pelo colaborador logado (via view).
  Future<List<Map<String, dynamic>>> buscarFeedbacksRecebidos() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return [];
    final res = await _client
        .from('v_feedbacks_recebidos')
        .select()
        .eq('destinatario_id', meuId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Conta feedbacks não lidos (para badge).
  Future<int> contarFeedbacksNaoLidos() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return 0;
    final res = await _client
        .from('feedbacks')
        .select('id')
        .eq('destinatario_id', meuId)
        .eq('lido', false);
    return (res as List).length;
  }

  /// Marca um feedback como lido.
  Future<void> marcarFeedbackLido(int feedbackId) async {
    await _client
        .from('feedbacks')
        .update({'lido': true})
        .eq('id', feedbackId)
        .eq('destinatario_id', colaboradorAtual!.id);
  }

  /// Busca todos os colaboradores para a lista de destinatários.
  Future<List<Map<String, dynamic>>> buscarTodosColaboradores() async {
    final meuId = colaboradorAtual?.id;
    final res = await _client
        .from('colaboradores')
        .select('id, nome, setor, cargo')
        .neq('id', meuId ?? 0)
        .order('nome', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Lista pesquisas disponíveis filtradas por destinatário,
  /// com campo ja_respondeu para bloquear resposta dupla.
  Future<List<Map<String, dynamic>>> buscarPesquisasDisponiveis() async {
    final colaboradorId = colaboradorAtual?.id;

    final res = await _client
        .from('pesquisas')
        .select()
        .eq('ativa', true)
        .order('criado_em', ascending: false);

    final filtradas = await _filtrarDestinatarios(
      (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );

    if (colaboradorId == null) return filtradas;

    // Busca todas as pesquisas já respondidas pelo colaborador de uma vez
    final ids = filtradas.map((p) => p['id'] as int).toList();
    if (ids.isEmpty) return filtradas;

    final respondidas = await _client
        .from('pesquisa_respostas')
        .select('pesquisa_id')
        .eq('colaborador_id', colaboradorId)
        .inFilter('pesquisa_id', ids);

    final respondidosSet =
        (respondidas as List).map((e) => e['pesquisa_id'] as int).toSet();

    return filtradas.map((p) {
      return {
        ...p,
        'ja_respondeu': respondidosSet.contains(p['id'] as int),
      };
    }).toList();
  }

  /// Busca as perguntas de uma pesquisa, em ordem.
  Future<List<Map<String, dynamic>>> buscarPerguntasPesquisa(
    int pesquisaId,
  ) async {
    final res = await _client
        .from('pesquisa_perguntas')
        .select()
        .eq('pesquisa_id', pesquisaId)
        .order('ordem', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Envia todas as respostas de uma pesquisa.
  /// [respostas] é um Map de pergunta_id → valor (String, int ou bool).
  Future<bool> responderPesquisa({
    required int pesquisaId,
    required bool anonima,
    required Map<int, dynamic> respostas,
  }) async {
    final meuId = colaboradorAtual?.id;
    try {
      // 1. Insere cabeçalho
      final cabecalho = await _client
          .from('pesquisa_respostas')
          .insert({
            'pesquisa_id': pesquisaId,
            'colaborador_id': anonima ? null : meuId,
          })
          .select('id')
          .single();
      final respostaId = cabecalho['id'] as int;

      // 2. Insere itens
      final itens = respostas.entries.map((e) {
        final mapa = <String, dynamic>{
          'resposta_id': respostaId,
          'pergunta_id': e.key,
        };
        if (e.value is String) mapa['valor_texto'] = e.value;
        if (e.value is int) mapa['valor_numero'] = e.value;
        if (e.value is bool) mapa['valor_booleano'] = e.value;
        return mapa;
      }).toList();

      await _client.from('pesquisa_resposta_itens').insert(itens);
      return true;
    } catch (_) {
      return false;
    }
  }



  // ─── Eu Crio Oportunidades ────────────────────────────────────────────────

  Future<List<VagaModel>> listarVagasAbertas() async {
    final data = await _client
        .from('vagas')
        .select()
        .eq('status', 'ABERTA')
        .eq('status_requisicao', 'APROVADA')
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => VagaModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> inscreverColaboradorNaVaga({
    required int colaboradorId,
    required int vagaId,
    required String nome,
    required String cpf,
    required String email,
    required String telefone,
  }) async {
    final cpfLimpo = cpf.replaceAll(RegExp(r'\D'), '');
    String candidatoId;
    final existente = await _client
        .from('candidatos')
        .select('id')
        .eq('cpf', cpfLimpo)
        .maybeSingle();
    if (existente != null) {
      candidatoId = existente['id'].toString();
    } else {
      final novo = await _client.from('candidatos').insert({
        'nome': nome,
        'cpf': cpfLimpo,
        'email': email,
        'telefone': telefone,
        'cidade': '',
        'estado': '',
        'area_interesse': '',
        'anos_experiencia': 0,
        'ultimo_emprego': '',
        'resumo_profissional': 'Colaborador interno',
      }).select('id').single();
      candidatoId = novo['id'].toString();
    }
    final jaInscrito = await _client
        .from('candidaturas')
        .select('id')
        .eq('candidato_id', int.parse(candidatoId))
        .eq('vaga_id', vagaId)
        .maybeSingle();
    if (jaInscrito != null) throw Exception('já inscrito');
    await _client.from('candidaturas').insert({
      'candidato_id': int.parse(candidatoId),
      'vaga_id': vagaId,
      'status': 'INSCRITO',
      'salario_esperado': 0,
      'tipo_origem': 'COLABORADOR',
    });
  }

  /// Busca um candidato pelo CPF (só dígitos). Retorna null se não encontrado.
  Future<Map<String, dynamic>?> buscarCandidatoPorCpf(String cpf) async {
    final data = await _client
        .from('candidatos')
        .select('id, nome, area_interesse, telefone')
        .eq('cpf', cpf)
        .maybeSingle();
    return data;
  }

  /// Vincula o colaborador como indicador de um candidato já cadastrado.
  /// Atualiza a candidatura existente para a vaga ou cria uma nova.
  Future<void> vincularIndicacao({
    required int candidatoId,
    required int vagaId,
    required int colaboradorId,
  }) async {
    // Verifica se já existe candidatura para esse candidato+vaga
    final existente = await _client
        .from('candidaturas')
        .select('id, indicado_por_id')
        .eq('candidato_id', candidatoId)
        .eq('vaga_id', vagaId)
        .maybeSingle();

    if (existente != null) {
      // Já tem candidatura — atualiza o indicador
      if (existente['indicado_por_id'] != null) throw Exception('já indicado');
      await _client
          .from('candidaturas')
          .update({'indicado_por_id': colaboradorId, 'tipo_origem': 'INDICACAO'})
          .eq('id', existente['id'] as int);
    } else {
      // Sem candidatura ainda — cria vinculada ao indicador
      await _client.from('candidaturas').insert({
        'candidato_id': candidatoId,
        'vaga_id':       vagaId,
        'status':        'INSCRITO',
        'salario_esperado': 0,
        'tipo_origem':   'INDICACAO',
        'indicado_por_id': colaboradorId,
      });
    }
  }

  Future<void> indicarCandidato({
    required int colaboradorId,
    required int vagaId,
    required String nomeIndicado,
    String cpfIndicado = '',
    String telefoneIndicado = '',
  }) async {
    final candidato = await _client.from('candidatos').insert({
      'nome': nomeIndicado,
      'cpf': cpfIndicado,
      'email': '',
      'telefone': telefoneIndicado,
      'cidade': '',
      'estado': '',
      'area_interesse': '',
      'anos_experiencia': 0,
      'ultimo_emprego': '',
      'resumo_profissional': '',
    }).select('id').single();
    await _client.from('candidaturas').insert({
      'candidato_id': candidato['id'] as int,
      'vaga_id': vagaId,
      'status': 'INSCRITO',
      'salario_esperado': 0,
      'tipo_origem': 'INDICACAO',
      'indicado_por_id': colaboradorId,
    });
  }

  // ════════════════════════════════════════════════════════════════════════════
// ADICIONAR NO api_service.dart — cole cada bloco na seção correspondente
// ════════════════════════════════════════════════════════════════════════════

// ─── Nutricionista ───────────────────────────────────────────────────────────
// Cole após os métodos de massoterapia

  Future<List<String>> buscarDiasDisponiveisNutricionista() async {
    // Reutiliza a mesma tabela de configuração de dias disponíveis.
    // Crie uma tabela nutricionista_config_dias (data DATE, ativo BOOL)
    // ou use a lógica de dias úteis que já existe na massoterapia.
    // Ajuste a query abaixo conforme seu schema:
    final hoje = _brasilia();
    final hojeStr =
        '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';

    final data = await _client
        .from('nutricionista_config_dias')
        .select('data')
        .eq('ativo', true)
        .gte('data', hojeStr)
        .order('data', ascending: true);

    return (data as List).map((e) => e['data'] as String).toList();
  }

  Future<List<NutricionistaAgendamentoModel>> buscarAgendamentosNutricionista() async {
    // Busca os agendamentos dos próximos 30 dias para montar a grade de horários.
    final hoje = _brasilia();
    final limite = hoje.add(const Duration(days: 30));
    final hojeStr =
        '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';
    final limiteStr =
        '${limite.year}-${limite.month.toString().padLeft(2, '0')}-${limite.day.toString().padLeft(2, '0')}';

    final data = await _client
        .from('nutricionista_agendamentos')
        .select('*, colaboradores(nome, matricula, setor)')
        .gte('data', hojeStr)
        .lte('data', limiteStr)
        .neq('status', 'CANCELADO')
        .order('data', ascending: true)
        .order('horario', ascending: true);
    // assinatura_url já vem no select '*'

    return (data as List)
        .map((e) => NutricionistaAgendamentoModel.fromJson(
            e as Map<String, dynamic>))
        .toList();
  }

  Future<bool> agendarNutricionista({
    required String data,
    required String horario,
  }) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return false;
    try {
      await _client.from('nutricionista_agendamentos').insert({
        'colaborador_id': meuId,
        'matricula': colaboradorAtual!.matricula,
        'data': data,
        'horario': horario,
        'status': 'AGENDADO',
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelarNutricionista(int agendamentoId) async {
    try {
      await _client
          .from('nutricionista_agendamentos')
          .update({'status': 'CANCELADO'}).eq('id', agendamentoId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> atualizarPresencaNutricionista({
    required int id,
    required String status,
    String? assinaturaUrl,
  }) async {
    try {
      final dados = <String, dynamic>{'status': status};
      if (assinaturaUrl != null) dados['assinatura_url'] = assinaturaUrl;
      await _client
          .from('nutricionista_agendamentos')
          .update(dados)
          .eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> uploadAssinaturaNutricionista({
    required int agendamentoId,
    required Uint8List bytes,
  }) async {
    final path =
        'nutricionista/$agendamentoId/${DateTime.now().millisecondsSinceEpoch}.png';
    await _client.storage
        .from('assinaturas-massoterapia')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        );
    return _client.storage
        .from('assinaturas-massoterapia')
        .getPublicUrl(path);
  }

// ─── Conexões do Bem ─────────────────────────────────────────────────────────
// Cole após os métodos de nutricionista

  Future<bool> salvarVoluntarioConexoes({
    required String tamanho,
    required String whatsapp,
  }) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return false;
    try {
      await _client.from('conexoes_voluntarios').insert({
        'colaborador_id': meuId,
        'matricula': colaboradorAtual!.matricula,
        'tamanho_camisa': tamanho,
        'whatsapp': whatsapp,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> buscarVoluntarioCadastrado() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return null;
    try {
      final res = await _client
          .from('conexoes_voluntarios')
          .select('id, tamanho_camisa, whatsapp, criado_em')
          .eq('colaborador_id', meuId)
          .maybeSingle();
      return res;
    } catch (_) {
      return null;
    }
  }

  Future<bool> salvarInstituicaoConexoes({
    required String nome,
    required String telefoneResponsavel,
  }) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return false;
    try {
      await _client.from('conexoes_instituicoes').insert({
        'indicado_por_id': meuId,
        'matricula': colaboradorAtual!.matricula,
        'nome_instituicao': nome,
        'telefone_responsavel': telefoneResponsavel,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

// ─── Ouvidoria ────────────────────────────────────────────────────────────────
// Cole após os métodos de conexões

  Future<bool> salvarOuvidoria({
    required String ocorrido,
    required String telefone,
    required String sugestao,
  }) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return false;
    try {
      await _client.from('ouvidoria').insert({
        'colaborador_id': meuId,
        'matricula': colaboradorAtual!.matricula,
        'ocorrido': ocorrido,
        'telefone_contato': telefone,
        'sugestao': sugestao.isEmpty ? null : sugestao,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

// ════════════════════════════════════════════════════════════════════════════
// TRECHO PARA ADICIONAR AO api_service.dart
// Cole os imports no topo do arquivo e os métodos dentro da classe ApiService,
// na seção de Comunicados/Feed.
// ════════════════════════════════════════════════════════════════════════════
//
// IMPORTS adicionais no topo:
//   import 'dart:io';
//   import '../models/feed_post_model.dart';
//
// ════════════════════════════════════════════════════════════════════════════
 
// ─── Feed ─────────────────────────────────────────────────────────────────────
 
  /// Busca os posts do feed mais recentes (paginado).
  ///
  /// Filtra por destinatário: o colaborador vê posts dirigidos a 'todos',
  /// ao seu setor, ou diretamente a ele.
  Future<List<FeedPostModel>> buscarFeed({int pagina = 0}) async {
    final colab = colaboradorAtual;
    if (colab == null) return [];

    // Traz posts aprovados visíveis + os próprios posts (qualquer status)
    final data = await _client
        .from('feed_posts')
        .select('*, autor:colaboradores(nome, foto_url, cargo)')
        .or('status.eq.aprovado,autor_id.eq.${colab.id}')
        .order('criado_em', ascending: false)
        .range(pagina * 20, pagina * 20 + 39);

    final posts = (data as List)
        .map((e) => FeedPostModel.fromJson(e as Map<String, dynamic>))
        .where((p) {
          // Comunicados vêm da tabela dedicada — exclui os que podem estar em feed_posts
          if (p.tipo == 'comunicado') return false;
          // O próprio autor sempre vê seus posts (com qualquer status)
          if (p.autorId == colab.id) return true;
          // Posts de terceiros só aparecem se aprovados
          if (!p.isAprovado) return false;
          if (p.destinatario == 'todos') return true;
          if (p.destinatario == '@setor:${colab.setor}') return true;
          // Suporta '@colaborador:42' e '@colaborador:42|NOME'
          if (p.destinatario.startsWith('@colaborador:${colab.id}|') ||
              p.destinatario == '@colaborador:${colab.id}') return true;
          return false;
        })
        .toList();

    // Mescla comunicados da tabela comunicados (só na primeira página)
    if (pagina == 0) {
      final comData = await _client
          .from('comunicados')
          .select()
          .order('criado_em', ascending: false)
          .limit(30);

      final filtrados = await _filtrarDestinatarios(
        (comData as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );

      final comunicados = filtrados.map((c) {
        final titulo = c['titulo'] as String?;
        final descricao = c['descricao'] as String?;
        final conteudo = [
          if (titulo != null && titulo.isNotEmpty) titulo,
          if (descricao != null && descricao.isNotEmpty) descricao,
        ].join('\n');
        return FeedPostModel(
          id: -(c['id'] as int),
          autorId: null,
          tipo: 'comunicado',
          conteudo: conteudo.isNotEmpty ? conteudo : null,
          imagemUrl: c['foto_url'] as String?,
          destinatario: 'todos',
          criadoEm: _parseComunicadoTs(c['criado_em'] as String),
        );
      }).toList();

      final tudo = [...posts, ...comunicados];
      tudo.sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
      return tudo.take(40).toList();
    }

    return posts;
  }
 
  /// Cria um novo post no feed.
  ///
  /// [imagemBytes] e [imagemNome] são opcionais (post sem foto).
  /// [destinatario] pode ser 'todos', '@setor:TI', '@colaborador:42'.
  Future<bool> criarPost({
    required String conteudo,
    required String destinatario,
    List<int>? imagemBytes,
    String? imagemNome,
  }) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return false;
    try {
      String? imagemUrl;
 
      // Faz upload da imagem se houver
      if (imagemBytes != null && imagemNome != null) {
        final ext = imagemNome.split('.').last.toLowerCase();
        final caminho = 'posts/$meuId/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await _client.storage
            .from('feed-imagens')
            .uploadBinary(
              caminho,
              Uint8List.fromList(imagemBytes),
              fileOptions: FileOptions(contentType: 'image/$ext', upsert: false),
            );
        imagemUrl = _client.storage.from('feed-imagens').getPublicUrl(caminho);
      }
 
      // Posts para 'todos' precisam de aprovação do RH; demais vão direto
      final status = destinatario == 'todos' ? 'pendente' : 'aprovado';
      await _client.from('feed_posts').insert({
        'autor_id': meuId,
        'tipo': 'post',
        'conteudo': conteudo.trim(),
        'imagem_url': imagemUrl,
        'destinatario': destinatario,
        'status': status,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
 
  /// Exclui um post (só o próprio autor pode excluir).
  Future<bool> excluirPost(int postId) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return false;
    try {
      final result = await _client
          .from('feed_posts')
          .delete()
          .eq('id', postId)
          .eq('autor_id', meuId)
          .select('id');
      return (result as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }
 
  /// Busca colaboradores e setores para o autocomplete de @menção.
  ///
  /// Retorna uma lista de Maps com 'tipo' ('colaborador' | 'setor'),
  /// 'label' (texto exibido) e 'valor' (string gravada no campo destinatario).
  Future<List<Map<String, String>>> buscarSugestoesMencao(String query) async {
    final q = query.toLowerCase();

    // Busca setores distintos
    final setoresRaw = await _client
        .from('colaboradores')
        .select('setor')
        .not('setor', 'is', null)
        .then((r) => r as List);

    final todosSetores = setoresRaw
        .map((e) => e['setor'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    // Query vazia: mostra "Todos" + todos os setores (sem busca de colaborador)
    if (q.isEmpty) {
      return [
        {
          'tipo': 'todos',
          'label': 'Todos',
          'sublabel': 'Todos os colaboradores',
          'valor': 'todos',
        },
        ...todosSetores.take(6).map((s) => {
              'tipo': 'setor',
              'label': '@$s',
              'sublabel': 'Setor',
              'valor': '@setor:$s',
            }),
      ];
    }

    // Com query: filtra
    final setoresFiltrados = todosSetores
        .where((s) => s.toLowerCase().contains(q))
        .take(4)
        .toList();

    final colabs = await _client
        .from('colaboradores')
        .select('id, nome, cargo')
        .ilike('nome', '%$q%')
        .limit(6);

    final sugestoes = <Map<String, String>>[];

    if ('todos'.contains(q)) {
      sugestoes.add({
        'tipo': 'todos',
        'label': 'Todos',
        'sublabel': 'Todos os colaboradores',
        'valor': 'todos',
      });
    }

    for (final s in setoresFiltrados) {
      sugestoes.add({
        'tipo': 'setor',
        'label': '@$s',
        'sublabel': 'Setor',
        'valor': '@setor:$s',
      });
    }

    for (final c in (colabs as List)) {
      sugestoes.add({
        'tipo': 'colaborador',
        'label': '@${c['nome']}',
        'sublabel': c['cargo'] ?? '',
        'valor': '@colaborador:${c['id']}',
      });
    }

    return sugestoes;
  }

  // ─── Indicações pendentes ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> buscarIndicacoesPendentes() async {
    final col = colaboradorAtual;
    if (col == null) return [];

    final matricula = col.matricula;
    final cpf = col.cpf?.replaceAll(RegExp(r'\D'), '') ?? '';

    final query = _client
        .from('candidaturas')
        .select('id, vaga_id, candidato_id, status, status_indicacao, matricula_indicador, candidatos(nome, cpf), vagas(titulo)')
        .eq('status_indicacao', 'pendente');

    final List resultados = [];

    final byMatricula = await query.eq('matricula_indicador', matricula);
    resultados.addAll(byMatricula as List);

    if (cpf.isNotEmpty && cpf != matricula) {
      final byCpf = await _client
          .from('candidaturas')
          .select('id, vaga_id, candidato_id, status, status_indicacao, matricula_indicador, candidatos(nome, cpf), vagas(titulo)')
          .eq('status_indicacao', 'pendente')
          .eq('matricula_indicador', cpf);
      for (final item in byCpf as List) {
        if (!resultados.any((r) => r['id'] == item['id'])) {
          resultados.add(item);
        }
      }
    }

    return resultados.cast<Map<String, dynamic>>();
  }

  Future<void> confirmarIndicacao({
    required int candidaturaId,
    required bool confirmar,
  }) async {
    final col = colaboradorAtual;
    if (col == null) return;

    if (confirmar) {
      await _client.from('candidaturas').update({
        'status_indicacao': 'confirmado',
        'indicado_por_id': col.id,
        'tipo_origem': 'INDICACAO',
      }).eq('id', candidaturaId);
    } else {
      await _client.from('candidaturas').update({
        'status_indicacao': 'rejeitado',
      }).eq('id', candidaturaId);
    }
  }

  Future<List<Map<String, dynamic>>> listarFiliais() async {
    final res = await _client
        .from('hierarquia_nomes')
        .select('id, chave, nome')
        .eq('tipo', 'filial')
        .order('nome');
    return List<Map<String, dynamic>>.from(res as List);
  }

}