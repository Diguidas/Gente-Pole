import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:gentepole/models/comunicado_model.dart';
import 'package:gentepole/models/feed_post_model.dart';
import 'package:gentepole/models/lojinha_model.dart';
import 'package:gentepole/models/fisioterapia_model.dart';
import 'package:gentepole/models/massoterapia_model.dart';
import 'package:gentepole/models/vaga_model.dart';
import 'package:gentepole/screens/nutricionista/nutricionista_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/colaborador_model.dart';
import '../models/aniversariante_model.dart';
import '../core/error_reporter.dart';

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
      // Verifica se é um fornecedor cadastrado em usuarios_app (por CPF)
      final resultFornecedor = await _client
          .from('usuarios_app')
          .select('id')
          .eq('cpf', cpfLimpo)
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
    required String? empresa,
  }) async {
    try {
      await _client.from('usuarios_auth').insert({
        'matricula': matricula,
        'senha_hash': _hash(senha),
        'data_nascimento_verificacao': dataNascimento,
        'empresa': empresa,
      });
      return true;
    } catch (e, st) {
      debugPrint('criarConta ERRO matricula=$matricula: $e');
      ErrorReporter.report(e, st, contexto: 'Criar conta (primeiro acesso)');
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

  /// Reseta a senha de quem já tem conta, mediante confirmação da data de
  /// nascimento (mesma verificação usada no primeiro acesso).
  /// Retorna false se a data não bater ou se a conta não existir.
  Future<bool> resetarSenhaEsquecida({
    required String matricula,
    required String dataNascimento,
    required String novaSenha,
  }) async {
    try {
      final colaborador = await _client
          .from('colaboradores')
          .select('data_nascimento')
          .eq('matricula', matricula)
          .maybeSingle();
      if (colaborador == null) return false;
      if (colaborador['data_nascimento'] != dataNascimento) return false;

      final auth = await _client
          .from('usuarios_auth')
          .update({'senha_hash': _hash(novaSenha)})
          .eq('matricula', matricula)
          .select('id');
      return auth.isNotEmpty;
    } catch (e, st) {
      debugPrint('resetarSenhaEsquecida ERRO matricula=$matricula: $e');
      ErrorReporter.report(e, st, contexto: 'Resetar senha esquecida');
      return false;
    }
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

  /// IDs dos colaboradores que o usuário atual já parabenizou hoje —
  /// usado para não deixar enviar parabéns duplicados no mesmo dia.
  Future<Set<int>> buscarParabensEnviadosHoje() async {
    final remetenteId = colaboradorAtual?.id;
    if (remetenteId == null) return {};
    final hoje = DateTime.now();
    final inicioDia = DateTime(hoje.year, hoje.month, hoje.day).toIso8601String();
    final data = await _client
        .from('parabens')
        .select('destinatario_id')
        .eq('remetente_id', remetenteId)
        .gte('criado_em', inicioDia);
    return (data as List)
        .map((e) => (e as Map)['destinatario_id'] as int)
        .toSet();
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
    } catch (e, st) {
      ErrorReporter.report(e, st, contexto: 'Enviar parabéns');
      return false;
    }
  }

  /// O aniversariante responde a uma mensagem de parabéns específica.
  /// Marca a resposta na própria linha de `parabens` e cria um post
  /// individual no feed, visível só para quem mandou o parabéns original.
  Future<bool> responderParabens({
    required int parabensId,
    required String resposta,
    required int remetenteId,
    required String remetenteNome,
  }) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return false;
    try {
      final respostaLimpa = resposta.trim();
      await _client.from('parabens').update({
        'resposta': respostaLimpa,
        'respondido_em': DateTime.now().toIso8601String(),
      }).eq('id', parabensId);

      final meuPrimeiroNome = colaboradorAtual?.primeiroNome ?? 'Alguém';
      await _client.from('feed_posts').insert({
        'autor_id': meuId,
        'tipo': 'resposta_parabens',
        'conteudo':
            '*$meuPrimeiroNome* respondeu aos parabéns de *$remetenteNome*:\n\n$respostaLimpa',
        'destinatario': '@colaborador:$remetenteId|$remetenteNome',
        'status': 'aprovado',
      });
      return true;
    } catch (e, st) {
      ErrorReporter.report(e, st, contexto: 'Responder parabéns');
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
  Future<List<Map<String, dynamic>>> listarTemplatesGestor({String? setor}) async {
    var q = _client
        .from('ats_templates')
        .select('id, titulo, departamento, tipo_contrato, tipo_vaga, teste_pratico, descricao')
        .eq('ativo', true);
    if (setor != null && setor.isNotEmpty) {
      q = q.eq('departamento', setor);
    }
    final res = await q.order('titulo');
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

  /// Conta, para cada vaga em [vagaIds], quantas candidaturas já estão com
  /// status 'APROVADO' — usado para mostrar "X de Y aprovados" e detectar
  /// quando uma vaga múltipla já preencheu a quantidade solicitada.
  Future<Map<int, int>> contarAprovadosPorVaga(List<int> vagaIds) async {
    if (vagaIds.isEmpty) return {};
    final data = await _client
        .from('candidaturas')
        .select('vaga_id')
        .inFilter('vaga_id', vagaIds)
        .eq('status', 'APROVADO');
    final contagem = <int, int>{};
    for (final row in data as List) {
      final vagaId = (row as Map)['vaga_id'] as int;
      contagem[vagaId] = (contagem[vagaId] ?? 0) + 1;
    }
    return contagem;
  }

  /// Encerra automaticamente a vaga quando o número de candidaturas
  /// aprovadas atinge a `quantidade_vagas` solicitada pelo gestor. Chamado
  /// depois que um candidato é aprovado na proposta. Não faz nada se a vaga
  /// já estiver encerrada ou se ainda não atingiu a quantidade.
  Future<void> encerrarVagaSePreenchida(int vagaId) async {
    final vaga = await _client
        .from('vagas')
        .select('status, quantidade_vagas')
        .eq('id', vagaId)
        .maybeSingle();
    if (vaga == null || vaga['status'] == 'ENCERRADA') return;

    final quantidade = (vaga['quantidade_vagas'] as num?)?.toInt() ?? 1;
    final aprovados = await contarAprovadosPorVaga([vagaId]);
    if ((aprovados[vagaId] ?? 0) >= quantidade) {
      await _client.from('vagas').update({'status': 'ENCERRADA'}).eq(
          'id', vagaId);
    }
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

  /// Grava o parecer/observação do gestor sobre a candidatura, na mesma
  /// tabela `candidatura_observacoes` usada pelo painel web (gentepole_admin),
  /// mantendo as colunas compatíveis: candidatura_id, texto, etapa, criado_por, criado_em.
  Future<void> salvarObservacaoCandidatura({
    required int candidaturaId,
    required String texto,
    required String etapa,
    required int criadoPor,
  }) async {
    await _client.from('candidatura_observacoes').insert({
      'candidatura_id': candidaturaId,
      'texto': texto,
      'etapa': etapa,
      'criado_por': criadoPor,
      'criado_em': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Lista os pareceres/observações já registrados sobre a candidatura,
  /// tanto pelo RH (gentepole_admin) quanto pelo próprio gestor — mesma
  /// tabela `candidatura_observacoes` usada por [salvarObservacaoCandidatura].
  Future<List<Map<String, dynamic>>> listarObservacoesCandidatura(
    int candidaturaId,
  ) async {
    final data = await _client
        .from('candidatura_observacoes')
        .select()
        .eq('candidatura_id', candidaturaId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Gestor aprova candidato na entrevista (move para PROPOSTA).
  /// Exige parecer (mesma regra do painel web: obrigatório antes de avançar de etapa).
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

      if (observacao != null && observacao.isNotEmpty) {
        await salvarObservacaoCandidatura(
          candidaturaId: candidaturaId,
          texto: observacao,
          etapa: 'ENTREV_GESTOR',
          criadoPor: gestorId,
        );
      }
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

  /// Gestor aprova proposta salarial (move para APROVADO).
  /// Exige parecer (mesma regra do painel web: obrigatório antes de avançar de etapa).
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

      if (observacao != null && observacao.isNotEmpty) {
        await salvarObservacaoCandidatura(
          candidaturaId: candidaturaId,
          texto: observacao,
          etapa: 'PROPOSTA',
          criadoPor: gestorId,
        );
      }
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

  /// Resolve se [diaSemana] (1–7) é dia de massoterapia, considerando a regra
  /// mais específica disponível para o colaborador: setor > segmento >
  /// filial > global. Retorna false se nenhuma regra estiver configurada.
  Future<bool> diaMassoterapiaAtivoParaColaborador({
    required int diaSemana,
    String? setor,
    String? segmento,
    String? filial,
  }) async {
    final res = await _client
        .from('massoterapia_dias_config')
        .select('escopo, chave, ativo')
        .eq('dia_semana', diaSemana);
    final linhas = List<Map<String, dynamic>>.from(res as List);

    bool? buscar(String escopo, String? chave) {
      if (chave == null) return null;
      final achado =
          linhas.where((l) => l['escopo'] == escopo && l['chave'] == chave);
      return achado.isEmpty ? null : achado.first['ativo'] as bool;
    }

    final global = linhas.where((l) => l['escopo'] == 'global');

    return buscar('setor', setor) ??
        buscar('segmento', segmento) ??
        buscar('filial', filial) ??
        (global.isEmpty ? false : global.first['ativo'] as bool);
  }

  /// Retorna APENAS o próximo dia disponível para massoterapia, resolvendo a
  /// regra específica do colaborador logado (setor > segmento > filial >
  /// global). Inclui hoje se o dia da semana estiver ativo.
  Future<List<String>> buscarDiasDisponiveisMassoterapia() async {
    final colaborador = colaboradorAtual;
    final agora = _brasilia();
    final hoje = DateTime(agora.year, agora.month, agora.day);

    for (var i = 0; i < 14; i++) {
      final d = hoje.add(Duration(days: i));
      final ativo = await diaMassoterapiaAtivoParaColaborador(
        diaSemana: d.weekday,
        setor: colaborador?.setor,
        segmento: colaborador?.codSegmento,
        filial: colaborador?.codFilial,
      );
      if (ativo) {
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

    // Hint explícito !colaborador_id necessário: desde que
    // substituto_colaborador_id também referencia colaboradores(id), há duas
    // FKs entre as tabelas e o embed ficaria ambíguo sem o hint.
    final data = await _client
        .from('massoterapia_agendamentos')
        .select('*, colaboradores!colaborador_id(nome, matricula, setor)')
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
      // A constraint única (colaborador_id, data) não distingue status: uma
      // linha CANCELADO deixada para trás bloquearia o insert abaixo com um
      // erro de chave duplicada. Limpa qualquer resquício antes de tentar.
      await _client
          .from('massoterapia_agendamentos')
          .delete()
          .eq('colaborador_id', colaborador.id)
          .eq('data', data)
          .eq('status', 'CANCELADO');

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

  /// Soft delete: marca como CANCELADO em vez de apagar, para manter
  /// histórico (relatórios de quem cancelou). O reagendamento no mesmo dia
  /// continua funcionando porque `agendarMassoterapia` limpa esse resquício
  /// antes do insert.
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

  /// Retorna true se o colaborador logado tem o perfil "gestor" — o mesmo
  /// perfil marcado pelo admin no sistema web (colaboradores.eh_gestor,
  /// mantido em sincronia com usuarios_admin.roles).
  Future<bool> verificarSeEhGestor() async {
    return colaboradorAtual?.ehGestor ?? false;
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
      _client.from('lojinha_regras').select('id, dias_semana, materiais'),
    ]);

    final fotos = <String, String>{
      for (final f in (results[1] as List))
        (f['material'] as String): (f['foto_url'] as String),
    };

    // Nova estrutura: uma regra → N materiais. Expande para mapa material → dias
    final diasPorMaterial = <String, List<int>>{};
    for (final r in (results[2] as List)) {
      final dias = (r['dias_semana'] as List?)?.cast<int>();
      final materiais = (r['materiais'] as List?)?.cast<String>() ?? [];
      for (final mat in materiais) {
        if (dias != null) diasPorMaterial[mat] = dias;
      }
    }

    return (results[0] as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final matSemZeros = (m['material'] as String).replaceAll(RegExp(r'^0+'), '');
      m['foto_url'] = fotos[matSemZeros];
      m['dias_semana'] = diasPorMaterial[matSemZeros];
      m['limite_qtd'] = null;
      m['periodo_limite'] = null;
      return LojinhaProdutoModel.fromJson(m);
    }).toList();
  }

  Future<Map<String, dynamic>> buscarConfigLojinha() async {
    final data = await _client
        .from('lojinha_config')
        .select('limite_qtd, periodo_dias')
        .eq('id', 1)
        .maybeSingle();
    if (data == null) return {'limite_qtd': null, 'periodo_dias': null};
    return Map<String, dynamic>.from(data as Map);
  }

  Future<int> buscarComprasRecentesColab(String colaboradorId, int periodoDias) async {
    final desde = DateTime.now().subtract(Duration(days: periodoDias - 1));
    final dataStr =
        '${desde.year}-${desde.month.toString().padLeft(2, '0')}-${desde.day.toString().padLeft(2, '0')}';
    final data = await _client
        .from('lojinha_compras')
        .select('quantidade_total')
        .eq('colaborador_id', colaboradorId)
        .gte('data', dataStr);
    final list = data as List;
    return list.fold<int>(0, (s, r) => s + ((r['quantidade_total'] as int?) ?? 0));
  }

  /// Dados do funcionário no SAP: limites + histórico de pedidos
  /// (mesclado com compras de produtos exclusivos, que não passam pelo SAP)
  Future<LojinhaFuncionarioModel?> buscarDadosFuncionarioLojinha() async {
    final cpf = colaboradorAtual?.cpf?.replaceAll(RegExp(r'\D'), '');
    if (cpf == null || cpf.isEmpty) return null;

    try {
      final res = await _client.functions.invoke(
        'lojinha-funcionario',
        method: HttpMethod.get,
        queryParameters: {'cpf': cpf},
      );
      final map = res.data as Map<String, dynamic>;
      if (map['ok'] != true) return null;
      final dados = LojinhaFuncionarioModel.fromJson(
        map['data'] as Map<String, dynamic>,
      );

      final matricula = colaboradorAtual?.matricula;
      if (matricula == null || matricula.isEmpty) return dados;
      final exclusivos = await buscarComprasExclusivasLojinha(matricula);
      if (exclusivos.isEmpty) return dados;

      return LojinhaFuncionarioModel(
        limiteTotal: dados.limiteTotal,
        limiteDisp: dados.limiteDisp,
        bloqueio: dados.bloqueio,
        centro: dados.centro,
        mensagem: dados.mensagem,
        pedidos: [
          ...dados.pedidos,
          ...exclusivos.map((c) => LojinhaPedidoResumoModel.exclusivo(
                data: c['data'] as String,
                descricao: c['descricao'] as String,
                quantidade: c['quantidade'] as int,
                preco: c['preco'] as double,
                criadoEm: c['criado_em'] as String?,
              )),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  /// Compras de produtos exclusivos (fora do SAP) do colaborador, já
  /// enriquecidas com descrição e preço do catálogo de exclusivos.
  Future<List<Map<String, dynamic>>> buscarComprasExclusivasLojinha(
      String matricula) async {
    final compras = await _client
        .from('lojinha_compras_itens')
        .select('material, quantidade, data, criado_em')
        .eq('colaborador_id', matricula)
        .order('criado_em', ascending: false);
    final comprasList = List<Map<String, dynamic>>.from(compras as List);
    if (comprasList.isEmpty) return [];

    final materiais =
        comprasList.map((c) => c['material'] as String).toSet().toList();
    final exclusivos = await _client
        .from('lojinha_exclusivos')
        .select('material, nome, preco')
        .inFilter('material', materiais);
    final catalogo = {
      for (final e in List<Map<String, dynamic>>.from(exclusivos as List))
        e['material'] as String: e,
    };

    return comprasList.map((c) {
      final info = catalogo[c['material']];
      return {
        'material': c['material'],
        'quantidade': c['quantidade'],
        'data': c['data'],
        'criado_em': c['criado_em'],
        'descricao': info?['nome'] as String? ?? 'Produto exclusivo',
        'preco': (info?['preco'] as num?)?.toDouble() ?? 0.0,
      };
    }).toList();
  }

  static const _nfeBaseUrl =
      'https://jyfovmyvhfyfxczaorxx.supabase.co/rest/v1/view_nfe_documents';
  static const _nfeApiKey = 'sb_publishable_i73HLNj65X34K2IJmI4lJg_stIVnMCb';

  /// Busca a URL do DANFE (nota fiscal) de um pedido a partir do DOCNUM.
  /// Retorna null se não encontrado ou em caso de erro.
  Future<String?> buscarDanfeUrlPorDocnum(String docnum) async {
    if (docnum.isEmpty) return null;
    try {
      final uri = Uri.parse(_nfeBaseUrl).replace(queryParameters: {
        'docnum': 'eq.$docnum',
        'select': 'danfe_url',
        'limit': '1',
      });
      final res = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'apikey': _nfeApiKey,
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body) as List;
      if (list.isEmpty) return null;
      return (list.first as Map<String, dynamic>)['danfe_url'] as String?;
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
    } catch (e, st) {
      ErrorReporter.report(e, st, contexto: 'Buscar estoque da lojinha');
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

  Future<List<LojinhaProdutoModel>> buscarExclusivosLojinha() async {
    final data = await _client
        .from('lojinha_exclusivos')
        .select('id, material, nome, descricao, foto_url, preco, estoque')
        .eq('ativo', true)
        .order('ordem', ascending: true);
    return (data as List)
        .map((j) => LojinhaProdutoModel.fromExclusivo(j as Map<String, dynamic>))
        .toList();
  }

  /// Envia pedido via Edge Function — pode gerar múltiplos pedidos (um por centro).
  /// Itens exclusivos NÃO vão ao SAP: são registrados diretamente no Supabase.
  Future<({bool ok, String retorno, List<LojinhaPedidoCentroResult> pedidos})>
  finalizarPedidoLojinha({required List<CarrinhoItem> itens}) async {
    final colaborador = colaboradorAtual!;
    final hoje = DateTime.now();
    final dataStr =
        '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';
    final datacriacao =
        '${hoje.year}${hoje.month.toString().padLeft(2, '0')}${hoje.day.toString().padLeft(2, '0')}';

    final itensRegulares = itens.where((i) => !i.produto.isExclusivo).toList();
    final itensExclusivos = itens.where((i) => i.produto.isExclusivo).toList();

    bool ok = true;
    String retorno = '';
    List<LojinhaPedidoCentroResult> pedidos = [];

    try {
      // Itens regulares → SAP
      if (itensRegulares.isNotEmpty) {
        final res = await _client.functions.invoke(
          'lojinha-pedido',
          body: {
            'colaborador_id': colaborador.id,
            'cliente_sap': colaborador.clienteSap,
            'datacriacao': datacriacao,
            'itens': itensRegulares.map((i) => i.toSapItem()).toList(),
          },
        );
        final data = res.data as Map<String, dynamic>;
        ok = data['ok'] as bool;
        retorno = data['retorno'] as String;
        final pedidosRaw = data['pedidos'] as List? ?? [];
        pedidos = pedidosRaw
            .map((p) => LojinhaPedidoCentroResult.fromJson(p as Map<String, dynamic>))
            .toList();
      }

      // Itens exclusivos → Supabase (independente do resultado SAP).
      // `comprar_exclusivo` debita o estoque e registra a compra numa única
      // transação atômica no banco — só registra se realmente havia
      // estoque suficiente (ver migrations/2026-07-04g_comprar_exclusivo_atomico.sql).
      if (itensExclusivos.isNotEmpty) {
        final matricula = colaborador.matricula;
        final colabNome = colaborador.nome;
        final semEstoque = <String>[];
        for (final item in itensExclusivos) {
          final sucesso = await _client.rpc('comprar_exclusivo', params: {
            'p_material': item.produto.material,
            'p_quantidade': item.quantidade,
            'p_colaborador_id': matricula,
            'p_colaborador_nome': colabNome,
            'p_data': dataStr,
          }) as bool;
          if (!sucesso) semEstoque.add(item.produto.descricao);
        }
        if (itensRegulares.isEmpty) {
          ok = semEstoque.length < itensExclusivos.length;
          retorno = semEstoque.isEmpty
              ? 'Pedido exclusivo registrado com sucesso!'
              : 'Sem estoque suficiente para: ${semEstoque.join(', ')}.';
        } else if (semEstoque.isNotEmpty) {
          retorno = '$retorno\nSem estoque suficiente para: ${semEstoque.join(', ')}.';
        }
      }

      // Registra total em lojinha_compras (para controle de limite global)
      if (ok) {
        final qtdTotal = itens.fold<int>(0, (s, i) => s + i.quantidade);
        await _client.from('lojinha_compras').insert({
          'colaborador_id': colaborador.matricula,
          'quantidade_total': qtdTotal,
          'data': dataStr,
        });
      }

      return (ok: ok, retorno: retorno, pedidos: pedidos);
    } catch (e, st) {
      ErrorReporter.report(e, st, contexto: 'Finalizar pedido na lojinha');
      return (
        ok: false,
        retorno: 'Não foi possível concluir o pedido. Verifique sua conexão e tente novamente.',
        pedidos: <LojinhaPedidoCentroResult>[],
      );
    }
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
  /// Quando [status] é 'ALTERADO', os dados do colaborador que efetivamente
  /// compareceu (substituto) são gravados para manter o histórico do
  /// agendamento original.
  Future<bool> atualizarPresencaMassoterapia({
    required int id,
    required String status, // 'VEIO' | 'NAO_VEIO' | 'ALTERADO'
    String? assinaturaUrl,
    int? substitutoColaboradorId,
    String? substitutoNome,
    String? substitutoMatricula,
    String? substitutoSetor,
    String? substitutoCargo,
  }) async {
    assert(status == 'VEIO' || status == 'NAO_VEIO' || status == 'ALTERADO');
    try {
      await _client
          .from('massoterapia_agendamentos')
          .update({
            'status': status,
            if (assinaturaUrl != null) 'assinatura_url': assinaturaUrl,
            if (substitutoColaboradorId != null)
              'substituto_colaborador_id': substitutoColaboradorId,
            if (substitutoNome != null) 'substituto_nome': substitutoNome,
            if (substitutoMatricula != null)
              'substituto_matricula': substitutoMatricula,
            if (substitutoSetor != null) 'substituto_setor': substitutoSetor,
            if (substitutoCargo != null) 'substituto_cargo': substitutoCargo,
          })
          .eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Busca um colaborador pela matrícula (usado no fluxo de substituição da
  /// massoterapia: quem assina não é sempre quem estava agendado).
  Future<ColaboradorModel?> buscarColaboradorPorMatricula(
      String matricula) async {
    final data = await _client
        .from('colaboradores')
        .select()
        .eq('matricula', matricula)
        .maybeSingle();
    if (data == null) return null;
    return ColaboradorModel.fromJson(data);
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

  /// Login pelo CPF do fornecedor (massoterapeuta/nutricionista).
  /// Retorna o map do usuário se válido, null caso contrário.
  Future<Map<String, dynamic>?> loginFornecedor({
    required String cpf,
    required String senha,
  }) async {
    final cpfLimpo = cpf.replaceAll(RegExp(r'[^0-9]'), '');
    final senhaHash = _hash(senha);
    final res = await _client
        .from('usuarios_app')
        .select()
        .eq('cpf', cpfLimpo)
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
        codCentro: colaboradorAtual!.codCentro,
        empresa: colaboradorAtual!.empresa,
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

  /// Lista pesquisas disponíveis para o colaborador (via `pesquisa_envios`),
  /// já com o campo `ja_respondeu` para bloquear resposta duplicada.
  ///
  /// Antes esse método só olhava `pesquisas.ativa`, que reflete se a
  /// pesquisa (o "molde") está ativa — não se o ENVIO (a campanha, com sua
  /// própria janela de datas) ainda está aberto. Uma pesquisa podia
  /// continuar `ativa = true` mesmo com todo envio já fora do prazo, e
  /// aparecia disponível pra sempre. Agora replica a mesma lógica de
  /// `pesquisa_envios` + `data_inicio`/`data_fim` que o gentepole_admin usa.
  Future<List<Map<String, dynamic>>> buscarPesquisasDisponiveis() async {
    final colab = colaboradorAtual;
    if (colab == null) return [];

    final hoje = DateTime.now().toIso8601String().substring(0, 10);

    final envios = await _client
        .from('pesquisa_envios')
        .select('id, pesquisa_id, tipo_destinatario, setores_alvo, '
            'agrupamentos_alvo, data_inicio, data_fim, pesquisas(*)')
        .or('data_inicio.is.null,data_inicio.lte.$hoje')
        .or('data_fim.is.null,data_fim.gte.$hoje');

    List<dynamic> parseLista(dynamic raw) {
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

    final meusAgrupamentos = <int>{};
    final membros = await _client
        .from('agrupamento_membros')
        .select('agrupamento_id')
        .eq('colaborador_id', colab.id);
    meusAgrupamentos
        .addAll((membros as List).map((e) => e['agrupamento_id'] as int));

    final enviosColaborador = await _client
        .from('pesquisa_envio_colaboradores')
        .select('envio_id, colaborador_alvo_id')
        .eq('colaborador_id', colab.id);
    final meusEnvios = <int, int?>{
      for (final e in enviosColaborador as List)
        e['envio_id'] as int: e['colaborador_alvo_id'] as int?,
    };

    // Chave por envio (não por pesquisa) — o mesmo colaborador pode estar
    // em vários envios da MESMA pesquisa (ex: um gestor avaliando várias
    // pessoas); agrupar por pesquisa_id faria só a primeira ocorrência
    // aparecer.
    final pesquisasVisiveis = <int, Map<String, dynamic>>{};
    for (final envio in envios as List) {
      final tipo = envio['tipo_destinatario'] as String? ?? 'todos';
      bool visivel;
      switch (tipo) {
        case 'todos':
          visivel = true;
          break;
        case 'setor':
          visivel = parseLista(envio['setores_alvo']).contains(colab.setor);
          break;
        case 'colaboradores':
          visivel = meusEnvios.containsKey(envio['id'] as int);
          break;
        case 'agrupamentos':
          visivel = parseLista(envio['agrupamentos_alvo']).any((g) =>
              meusAgrupamentos
                  .contains(g is int ? g : int.tryParse(g.toString()) ?? -1));
          break;
        default:
          visivel = true;
      }
      if (!visivel) continue;
      final pesquisa = envio['pesquisas'] as Map?;
      if (pesquisa == null) continue;
      final envioId = envio['id'] as int;
      pesquisasVisiveis[envioId] = {
        ...Map<String, dynamic>.from(pesquisa),
        '_envio_id': envioId,
        'colaborador_alvo_id': meusEnvios[envioId] ?? colab.id,
      };
    }

    if (pesquisasVisiveis.isEmpty) return [];

    final pesquisaIds =
        pesquisasVisiveis.values.map((p) => p['id'] as int).toSet().toList();
    // Usa `pesquisa_participacoes` (não `pesquisa_respostas`) porque em
    // pesquisas anônimas o colaborador_id da resposta é gravado como null de
    // propósito — só a tabela de participação sabe quem já respondeu. Inclui
    // colaborador_alvo_id pra não confundir "já respondi sobre a Maria" com
    // "já respondi sobre o João" quando é a mesma pesquisa.
    final respondidas = await _client
        .from('pesquisa_participacoes')
        .select('pesquisa_id, colaborador_alvo_id')
        .eq('colaborador_id', colab.id)
        .inFilter('pesquisa_id', pesquisaIds);
    final respondidasSet = (respondidas as List)
        .map((e) => '${e['pesquisa_id']}_${e['colaborador_alvo_id']}')
        .toSet();

    return pesquisasVisiveis.values.map((p) {
      return {
        ...p,
        'ja_respondeu': respondidasSet
            .contains('${p['id']}_${p['colaborador_alvo_id']}'),
      };
    }).toList()
      ..sort((a, b) => (b['criado_em'] as String? ?? '')
          .compareTo(a['criado_em'] as String? ?? ''));
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

  /// Resolve qual envio (`pesquisa_envios`) deu acesso a esta pesquisa para
  /// o colaborador logado — usado só na hora de responder, pra gravar
  /// `envio_id` na resposta (sem isso, o filtro por envio na tela de
  /// detalhe do admin nunca encontra nada).
  Future<int?> _resolverEnvioIdPesquisa(int pesquisaId) async {
    final colab = colaboradorAtual;
    if (colab == null) return null;

    final hoje = DateTime.now().toIso8601String().substring(0, 10);
    final envios = await _client
        .from('pesquisa_envios')
        .select('id, tipo_destinatario, setores_alvo, agrupamentos_alvo')
        .eq('pesquisa_id', pesquisaId)
        .or('data_inicio.is.null,data_inicio.lte.$hoje')
        .or('data_fim.is.null,data_fim.gte.$hoje');
    if ((envios as List).isEmpty) return null;

    List<dynamic> parseLista(dynamic raw) {
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

    Set<int>? meusAgrupamentos;
    Set<int>? meusEnviosColab;

    for (final envio in envios) {
      final tipo = envio['tipo_destinatario'] as String? ?? 'todos';
      bool visivel;
      switch (tipo) {
        case 'todos':
          visivel = true;
          break;
        case 'setor':
          visivel = parseLista(envio['setores_alvo']).contains(colab.setor);
          break;
        case 'colaboradores':
          meusEnviosColab ??= await _client
              .from('pesquisa_envio_colaboradores')
              .select('envio_id')
              .eq('colaborador_id', colab.id)
              .then((r) => (r as List).map((e) => e['envio_id'] as int).toSet());
          visivel = meusEnviosColab!.contains(envio['id'] as int);
          break;
        case 'agrupamentos':
          meusAgrupamentos ??= await _client
              .from('agrupamento_membros')
              .select('agrupamento_id')
              .eq('colaborador_id', colab.id)
              .then((r) => (r as List).map((e) => e['agrupamento_id'] as int).toSet());
          visivel = parseLista(envio['agrupamentos_alvo']).any((g) =>
              meusAgrupamentos!.contains(g is int ? g : int.tryParse(g.toString()) ?? -1));
          break;
        default:
          visivel = true;
      }
      if (visivel) return envio['id'] as int;
    }
    return null;
  }

  /// Resolve o "alvo" de uma resposta — normalmente é o próprio
  /// colaborador; só difere quando o envio foi endereçado a alguém
  /// avaliando outra pessoa (ex: gestor respondendo sobre um colaborador no
  /// Período de Experiência). Sem vínculo em `pesquisa_envio_colaboradores`,
  /// o alvo é sempre o próprio respondente.
  Future<int> _resolverAlvoIdPesquisa(int? envioId, int colaboradorId) async {
    if (envioId != null) {
      final vinculo = await _client
          .from('pesquisa_envio_colaboradores')
          .select('colaborador_alvo_id')
          .eq('envio_id', envioId)
          .eq('colaborador_id', colaboradorId)
          .maybeSingle();
      if (vinculo != null && vinculo['colaborador_alvo_id'] != null) {
        return vinculo['colaborador_alvo_id'] as int;
      }
    }
    return colaboradorId;
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
      final envioId = await _resolverEnvioIdPesquisa(pesquisaId);
      final alvoId = meuId == null
          ? null
          : await _resolverAlvoIdPesquisa(envioId, meuId);
      // 1. Insere cabeçalho
      final cabecalho = await _client
          .from('pesquisa_respostas')
          .insert({
            'pesquisa_id': pesquisaId,
            'colaborador_id': anonima ? null : meuId,
            'colaborador_alvo_id': alvoId,
            'envio_id': envioId,
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
        if (e.value is num) mapa['valor_numero'] = e.value;
        if (e.value is bool) mapa['valor_booleano'] = e.value;
        // checkbox de múltipla escolha real (List<String>) — grava como
        // texto separado por vírgula, igual ao app admin.
        if (e.value is Iterable) {
          mapa['valor_texto'] = (e.value as Iterable).join(', ');
        }
        // escala_matriz (Map<String,String> linha → coluna escolhida) —
        // não tem coluna própria, então grava como JSON no valor_texto,
        // igual ao app admin (ver responderPesquisaColab de lá).
        if (e.value is Map) mapa['valor_texto'] = jsonEncode(e.value);
        return mapa;
      }).toList();

      await _client.from('pesquisa_resposta_itens').insert(itens);

      // Marca participação separadamente do conteúdo da resposta (que pode
      // ser anônimo) — é isso que faz a pesquisa virar "já respondida" e
      // evita resposta duplicada, sem expor quem respondeu o quê.
      if (meuId != null) {
        await _client.from('pesquisa_participacoes').upsert({
          'pesquisa_id': pesquisaId,
          'colaborador_id': meuId,
          'colaborador_alvo_id': alvoId,
          'respondido_em': DateTime.now().toIso8601String(),
        }, onConflict: 'pesquisa_id,colaborador_id,colaborador_alvo_id');
      }

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

// ─── Cardápio do Refeitório (imagem única) ─────────────────────────────────

  /// Busca a imagem única do cardápio (ex: foto do quadro semanal). Retorna
  /// null se ainda não houver imagem cadastrada.
  Future<String?> buscarCardapioImagem() async {
    final res = await _client
        .from('cardapio_config')
        .select('imagem_url')
        .eq('id', 1)
        .maybeSingle();
    return res?['imagem_url'] as String?;
  }

// ─── Reserva de Salas ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listarSalasReserva({bool apenasAtivas = false}) async {
    var query = _client.from('salas_reserva').select();
    if (apenasAtivas) query = query.eq('ativo', true);
    final res = await query.order('ordem', ascending: true).order('nome', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> listarMinhasReservasSalas(String colaboradorId) async {
    final res = await _client
        .from('reservas_salas')
        .select()
        .eq('colaborador_id', colaboradorId)
        .order('data', ascending: false)
        .order('hora_inicio', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Retorna null em sucesso, ou uma mensagem de erro amigável em caso de
  /// falha (ex: conflito de horário).
  Future<String?> reservarSala({
    required int salaId,
    required String data,
    required String horaInicio,
    required String horaFim,
    required String colaboradorId,
    required String colaboradorNome,
    required String titulo,
    String? subtipo,
    required String responsavelNome,
    required String responsavelContato,
    String? observacao,
  }) async {
    try {
      await _client.rpc('reservar_sala', params: {
        'p_sala_id': salaId,
        'p_data': data,
        'p_hora_inicio': horaInicio,
        'p_hora_fim': horaFim,
        'p_colaborador_id': colaboradorId,
        'p_colaborador_nome': colaboradorNome,
        'p_titulo': titulo,
        'p_subtipo': subtipo,
        'p_responsavel_nome': responsavelNome,
        'p_responsavel_contato': responsavelContato,
        'p_observacao': observacao,
      });
      return null;
    } catch (e, st) {
      final msg = e.toString();
      if (msg.contains('CONFLITO_HORARIO')) {
        return 'Essa sala já está reservada nesse horário. Escolha outro horário.';
      }
      if (msg.contains('HORARIO_INVALIDO')) {
        return 'O horário final precisa ser depois do horário inicial.';
      }
      if (msg.contains('SALA_INVALIDA')) {
        return 'Essa sala não está mais disponível.';
      }
      ErrorReporter.report(e, st, contexto: 'Reservar sala');
      return 'Não foi possível reservar. Tente novamente.';
    }
  }

  Future<bool> cancelarReservaSala(int id) async {
    try {
      await _client.from('reservas_salas').delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

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

  /// Apaga a linha em vez de só marcar como CANCELADO — se só marcássemos o
  /// status, a linha continuaria ocupando o dia na constraint única
  /// (colaborador_id, data), impedindo um novo agendamento no mesmo dia em
  /// outro horário.
  Future<bool> cancelarNutricionista(int agendamentoId) async {
    try {
      await _client
          .from('nutricionista_agendamentos')
          .delete()
          .eq('id', agendamentoId);
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

// ─── Fisioterapia ────────────────────────────────────────────────────────────
// Tela do prestador (fisioterapeuta) e do colaborador (somente leitura).
// Mesmas tabelas/buckets já criados e usados pelo app Admin.

  // -- Prestador -------------------------------------------------------------

  Future<List<FisioterapiaCaso>> listarMeusCasosFisioterapia(
      int fisioterapeutaId) async {
    final res = await _client
        .from('fisioterapia_casos')
        .select('*, colaboradores(nome, matricula, setor)')
        .eq('fisioterapeuta_id', fisioterapeutaId)
        .eq('status', 'ativo')
        .order('criado_em', ascending: false);
    return (res as List)
        .map((e) => FisioterapiaCaso.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<FisioterapiaSessao>> listarSessoesPorCasos(
      List<int> casoIds) async {
    if (casoIds.isEmpty) return [];
    final res = await _client
        .from('fisioterapia_sessoes')
        .select()
        .inFilter('caso_id', casoIds)
        .order('data', ascending: false)
        .order('horario');
    return (res as List)
        .map((e) => FisioterapiaSessao.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<bool> atualizarSessaoFisioterapia(
      int id, Map<String, dynamic> dados) async {
    try {
      await _client.from('fisioterapia_sessoes').update(dados).eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<FisioterapiaExercicio>> listarExerciciosFisioterapia(
      int casoId) async {
    final res = await _client
        .from('fisioterapia_exercicios')
        .select()
        .eq('caso_id', casoId)
        .order('criado_em', ascending: false);
    return (res as List)
        .map((e) => FisioterapiaExercicio.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<bool> criarExercicioFisioterapia({
    required int casoId,
    required String descricao,
    String? frequencia,
  }) async {
    try {
      await _client.from('fisioterapia_exercicios').insert({
        'caso_id': casoId,
        'descricao': descricao,
        'frequencia': frequencia,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> excluirExercicioFisioterapia(int id) async {
    try {
      await _client.from('fisioterapia_exercicios').delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  // -- Colaborador (somente leitura) ------------------------------------------

  /// Caso mais recente do colaborador logado, em qualquer status.
  Future<FisioterapiaCaso?> buscarMeuCasoFisioterapia() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return null;
    final res = await _client
        .from('fisioterapia_casos')
        .select()
        .eq('colaborador_id', meuId)
        .order('criado_em', ascending: false)
        .limit(1)
        .maybeSingle();
    if (res == null) return null;
    return FisioterapiaCaso.fromJson(res);
  }

  Future<List<FisioterapiaSessao>> listarSessoesDoCasoFisioterapia(
      int casoId) async {
    final res = await _client
        .from('fisioterapia_sessoes')
        .select()
        .eq('caso_id', casoId)
        .order('data', ascending: false)
        .order('horario');
    return (res as List)
        .map((e) => FisioterapiaSessao.fromJson(e as Map<String, dynamic>))
        .toList();
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
        .select('*, autor:colaboradores!autor_id(nome, foto_url, cargo)')
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
        return FeedPostModel(
          id: -(c['id'] as int),
          autorId: null,
          tipo: 'comunicado',
          titulo: titulo != null && titulo.isNotEmpty ? titulo : null,
          conteudo: descricao != null && descricao.isNotEmpty ? descricao : null,
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
    String tipo = 'post',
    bool temTextoLivre = false,
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

      // Posts para 'todos' precisam de aprovação do RH; demais vão direto.
      // Posts de humor sem motivo são só o nível selecionado (sem texto
      // livre do usuário) e saem aprovados direto; com motivo preenchido,
      // vira texto livre e precisa da mesma aprovação de qualquer post.
      final precisaAprovacao = destinatario == 'todos' &&
          (tipo != 'humor' || temTextoLivre);
      final status = precisaAprovacao ? 'pendente' : 'aprovado';
      await _client.from('feed_posts').insert({
        'autor_id': meuId,
        'tipo': tipo,
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
 
  /// Lista os setores distintos cadastrados, para o seletor de "Para: Por setor".
  Future<List<String>> listarSetoresDistintos() async {
    final res = await _client
        .from('colaboradores')
        .select('setor')
        .not('setor', 'is', null);
    return (res as List)
        .map((e) => e['setor'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
  }

  /// Busca colaboradores pelo nome, para o seletor de "Para: Individual".
  Future<List<Map<String, dynamic>>> buscarColaboradoresParaDestinatario(
      String query) async {
    if (query.isEmpty) return [];
    final res = await _client
        .from('colaboradores')
        .select('id, nome, setor')
        .ilike('nome', '%$query%')
        .limit(8);
    return List<Map<String, dynamic>>.from(res as List);
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

  // ─── Performance: Feedback (Avaliação) ──────────────────────────────────
  // Portado do app admin (gentepole_admin/lib/core/services/api_service.dart)
  // Tabelas: avaliacao_feedbacks, feedback_solicitacoes, elogios,
  // feedback_itens_empresa. Mesmo schema Supabase do admin.

  /// Marca todos os feedbacks recebidos pelo colaborador como visualizados —
  /// chamado ao abrir a tela onde ele os vê.
  Future<void> marcarFeedbacksRecebidosComoVistos(int colaboradorId) async {
    await _client
        .from('avaliacao_feedbacks')
        .update({'visualizado_em': DateTime.now().toIso8601String()})
        .eq('colaborador_id', colaboradorId)
        .filter('visualizado_em', 'is', null);
  }

  /// Feedbacks de avaliação recebidos pelo colaborador (distinto da tabela
  /// `feedbacks` genérica já usada em [enviarFeedback]/[buscarFeedbacksRecebidos]).
  Future<List<Map<String, dynamic>>> listarFeedbacksAvaliacao(
      int colaboradorId) async {
    final data = await _client
        .from('avaliacao_feedbacks')
        .select('*, autor:autor_id(nome)')
        .eq('colaborador_id', colaboradorId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Solicitações de feedback que o colaborador enviou pra outras pessoas.
  Future<List<Map<String, dynamic>>> listarSolicitacoesFeedbackEnviadas(
      int colaboradorId) async {
    final data = await _client
        .from('feedback_solicitacoes')
        .select()
        .eq('solicitante_id', colaboradorId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<void> criarSolicitacaoFeedback({
    required int solicitanteId,
    required int destinatarioId,
    String? mensagem,
  }) async {
    await _client.from('feedback_solicitacoes').insert({
      'solicitante_id': solicitanteId,
      'destinatario_id': destinatarioId,
      'mensagem': mensagem,
    });
  }

  // ─── Elogios entre colaboradores ────────────────────────────────────────
  // Distinto do feedback/avaliação: elogio é livre, sem notas nem itens da
  // empresa — só um texto de reconhecimento entre colegas.

  Future<void> criarElogio({
    required int autorId,
    required int colaboradorId,
    required String texto,
    required bool anonimo,
  }) async {
    await _client.from('elogios').insert({
      'autor_id': autorId,
      'colaborador_id': colaboradorId,
      'texto': texto.trim(),
      'anonimo': anonimo,
    });
  }

  Future<List<Map<String, dynamic>>> listarElogiosRecebidos(
      int colaboradorId) async {
    final data = await _client
        .from('elogios')
        .select()
        .eq('colaborador_id', colaboradorId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Gestor do mesmo setor — usado pra "Pedir feedback ao meu gestor".
  ///
  /// APROXIMAÇÃO: o app admin resolve isso via `usuarios_admin.roles`
  /// contendo 'gestor' (tabela que não existe neste projeto). Aqui usamos o
  /// mesmo sinal já usado por [verificarSeEhGestor] — `colaboradores.eh_gestor`
  /// — que é o equivalente mais simples disponível neste schema.
  Future<ColaboradorModel?> buscarGestorDoSetor(String setor) async {
    final data = await _client
        .from('colaboradores')
        .select()
        .eq('setor', setor)
        .eq('eh_gestor', true)
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    return ColaboradorModel.fromJson(data);
  }

  /// Os itens fixos (por slot) de avaliação por estrelas, configurados pelo RH.
  Future<List<Map<String, dynamic>>> listarItensEmpresaFeedback() async {
    final data = await _client
        .from('feedback_itens_empresa')
        .select()
        .order('slot');
    return List<Map<String, dynamic>>.from(data as List);
  }

  // ─── Ouvidoria (com assunto/tipo/anexo) ─────────────────────────────────
  // Distinto de [salvarOuvidoria] (que já existe acima, no formato antigo
  // ocorrido/telefone/sugestao). Este método mirra o formato usado pelo app
  // admin, com assunto, tipo e anexo opcional no Storage.

  /// Envia uma manifestação de ouvidoria em nome do colaborador logado.
  /// Quando [anonimo] é true, colaborador_id/matrícula ainda são gravados
  /// (pra evitar abuso) — quem exibe "Anônimo" em vez do nome é a tela de
  /// leitura (admin).
  Future<bool> enviarOuvidoriaColab({
    required String assunto,
    required String tipo, // 'reclamacao' | 'sugestao' | 'denuncia'
    required String texto,
    required bool anonimo,
    Uint8List? anexoBytes,
    String? anexoNomeArquivo,
  }) async {
    final colaborador = colaboradorAtual;
    if (colaborador == null) return false;
    try {
      String? anexoUrl;
      if (anexoBytes != null && anexoNomeArquivo != null) {
        final path =
            '${DateTime.now().millisecondsSinceEpoch}_$anexoNomeArquivo';
        await _client.storage
            .from('ouvidoria-anexos')
            .uploadBinary(path, anexoBytes);
        anexoUrl = _client.storage.from('ouvidoria-anexos').getPublicUrl(path);
      }
      await _client.from('ouvidoria').insert({
        'colaborador_id': colaborador.id,
        'matricula': colaborador.matricula,
        'assunto': assunto.trim(),
        'tipo': tipo,
        'ocorrido': texto.trim(),
        'anonimo': anonimo,
        if (anexoUrl != null) 'anexo_url': anexoUrl,
        if (anexoUrl != null) 'anexo_nome': anexoNomeArquivo,
        'criado_em': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e, st) {
      ErrorReporter.report(e, st, contexto: 'Enviar ouvidoria');
      return false;
    }
  }

  // ─── Pesquisas — recusa ─────────────────────────────────────────────────

  /// Registra que o colaborador recusou responder a pesquisa (com motivo
  /// opcional), sem preencher as respostas. Mantém a mesma marcação de
  /// participação usada por [responderPesquisa], pra pesquisa virar
  /// "já respondida" e não ficar pendente pra sempre.
  Future<bool> recusarPesquisaColab({
    required int pesquisaId,
    required int colaboradorId,
    String? motivo,
  }) async {
    try {
      final envioId = await _resolverEnvioIdPesquisa(pesquisaId);
      final alvoId = await _resolverAlvoIdPesquisa(envioId, colaboradorId);
      await _client.from('pesquisa_respostas').insert({
        'pesquisa_id': pesquisaId,
        'colaborador_id': colaboradorId,
        'colaborador_alvo_id': alvoId,
        'envio_id': envioId,
        'recusou': true,
        if (motivo != null && motivo.trim().isNotEmpty)
          'motivo_recusa': motivo.trim(),
      });

      await _client.from('pesquisa_participacoes').upsert({
        'pesquisa_id': pesquisaId,
        'colaborador_id': colaboradorId,
        'colaborador_alvo_id': alvoId,
        'respondido_em': DateTime.now().toIso8601String(),
      }, onConflict: 'pesquisa_id,colaborador_id,colaborador_alvo_id');

      return true;
    } catch (e, st) {
      ErrorReporter.report(e, st, contexto: 'Recusar pesquisa');
      return false;
    }
  }

  // ─── Performance: Ciclos de avaliação + PDI + 9box ──────────────────────
  // Portado do app admin (gentepole_admin/lib/core/services/api_service.dart).
  // Mesmo schema Supabase do admin. Tabelas: avaliacao_ciclos, avaliacoes,
  // avaliacao_perguntas, avaliacao_respostas, avaliacao_equipe_avaliadores,
  // pdi_planos, pdi_acoes, pdi_termos_compromisso.

  /// Ciclo de avaliação aberto que vale pro setor informado — o ciclo geral
  /// (setor nulo, aberto pelo RH) e/ou o ciclo que o gestor abriu para o
  /// setor. Prioriza o ciclo específico do setor quando os dois existem.
  Future<Map<String, dynamic>?> buscarCicloAbertoParaSetor(String setor) async {
    final data = await _client
        .from('avaliacao_ciclos')
        .select()
        .eq('status', 'aberto')
        .or('setor.eq.$setor,setor.is.null')
        .order('setor', ascending: false, nullsFirst: false)
        .order('criado_em', ascending: false);
    final lista = List<Map<String, dynamic>>.from(data as List);
    if (lista.isEmpty) return null;
    return lista.firstWhere((c) => c['setor'] == setor,
        orElse: () => lista.first);
  }

  /// Busca a avaliação do colaborador nesse ciclo (criando se ainda não
  /// existir) — usado tanto pela autoavaliação quanto pela avaliação do
  /// gestor.
  Future<Map<String, dynamic>?> buscarOuCriarAvaliacao({
    required int cicloId,
    required int colaboradorId,
  }) async {
    await _client.from('avaliacoes').upsert(
      {'ciclo_id': cicloId, 'colaborador_id': colaboradorId},
      onConflict: 'ciclo_id,colaborador_id',
      ignoreDuplicates: true,
    );
    return await _client
        .from('avaliacoes')
        .select(
            '*, colaboradores!avaliacoes_colaborador_id_fkey(nome, cargo, setor, foto_url)')
        .eq('ciclo_id', cicloId)
        .eq('colaborador_id', colaboradorId)
        .maybeSingle();
  }

  /// Perguntas ativas cadastradas para a função (cargo) informada.
  Future<List<Map<String, dynamic>>> listarPerguntasFuncao(
      String funcao) async {
    final data = await _client
        .from('avaliacao_perguntas')
        .select()
        .eq('funcao', funcao)
        .eq('ativo', true)
        .order('ordem');
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> listarRespostasAvaliacao(
      int avaliacaoId) async {
    final data = await _client
        .from('avaliacao_respostas')
        .select()
        .eq('avaliacao_id', avaliacaoId);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Salva as respostas (nota 1-3 + comentário) de uma origem
  /// ('colaborador', 'gestor' ou 'equipe') para uma avaliação. Recalcula a
  /// média por dimensão (desempenho/potencial): pra 'colaborador'/'gestor'
  /// grava direto nas colunas do 9box; pra 'equipe' primeiro salva a
  /// resposta desse avaliador e depois recalcula a média de todos os
  /// avaliadores da equipe que já responderam.
  Future<void> salvarRespostasAvaliacao({
    required int avaliacaoId,
    required String origem, // 'colaborador' | 'gestor' | 'equipe'
    required List<Map<String, dynamic>>
        respostas, // {perguntaId, dimensao, nota, comentario}
    required int avaliadorId,
    int? gestorId,
  }) async {
    if (respostas.isNotEmpty) {
      final linhas = respostas
          .map((r) => {
                'avaliacao_id': avaliacaoId,
                'pergunta_id': r['perguntaId'],
                'origem': origem,
                'avaliador_id': avaliadorId,
                'nota': r['nota'],
                'comentario': r['comentario'],
              })
          .toList();
      await _client.from('avaliacao_respostas').upsert(linhas,
          onConflict: 'avaliacao_id,pergunta_id,origem,avaliador_id');
    }

    int media(Iterable<int> notas) {
      if (notas.isEmpty) return 2;
      return (notas.reduce((a, b) => a + b) / notas.length).round().clamp(1, 3);
    }

    if (origem == 'colaborador') {
      final desempenho = media(respostas
          .where((r) => r['dimensao'] == 'desempenho')
          .map((r) => r['nota'] as int));
      final potencial = media(respostas
          .where((r) => r['dimensao'] == 'potencial')
          .map((r) => r['nota'] as int));
      await _client.from('avaliacoes').update({
        'autoavaliacao_desempenho': desempenho,
        'autoavaliacao_potencial': potencial,
        'autoavaliacao_em': DateTime.now().toIso8601String(),
        'status': 'pendente_gestor',
      }).eq('id', avaliacaoId);
    } else if (origem == 'gestor') {
      final desempenho = media(respostas
          .where((r) => r['dimensao'] == 'desempenho')
          .map((r) => r['nota'] as int));
      final potencial = media(respostas
          .where((r) => r['dimensao'] == 'potencial')
          .map((r) => r['nota'] as int));
      await _client.from('avaliacoes').update({
        'gestor_id': gestorId ?? avaliadorId,
        'gestor_desempenho': desempenho,
        'gestor_potencial': potencial,
        'gestor_em': DateTime.now().toIso8601String(),
        'status': 'concluida',
      }).eq('id', avaliacaoId);
    } else {
      // 'equipe' — recalcula a média com as respostas de TODOS os colegas
      // que já avaliaram essa pessoa nesse ciclo, não só a desse avaliador.
      final comPergunta = await _client
          .from('avaliacao_respostas')
          .select(
              '*, avaliacao_perguntas!avaliacao_respostas_pergunta_id_fkey(dimensao)')
          .eq('avaliacao_id', avaliacaoId);
      final equipeComPergunta = List<Map<String, dynamic>>.from(
              comPergunta as List)
          .where((r) => r['origem'] == 'equipe');
      final desempenhoEquipe = media(equipeComPergunta
          .where((r) => (r['avaliacao_perguntas']?['dimensao']) == 'desempenho')
          .map((r) => r['nota'] as int));
      final potencialEquipe = media(equipeComPergunta
          .where((r) => (r['avaliacao_perguntas']?['dimensao']) == 'potencial')
          .map((r) => r['nota'] as int));
      await _client.from('avaliacoes').update({
        'equipe_desempenho': desempenhoEquipe,
        'equipe_potencial': potencialEquipe,
        'equipe_em': DateTime.now().toIso8601String(),
      }).eq('id', avaliacaoId);
      await _client
          .from('avaliacao_equipe_avaliadores')
          .update({'respondido': true})
          .eq('avaliacao_id', avaliacaoId)
          .eq('avaliador_id', avaliadorId);
    }
  }

  /// Avaliações de colegas pendentes pra um avaliador da equipe responder —
  /// usado na tela "Avaliar Colegas" (ciclos 360, convite automático feito
  /// pelo app admin em [gerarAvaliadoresEquipeAutomatico] quando o gestor
  /// abre a avaliação da equipe).
  Future<List<Map<String, dynamic>>> listarAvaliacoesEquipeParaAvaliar(
      int avaliadorId) async {
    final data = await _client
        .from('avaliacao_equipe_avaliadores')
        .select(
            '*, avaliacoes(*, colaboradores!avaliacoes_colaborador_id_fkey(nome, cargo, setor, foto_url))')
        .eq('avaliador_id', avaliadorId)
        .eq('respondido', false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Avaliações da equipe (mesmo setor) de um gestor, num ciclo — cria as
  /// que ainda não existem, para a lista já vir completa. Reusa
  /// [buscarMinhaEquipe] pra obter os colaboradores do setor do gestor.
  Future<List<Map<String, dynamic>>> listarAvaliacoesEquipeGestor({
    required int cicloId,
  }) async {
    final equipe = await buscarMinhaEquipe();
    final resultado = <Map<String, dynamic>>[];
    for (final colab in equipe) {
      final avaliacao = await buscarOuCriarAvaliacao(
        cicloId: cicloId,
        colaboradorId: colab.id,
      );
      if (avaliacao != null) resultado.add(avaliacao);
    }
    return resultado;
  }

  // ─── Performance: PDI (Plano de Desenvolvimento Individual) ─────────────

  Future<List<Map<String, dynamic>>> listarPdiPlanos(
      int colaboradorId) async {
    final data = await _client
        .from('pdi_planos')
        .select('*, pdi_acoes(*), pdi_termos_compromisso(*)')
        .eq('colaborador_id', colaboradorId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<int> criarPdiPlano({
    required int colaboradorId,
    required String objetivo,
    required String tipo, // 'tecnico' | 'comportamental'
    int? cicloId,
    int? criadoPor,
  }) async {
    final res = await _client
        .from('pdi_planos')
        .insert({
          'colaborador_id': colaboradorId,
          'objetivo': objetivo,
          'tipo': tipo,
          'ciclo_id': cicloId,
          'criado_por': criadoPor,
        })
        .select('id')
        .single();
    return res['id'] as int;
  }

  Future<void> atualizarStatusPdiPlano(int planoId, String status) async {
    await _client
        .from('pdi_planos')
        .update({'status': status}).eq('id', planoId);
  }

  Future<void> adicionarAcaoPdi({
    required int planoId,
    required String descricao,
    DateTime? prazo,
    String? link,
    String? modalidade, // 'blearning' | 'benchmarking' | 'elearning'
    int ordem = 0,
  }) async {
    await _client.from('pdi_acoes').insert({
      'plano_id': planoId,
      'descricao': descricao,
      'prazo': prazo?.toIso8601String().substring(0, 10),
      'link': link,
      'modalidade': modalidade,
      'ordem': ordem,
    });
  }

  Future<void> atualizarStatusAcaoPdi(int acaoId, String status) async {
    await _client.from('pdi_acoes').update({'status': status}).eq('id', acaoId);
  }

  Future<void> excluirAcaoPdi(int acaoId) async {
    await _client.from('pdi_acoes').delete().eq('id', acaoId);
  }

  /// Upload do arquivo que o colaborador anexa como evidência de uma ação
  /// do PDI.
  Future<String> uploadAnexoAcaoPdi({
    required int acaoId,
    required Uint8List bytes,
    required String nomeArquivo,
  }) async {
    final path =
        'acao_$acaoId/${DateTime.now().millisecondsSinceEpoch}_$nomeArquivo';
    await _client.storage.from('pdi-anexos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final url = _client.storage.from('pdi-anexos').getPublicUrl(path);
    await _client.from('pdi_acoes').update({
      'anexo_url': url,
      'anexo_nome': nomeArquivo,
    }).eq('id', acaoId);
    return url;
  }

  /// Resumo do ciclo ativo do setor do colaborador logado: se há ciclo
  /// aberto, se ele já enviou a autoavaliação, e quantos colegas ele tem
  /// pendentes pra avaliar ("Avaliar Colegas"). Usado pra badges/telas de
  /// estado vazio sem precisar duplicar as consultas em cada tela.
  Future<Map<String, dynamic>> buscarResumoPerformance() async {
    final col = colaboradorAtual;
    if (col == null || col.setor == null || col.setor!.isEmpty) {
      return {
        'ciclo': null,
        'autoavaliacaoPendente': false,
        'colegasPendentes': 0,
      };
    }
    final ciclo = await buscarCicloAbertoParaSetor(col.setor!);
    if (ciclo == null) {
      return {
        'ciclo': null,
        'autoavaliacaoPendente': false,
        'colegasPendentes': 0,
      };
    }
    final avaliacao = await buscarOuCriarAvaliacao(
      cicloId: ciclo['id'] as int,
      colaboradorId: col.id,
    );
    final colegasPendentes = await listarAvaliacoesEquipeParaAvaliar(col.id);
    return {
      'ciclo': ciclo,
      'autoavaliacaoPendente': (ciclo['tipo_avaliacao'] != 'gestor') &&
          (avaliacao?['autoavaliacao_em'] == null),
      'colegasPendentes': colegasPendentes.length,
    };
  }

  // ─── Feedback do Gestor (avaliação estruturada por estrelas) ───────────
  // Portado do app admin (gentepole_admin/lib/core/services/api_service.dart)
  // Tabelas: avaliacao_feedbacks, feedback_modelos, feedback_solicitacoes.
  // Mesmo schema Supabase do admin; ids aqui são int (ColaboradorModel.id).

  /// Cria um feedback estruturado (com notas por estrela) que o gestor dá a
  /// um colaborador da equipe. Retorna o id do feedback criado, usado para
  /// vincular a uma solicitação atendida.
  Future<int> criarFeedbackAvaliacao({
    required int colaboradorId,
    required int autorId,
    required String texto,
    bool anonimo = false,
    bool? presencial,
    String? anotacoesInternas,
    int? modeloId,
    int? item1Nota,
    int? item2Nota,
  }) async {
    final res = await _client
        .from('avaliacao_feedbacks')
        .insert({
          'colaborador_id': colaboradorId,
          'autor_id': autorId,
          'texto': texto,
          'anonimo': anonimo,
          'presencial': presencial,
          'anotacoes_internas': anotacoesInternas,
          'modelo_id': modeloId,
          'item1_nota': item1Nota,
          'item2_nota': item2Nota,
        })
        .select('id')
        .single();
    return res['id'] as int;
  }

  /// Modelos de texto pré-prontos pra facilitar a escrita do feedback.
  Future<List<Map<String, dynamic>>> listarModelosFeedback(
      {bool apenasAtivos = false}) async {
    var query = _client.from('feedback_modelos').select();
    if (apenasAtivos) query = query.eq('ativo', true);
    final data = await query.order('ordem');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Solicitações de feedback recebidas pelo colaborador (pendentes ou
  /// todas, conforme [apenasPendentes]) — usado na tela "Feedback" do
  /// módulo Gestor pra mostrar os pedidos da equipe.
  Future<List<Map<String, dynamic>>> listarSolicitacoesFeedbackRecebidas(
    int colaboradorId, {
    bool apenasPendentes = false,
  }) async {
    var query = _client
        .from('feedback_solicitacoes')
        .select()
        .eq('destinatario_id', colaboradorId);
    if (apenasPendentes) query = query.eq('status', 'pendente');
    final data = await query.order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Feedbacks de avaliação dados por um autor (gestor) à equipe.
  Future<List<Map<String, dynamic>>> listarFeedbacksDadosPor(
      int autorId) async {
    final data = await _client
        .from('avaliacao_feedbacks')
        .select()
        .eq('autor_id', autorId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<void> recusarSolicitacaoFeedback(int id) async {
    await _client.from('feedback_solicitacoes').update({
      'status': 'recusada',
      'respondido_em': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> marcarSolicitacaoFeedbackAtendida(
      int id, int feedbackId) async {
    await _client.from('feedback_solicitacoes').update({
      'status': 'atendida',
      'feedback_id': feedbackId,
      'respondido_em': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  // ─── Feed: banners RH, aniversário de empresa e pesquisas pendentes ─────────
  // (espelha os métodos equivalentes do gentepole_admin/api_service.dart)

  /// Banners gerenciados pelo RH para o carrossel do topo da Home/Feed.
  Future<List<Map<String, dynamic>>> listarBannersHome() async {
    final res = await _client
        .from('home_banners')
        .select()
        .eq('ativo', true)
        .order('ordem')
        .order('criado_em');
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> listarAcessoRapidoLinks() async {
    final res = await _client
        .from('acesso_rapido_links')
        .select()
        .eq('ativo', true)
        .order('ordem')
        .order('criado_em');
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> listarDocumentosInstitucionais() async {
    final res = await _client
        .from('documentos_institucionais')
        .select()
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Colaboradores que completam anos de empresa no mês (view
  /// `v_aniversarios_empresa_mes`), com `eh_hoje`, `dia_admissao` e
  /// `anos_completos`. Não existe ainda modelo dedicado no app — os
  /// dados são consumidos como Map diretamente pelo card do Feed.
  Future<List<Map<String, dynamic>>> buscarAniversariosEmpresaMesColab() async {
    final res = await _client
        .from('v_aniversarios_empresa_mes')
        .select()
        .order('eh_hoje', ascending: false)
        .order('dia_admissao', ascending: true);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Colaboradores admitidos na semana corrente (segunda a domingo) — vira
  /// automaticamente para a próxima semana assim que ela começa.
  Future<List<Map<String, dynamic>>> buscarNovosColaboradoresSemana() async {
    final hoje = DateTime.now();
    final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);
    final inicioSemana =
        hojeSemHora.subtract(Duration(days: hoje.weekday - 1));
    final fimSemana = inicioSemana.add(const Duration(days: 6));
    // Nunca inclui admissões com data futura (às vezes cadastram a data em
    // que o colaborador vai entrar, que pode ser um dia à frente).
    final limiteSuperior =
        fimSemana.isBefore(hojeSemHora) ? fimSemana : hojeSemHora;
    final fmt = (DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final res = await _client
        .from('colaboradores')
        .select('id, nome, setor, foto_url, data_admissao')
        .gte('data_admissao', fmt(inicioSemana))
        .lte('data_admissao', fmt(limiteSuperior))
        .order('data_admissao', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  // ─── Central de notificações (sino) ───────────────────────────────────────────
  // Espelha o sino do gentepole_admin: cada categoria de alerta é calculada
  // "ao vivo" a partir das próprias tabelas de negócio (pesquisas pendentes,
  // mensagens diretas, parabéns sem resposta, feedback, fim de experiência) e
  // depois filtrada pela tabela `notificacoes_dispensadas`, que guarda só a
  // marca "o colaborador já clicou nesse alerta" por `colaborador_id + chave`.

  /// Chaves de alertas já dispensados pelo colaborador logado.
  Future<Set<String>> listarNotificacoesDispensadas() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return {};
    final res = await _client
        .from('notificacoes_dispensadas')
        .select('chave')
        .eq('colaborador_id', meuId);
    return (res as List).map((e) => (e as Map)['chave'] as String).toSet();
  }

  /// Marca um alerta como dispensado (some do sino mesmo que a tarefa em si
  /// ainda não tenha sido concluída).
  Future<void> dispensarNotificacao(String chave) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return;
    await _client.from('notificacoes_dispensadas').upsert(
      {'colaborador_id': meuId, 'chave': chave},
      onConflict: 'colaborador_id,chave',
    );
  }

  /// Colaboradores perto do fim do período de experiência (90 dias após a
  /// admissão, a partir de 10 dias antes do limite) — porta fiel de
  /// `listarColaboradoresFimExperiencia` do gentepole_admin, adaptando ids
  /// `int` (este app) em vez de `String` (web). Só cobre o auto-check do
  /// colaborador logado (`colaboradorId`); a variante por `setor` (gestor
  /// olhando a equipe toda) é aceita mas não é usada pelo sino hoje.
  Future<List<Map<String, dynamic>>> listarColaboradoresFimExperiencia({
    int? colaboradorId,
    String? setor,
  }) async {
    var query =
        _client.from('colaboradores').select('id, nome, setor, data_admissao');
    if (colaboradorId != null) {
      query = query.eq('id', colaboradorId);
    } else if (setor != null) {
      query = query.eq('setor', setor);
    } else {
      return [];
    }
    final data = await query;
    final hoje = DateTime.now();
    final resultado = <Map<String, dynamic>>[];
    for (final c in List<Map<String, dynamic>>.from(data as List)) {
      final admissaoStr = c['data_admissao'] as String?;
      if (admissaoStr == null) continue;
      final admissao = DateTime.tryParse(admissaoStr);
      if (admissao == null) continue;
      final diasDesdeAdmissao = hoje.difference(admissao).inDays;
      final diasRestantes = 90 - diasDesdeAdmissao;
      if (diasRestantes >= 0 && diasRestantes <= 10) {
        resultado.add({...c, 'dias_restantes': diasRestantes});
      }
    }
    if (resultado.isEmpty) return resultado;

    final respondenteId = colaboradorAtual?.id;
    final pesquisa = await _client
        .from('pesquisas')
        .select('id')
        .eq('tipo', 'periodo_experiencia')
        .eq('ativa', true)
        .order('criado_em', ascending: false)
        .limit(1)
        .maybeSingle();
    if (pesquisa != null && respondenteId != null) {
      final pesquisaId = pesquisa['id'] as int;
      final alvoIds = resultado.map((c) => c['id']).toList();
      final respondidas = await _client
          .from('pesquisa_participacoes')
          .select('colaborador_alvo_id')
          .eq('pesquisa_id', pesquisaId)
          .eq('colaborador_id', respondenteId)
          .inFilter('colaborador_alvo_id', alvoIds);
      final jaRespondidos = List<Map<String, dynamic>>.from(respondidas)
          .map((r) => r['colaborador_alvo_id'])
          .toSet();
      resultado.removeWhere((c) => jaRespondidos.contains(c['id']));
    }

    resultado.sort(
        (a, b) => (a['dias_restantes'] as int).compareTo(b['dias_restantes'] as int));
    return resultado;
  }

  /// Mensagens diretas (`feed_posts` com `destinatario` = `@colaborador:<id>`
  /// ou `@colaborador:<id>|...`) recebidas pelo colaborador logado, de
  /// outra pessoa (exclui o que ele mesmo postou).
  Future<List<Map<String, dynamic>>> listarMensagensDiretasRecebidas(
      {int limite = 20}) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return [];
    final res = await _client
        .from('feed_posts')
        .select('*, autor:colaboradores!autor_id(nome, foto_url, cargo)')
        .or('destinatario.eq.@colaborador:$meuId,destinatario.like.@colaborador:$meuId|%')
        .order('criado_em', ascending: false)
        .limit(limite);
    return List<Map<String, dynamic>>.from(res as List)
        .where((p) => p['autor_id'] != meuId)
        .toList();
  }

  /// Parabéns recebidos pelo colaborador logado que ainda não tiveram
  /// resposta (`respondido_em IS NULL`).
  Future<List<Map<String, dynamic>>> listarParabensSemResposta() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return [];
    final res = await _client
        .from('parabens')
        .select('*, remetente:remetente_id(nome)')
        .eq('destinatario_id', meuId)
        .filter('respondido_em', 'is', null)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Feedbacks recebidos pelo colaborador logado ainda não lidos — mesma
  /// fonte de `contarFeedbacksNaoLidos`, mas retornando as linhas (não só a
  /// contagem) pra alimentar o sino.
  Future<List<Map<String, dynamic>>> listarFeedbacksNaoLidos() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return [];
    final res = await _client
        .from('feedbacks')
        .select()
        .eq('destinatario_id', meuId)
        .eq('lido', false)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Monta a lista unificada do sino de notificações: combina pesquisas
  /// pendentes, mensagens diretas não vistas, parabéns sem resposta,
  /// feedback recebido não lido, solicitação de feedback pendente e aviso de
  /// fim de experiência — filtra o que já foi dispensado e ordena por mais
  /// recente.
  Future<List<NotificacaoItem>> listarNotificacoesSino() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return [];

    final dispensadas = await listarNotificacoesDispensadas();
    final itens = <NotificacaoItem>[];

    try {
      final pesquisas = await buscarPesquisasDisponiveis();
      for (final p in pesquisas) {
        if (p['ja_respondeu'] == true) continue;
        final envioId = p['_envio_id'] ?? p['id'];
        final chave = 'pesquisa:$envioId';
        if (dispensadas.contains(chave)) continue;
        final criadoEm =
            DateTime.tryParse(p['criado_em'] as String? ?? '') ?? DateTime.now();
        itens.add(NotificacaoItem(
          chave: chave,
          tipo: 'pesquisa',
          titulo: 'Pesquisa pendente',
          subtitulo: (p['titulo'] as String?) ?? 'Você tem uma pesquisa para responder',
          criadoEm: criadoEm,
        ));
      }
    } catch (e) {
      debugPrint('Erro ao carregar pesquisas pendentes no sino: $e');
    }

    try {
      final mensagens = await listarMensagensDiretasRecebidas();
      for (final m in mensagens) {
        final chave = 'post:${m['id']}';
        if (dispensadas.contains(chave)) continue;
        final autor = m['autor'] as Map?;
        final autorNome = autor?['nome'] as String? ?? 'Alguém';
        itens.add(NotificacaoItem(
          chave: chave,
          tipo: 'mensagem',
          titulo: 'Mensagem de $autorNome',
          subtitulo: (m['titulo'] as String?) ??
              (m['conteudo'] as String?) ??
              'Você recebeu uma nova mensagem',
          criadoEm: DateTime.tryParse(m['criado_em'] as String? ?? '') ?? DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('Erro ao carregar mensagens diretas no sino: $e');
    }

    try {
      final parabens = await listarParabensSemResposta();
      for (final p in parabens) {
        final chave = 'parabens:${p['id']}';
        if (dispensadas.contains(chave)) continue;
        final remetente = p['remetente'] as Map?;
        final remetenteNome = remetente?['nome'] as String? ?? 'Alguém';
        itens.add(NotificacaoItem(
          chave: chave,
          tipo: 'parabens',
          titulo: 'Parabéns de $remetenteNome',
          subtitulo: (p['mensagem'] as String?) ?? 'Você recebeu um parabéns',
          criadoEm: DateTime.tryParse(p['criado_em'] as String? ?? '') ?? DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('Erro ao carregar parabéns no sino: $e');
    }

    try {
      final feedbacks = await listarFeedbacksNaoLidos();
      for (final f in feedbacks) {
        final chave = 'fb_recebido:${f['id']}';
        if (dispensadas.contains(chave)) continue;
        itens.add(NotificacaoItem(
          chave: chave,
          tipo: 'feedback',
          titulo: 'Novo feedback recebido',
          subtitulo: (f['mensagem'] as String?) ?? 'Você recebeu um feedback',
          criadoEm: DateTime.tryParse(f['criado_em'] as String? ?? '') ?? DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('Erro ao carregar feedbacks no sino: $e');
    }

    try {
      final solicitacoes = await listarSolicitacoesFeedbackRecebidas(
        meuId,
        apenasPendentes: true,
      );
      for (final s in solicitacoes) {
        final chave = 'fb_sol:${s['id']}';
        if (dispensadas.contains(chave)) continue;
        itens.add(NotificacaoItem(
          chave: chave,
          tipo: 'feedback',
          titulo: 'Solicitação de feedback',
          subtitulo: (s['mensagem'] as String?) ?? 'Alguém pediu um feedback seu',
          criadoEm: DateTime.tryParse(s['criado_em'] as String? ?? '') ?? DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('Erro ao carregar solicitações de feedback no sino: $e');
    }

    try {
      final experiencia = await listarColaboradoresFimExperiencia(colaboradorId: meuId);
      for (final c in experiencia) {
        final chave = 'experiencia:${c['id']}';
        if (dispensadas.contains(chave)) continue;
        final diasRestantes = c['dias_restantes'] as int;
        itens.add(NotificacaoItem(
          chave: chave,
          tipo: 'experiencia',
          titulo: 'Fim do período de experiência',
          subtitulo: diasRestantes <= 0
              ? 'Seu período de experiência está terminando'
              : 'Faltam $diasRestantes dia(s) para o fim do seu período de experiência',
          criadoEm: DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('Erro ao carregar aviso de experiência no sino: $e');
    }

    itens.sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
    return itens;
  }
}

/// Um item do sino de notificações — junta categorias bem diferentes
/// (pesquisa, mensagem, parabéns, feedback, experiência) num formato só,
/// suficiente pra desenhar o card e decidir a navegação ao tocar.
class NotificacaoItem {
  final String chave;
  final String tipo; // 'pesquisa' | 'mensagem' | 'parabens' | 'feedback' | 'experiencia'
  final String titulo;
  final String subtitulo;
  final DateTime criadoEm;

  NotificacaoItem({
    required this.chave,
    required this.tipo,
    required this.titulo,
    required this.subtitulo,
    required this.criadoEm,
  });
}

