import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:gentepole/models/comunicado_model.dart';
import 'package:gentepole/models/lojinha_model.dart';
import 'package:gentepole/models/massoterapia_model.dart';
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
    int vagaId,
  ) async {
    final data = await _client
        .from('candidaturas')
        .select('*, candidatos(*)')
        .eq('vaga_id', vagaId)
        .inFilter('status', [
          'ENTREV_GESTOR',
          'PROPOSTA',
          'APROVADO',
          'REPROVADO',
        ])
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

  /// Dias disponíveis para massoterapia nas próximas 4 semanas,
  /// baseado nos dias_semana configurados pelo admin.
  Future<List<String>> buscarDiasDisponiveisMassoterapia() async {
    // Busca os dias da semana ativos (1=seg … 5=sex)
    final configDias = await _client
        .from('massoterapia_dias_disponiveis')
        .select('dia_semana')
        .eq('ativo', true);

    final diasAtivos = (configDias as List)
        .map((e) => e['dia_semana'] as int)
        .toSet();

    if (diasAtivos.isEmpty) return [];

    // Gera as próximas 4 semanas de datas válidas (a partir de hoje)
    final hoje = DateTime.now();
    final datas = <String>[];
    // Encontra a segunda-feira da semana atual
    final inicioSemana = hoje.subtract(Duration(days: hoje.weekday - 1));
    for (var i = 0; i < 5; i++) {
      final d = inicioSemana.add(Duration(days: i));
      if (diasAtivos.contains(d.weekday)) {
        final str =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        datas.add(str);
      }
    }
    return datas;
  }

  /// Todos os agendamentos com status AGENDADO nas próximas 4 semanas.
  /// Inclui join com colaboradores para exibir nome, matrícula e setor.
  Future<List<MassoterapiaAgendamentoModel>>
  buscarAgendamentosMassoterapia() async {
    final hoje = DateTime.now();
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

  /// Retorna true se o colaborador logado tem role de gestor na tabela usuarios_web.
  Future<bool> verificarSeEhGestor() async {
    final colaborador = colaboradorAtual;
    if (colaborador == null) return false;
    try {
      final res = await _client
          .from('usuarios_web')
          .select('id')
          .eq('colaborador_id', colaborador.id)
          .eq('role', 'gestor')
          .eq('ativo', true)
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  /// Busca as mensagens de parabéns recebidas pelo colaborador logado hoje.
  Future<List<Map<String, dynamic>>> buscarMensagensParabens() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return [];

    final res = await _client
        .from('parabens')
        .select('*, colaboradores!remetente_id(nome, setor)')
        .eq('destinatario_id', meuId)
        .order('criado_em', ascending: true);

    return (res as List).map((m) {
      final map = Map<String, dynamic>.from(m as Map); // ← cast aqui
      final col = map['colaboradores'] as Map?;
      return {
        ...map,
        'remetente_nome': col?['nome'] ?? 'Colega',
        'remetente_setor': col?['setor'],
      };
    }).toList();
  }

  // Cole estes métodos dentro da classe ApiService, na seção de Lojinha.
  // Imports necessários no topo do api_service.dart:
  //   import '../models/lojinha_model.dart';

  // ─── Lojinha ──────────────────────────────────────────────────────────────────

  /// Busca produtos ativos com estoque > 0
  Future<List<LojinhaProdutoModel>> buscarProdutosLojinha() async {
    final data = await _client
        .from('lojinha_produtos')
        .select()
        .eq('ativo', true)
        .gt('estoque', 0)
        .order('descricao', ascending: true);

    return (data as List)
        .map((e) => LojinhaProdutoModel.fromJson(e as Map<String, dynamic>))
        .toList();
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

  /// Envia pedido via Edge Function
  Future<({bool ok, String retorno, String? numeroPedido})>
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
    return (
      ok: data['ok'] as bool,
      retorno: data['retorno'] as String,
      numeroPedido: data['numeroPedido'] as String?,
    );
  }
}
