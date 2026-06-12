import 'dart:convert';
import 'dart:typed_data';
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
      // Verifica se é um fornecedor (ex: massoterapeuta) cadastrado em usuarios_app
      final resultFornecedor = await _client
          .from('usuarios_app')
          .select('id')
          .eq('matricula', matricula.trim())
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

    return lista.where((item) {
      final tipo = item['tipo_destinatario'] as String? ?? 'todos';
      switch (tipo) {
        case 'todos':
          return true;
        case 'setor':
          final setores = item['setores_alvo'];
          if (setores == null) return false;
          return (setores as List).contains(colab.setor);
        case 'colaboradores':
          final colabs = item['colaboradores_alvo'];
          if (colabs == null) return false;
          return (colabs as List).contains(colab.id);
        case 'agrupamentos':
          final grupos = item['agrupamentos_alvo'];
          if (grupos == null) return false;
          return (grupos as List)
              .any((g) => meusAgrupamentos.contains(g as int));
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
      await _client.from('humor_registros').insert({
        'colaborador_id': meuId,
        'nivel': nivel,
        if (motivo != null && motivo.isNotEmpty) 'motivo': motivo,
      });
      return true;
    } catch (_) {
      return false;
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

  /// Lista pesquisas disponíveis filtradas por destinatário.
  Future<List<Map<String, dynamic>>> buscarPesquisasDisponiveis() async {
    final res = await _client
        .from('pesquisas')
        .select()
        .eq('ativa', true)
        .order('criado_em', ascending: false);

    final filtradas = await _filtrarDestinatarios(
      (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
    return filtradas;
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


}
