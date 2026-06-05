import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:gentepole/models/comunicado_model.dart';
import 'package:gentepole/models/vaga_model.dart';
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

  // ─── Sessão ──────────────────────────────────────────────────────────────────

  ColaboradorModel? colaboradorAtual;
  void limparSessao() => colaboradorAtual = null;

  // ─── Auth ─────────────────────────────────────────────────────────────────────

  Future<({String status, ColaboradorModel? colaborador})> verificarMatricula(
    String matricula,
  ) async {
    final resultColaborador = await _client
        .from('colaboradores')
        .select()
        .eq('matricula', matricula)
        .maybeSingle();

    if (resultColaborador == null) {
      return (status: 'NAO_ENCONTRADO', colaborador: null);
    }

    final colaborador = ColaboradorModel.fromJson(resultColaborador);
    colaboradorAtual = colaborador;

    final resultAuth = await _client
        .from('usuarios_auth')
        .select('id')
        .eq('matricula', matricula)
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
    } catch (_) {
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
  Future<List<ComunicadoModel>> buscarUltimosComunicados() async {
    final data = await _client
        .from('comunicados')
        .select()
        .order('criado_em', ascending: false)
        .limit(4);

    return (data as List)
        .map((e) => ComunicadoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Todos os comunicados (para a tela de Comunicados)
  Future<List<ComunicadoModel>> buscarTodosComunicados() async {
    final data = await _client
        .from('comunicados')
        .select()
        .order('criado_em', ascending: false);

    return (data as List)
        .map((e) => ComunicadoModel.fromJson(e as Map<String, dynamic>))
        .toList();
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
      int vagaId) async {
    final data = await _client
        .from('candidaturas')
        .select('*, candidatos(*)')
        .eq('vaga_id', vagaId)
        .inFilter('status', ['ENTREV_GESTOR', 'PROPOSTA', 'APROVADO', 'REPROVADO'])
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => CandidaturaGestorModel.fromJson(e as Map<String, dynamic>))
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
          .update({'status': 'PROPOSTA'}).eq('id', candidaturaId);

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
      await _client.from('candidaturas').update({
        'status': 'REPROVADO',
        'motivo_reprovacao': motivo,
      }).eq('id', candidaturaId);

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
          .update({'status': 'APROVADO'}).eq('id', candidaturaId);

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

  /// Acompanhamento da admissão de um candidato aprovado
  Future<Map<String, dynamic>?> buscarStatusAdmissao(int candidaturaId) async {
    final data = await _client
        .from('admissoes')
        .select('status, cargo_admitido, setor_admitido, data_inicio, salario_acordado')
        .eq('candidatura_id', candidaturaId)
        .maybeSingle();
    return data;
  }
  
}
