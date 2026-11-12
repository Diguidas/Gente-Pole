import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:gentepole/models/comunicado_model.dart';
import 'package:gentepole/models/feed_post_model.dart';
import 'package:gentepole/models/lojinha_model.dart';
import 'package:gentepole/models/fisioterapia_model.dart';
import 'package:gentepole/models/massoterapia_model.dart';
import 'package:gentepole/models/vaga_model.dart';
import 'package:gentepole/models/veiculo_model.dart';
import 'package:gentepole/screens/nutricionista/nutricionista_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/pontos_bus.dart';
import '../models/colaborador_model.dart';
import '../models/aniversariante_model.dart';
import '../core/error_reporter.dart';
import '../core/nome_foto.dart' show nomeCurto;
import 'documentos_cadastrais_service.dart';

/// Chave dos pesos de um ciclo no mesmo mapa dos pesos de template (ids de
/// template são positivos; os de ciclo ficam negativos).
int chavePesoCiclo(int cicloId) => -cicloId;

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
  // Matrícula sozinha não identifica a pessoa — o mesmo número pode existir
  // em empresas diferentes, pertencendo a pessoas diferentes. A sessão
  // precisa guardar as duas.
  static const _kEmpresaKey = 'sessao_empresa';

  ColaboradorModel? colaboradorAtual;

  Future<void> salvarSessao(String matricula, String? empresa) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMatriculaKey, matricula);
    if (empresa != null) {
      await prefs.setString(_kEmpresaKey, empresa);
    } else {
      await prefs.remove(_kEmpresaKey);
    }
  }

  Future<void> limparSessao() async {
    colaboradorAtual = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMatriculaKey);
    await prefs.remove(_kEmpresaKey);
  }

  /// Única porta de entrada do app: colaborador desligado nunca entra, e o
  /// bloqueio por setor/admin do painel (Configurações > Acesso por setor)
  /// vale por cima. Se a checagem falhar por qualquer motivo, NEGA.
  Future<bool> acessoLiberado(String matricula, String empresa) async {
    try {
      final r = await _client.rpc('acesso_liberado',
          params: {'p_matricula': matricula, 'p_empresa': empresa});
      return r == true;
    } catch (e, st) {
      ErrorReporter.report(e, st, contexto: 'Checar acesso ao sistema');
      return false;
    }
  }

  /// Conferência periódica de quem já está logado: `true` = segue liberado,
  /// `false` = acesso encerrado (desligado ou bloqueado no painel), `null` =
  /// não deu pra conferir (erro de rede) — nesse caso NÃO derruba a sessão,
  /// pra uma oscilação de internet não deslogar todo mundo.
  Future<bool?> verificarAcessoAtivo(String matricula, String empresa) async {
    try {
      final r = await _client.rpc('acesso_liberado',
          params: {'p_matricula': matricula, 'p_empresa': empresa});
      return r == true;
    } catch (_) {
      return null;
    }
  }

  /// Tenta restaurar a sessão salva. Retorna true se conseguiu.
  Future<bool> restaurarSessao() async {
    final prefs = await SharedPreferences.getInstance();
    final matricula = prefs.getString(_kMatriculaKey);
    final empresa = prefs.getString(_kEmpresaKey);
    if (matricula == null || empresa == null) return false;

    final data = await _client
        .from('colaboradores')
        .select()
        .eq('matricula', matricula)
        .eq('empresa', empresa)
        .maybeSingle();
    if (data == null || !await acessoLiberado(matricula, empresa)) {
      await prefs.remove(_kMatriculaKey);
      await prefs.remove(_kEmpresaKey);
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
        .order('demitido', ascending: true, nullsFirst: true).order('data_admissao', ascending: false).limit(1).maybeSingle();

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
    if (!await acessoLiberado(colaborador.matricula, colaborador.empresa ?? '')) {
      return (status: 'SEM_ACESSO', colaborador: null);
    }
    colaboradorAtual = colaborador;

    final resultAuth = await _client
        .from('usuarios_auth')
        .select('id')
        .eq('matricula', colaborador.matricula)
        .eq('empresa', colaborador.empresa!)
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
    if (empresa == null) return false;
    if (!await acessoLiberado(matricula, empresa)) return false;
    try {
      // Confere a data de nascimento digitada (AAAA-MM-DD) com o cadastro antes
      // de criar a senha — igual ao web. (A trava definitiva precisa existir
      // também dentro da função criar_usuario_auth, no banco.)
      final colab = await _client
          .from('colaboradores')
          .select('data_nascimento')
          .eq('matricula', matricula)
          .eq('empresa', empresa)
          .maybeSingle();
      final nascBd = (colab?['data_nascimento'] as String? ?? '');
      if (dataNascimento.isEmpty ||
          nascBd.isEmpty ||
          !nascBd.startsWith(dataNascimento)) {
        return false;
      }
      await _client.rpc('criar_usuario_auth', params: {
        'p_matricula': matricula,
        'p_empresa': empresa,
        'p_senha_hash': _hash(senha),
        'p_data_nascimento': dataNascimento,
      });
      return true;
    } catch (e, st) {
      debugPrint('criarConta ERRO matricula=$matricula empresa=$empresa: $e');
      ErrorReporter.report(e, st, contexto: 'Criar conta (primeiro acesso)');
      return false;
    }
  }

  Future<bool> validarLogin({
    required String matricula,
    required String empresa,
    required String senha,
  }) async {
    final data = await _client
        .from('usuarios_auth')
        .select('senha_hash')
        .eq('matricula', matricula)
        .eq('empresa', empresa)
        .maybeSingle();
    if (data == null) return false;
    if (data['senha_hash'] != _hash(senha)) return false;
    return acessoLiberado(matricula, empresa);
  }

  /// Reseta a senha de quem já tem conta, mediante confirmação da data de
  /// nascimento (mesma verificação usada no primeiro acesso).
  /// Retorna false se a data não bater ou se a conta não existir.
  Future<bool> resetarSenhaEsquecida({
    required String matricula,
    required String empresa,
    required String dataNascimento,
    required String novaSenha,
  }) async {
    try {
      final colaborador = await _client
          .from('colaboradores')
          .select('data_nascimento')
          .eq('matricula', matricula)
          .eq('empresa', empresa)
          .maybeSingle();
      if (colaborador == null) return false;
      final nascBd = (colaborador['data_nascimento'] as String? ?? '');
      if (dataNascimento.isEmpty ||
          nascBd.isEmpty ||
          !nascBd.startsWith(dataNascimento)) {
        return false;
      }
      if (!await acessoLiberado(matricula, empresa)) return false;

      final auth = await _client
          .from('usuarios_auth')
          .update({'senha_hash': _hash(novaSenha)})
          .eq('matricula', matricula)
          .eq('empresa', empresa)
          .select('id');
      return auth.isNotEmpty;
    } catch (e, st) {
      debugPrint('resetarSenhaEsquecida ERRO matricula=$matricula empresa=$empresa: $e');
      ErrorReporter.report(e, st, contexto: 'Resetar senha esquecida');
      return false;
    }
  }

  /// Telemetria de engajamento: registra que o colaborador abriu o app (uma
  /// linha por abertura; o painel conta colaboradores únicos por dia). Erro
  /// aqui nunca pode atrapalhar o uso do app.
  Future<void> registrarAcessoApp() async {
    final id = colaboradorAtual?.id;
    if (id == null) return;
    try {
      await _client.from('acessos_app').insert({
        'colaborador_id': int.tryParse(id.toString()) ?? id,
        'origem': 'app',
      });
    } catch (_) {}
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

  /// Config de versão mínima/recomendada do app (ver VersionCheckService) —
  /// linha única (id sempre 1), editada pelo admin no painel web.
  Future<Map<String, dynamic>?> buscarConfigVersaoApp() async {
    return await _client
        .from('app_versao_config')
        .select()
        .eq('id', 1)
        .maybeSingle();
  }

  // ─── Aniversariantes ──────────────────────────────────────────────────────────

  /// Todos os aniversariantes do mês — hoje primeiro, depois por dia crescente.
  Future<List<AniversarianteModel>> buscarAniversariantesMes() async {
    final data = await _client
        .from('v_aniversariantes_mes')
        .select()
        .order('eh_hoje', ascending: false)
        .order('dia_nascimento', ascending: true);

    final linhas = await _comApelidos(
        List<Map<String, dynamic>>.from(data as List));
    return linhas.map((e) => AniversarianteModel.fromJson(e)).toList();
  }

  /// Views não expõem `apelido`: busca em `colaboradores` pelo `id` de cada
  /// linha e injeta a chave `apelido` (quando a pessoa tiver).
  Future<List<Map<String, dynamic>>> _comApelidos(
      List<Map<String, dynamic>> linhas) async {
    final ids = linhas.map((l) => l['id']).where((i) => i != null).toSet().toList();
    if (ids.isEmpty) return linhas;
    try {
      final res = await _client
          .from('colaboradores')
          .select('id, apelido')
          .inFilter('id', ids)
          .not('apelido', 'is', null);
      final mapa = {for (final r in res) r['id'].toString(): r['apelido']};
      for (final l in linhas) {
        final a = mapa[l['id']?.toString()];
        if (a != null) l['apelido'] = a;
      }
    } catch (_) {}
    return linhas;
  }

  /// Salva o "nome que gosta de ser chamado" (vazio remove) e atualiza o
  /// colaborador da sessão.
  Future<void> salvarApelido(String? apelido) async {
    final atual = colaboradorAtual;
    if (atual == null) return;
    final limpo = apelido?.trim() ?? '';
    await _client
        .from('colaboradores')
        .update({'apelido': limpo.isEmpty ? null : limpo}).eq('id', atual.id);
    colaboradorAtual = ColaboradorModel(
      id: atual.id,
      matricula: atual.matricula,
      nome: atual.nome,
      setor: atual.setor,
      cargo: atual.cargo,
      cpf: atual.cpf,
      dataNascimento: atual.dataNascimento,
      dataAdmissao: atual.dataAdmissao,
      supervisorId: atual.supervisorId,
      fotoUrl: atual.fotoUrl,
      apelido: limpo.isEmpty ? null : limpo,
      clienteSap: atual.clienteSap,
      codCentro: atual.codCentro,
      empresa: atual.empresa,
      ehGestor: atual.ehGestor,
      branch: atual.branch,
    );
  }

  // ─── Gamificação: pontos e ranking ────────────────────────────────────────

  /// Interruptor geral do Polecoin (ligado/desligado pelo RH em
  /// Administração > Gamificação): desligado, o chip de saldo, a tela de
  /// Polecoin e o item no menu de Serviços somem até religar.
  Future<bool> gamificacaoAtiva() async {
    final row = await _client
        .from('gamificacao_config_geral')
        .select('ativo')
        .eq('id', 1)
        .maybeSingle();
    return row?['ativo'] as bool? ?? true;
  }

  // ─── Performance: materiais, visual e Tô na Trilha ────────────────────────

  /// Materiais de apoio (links) da tela Performance. [gestor] = false filtra
  /// os marcados como "só gestores" — o app do colaborador nunca os mostra,
  /// mesmo que a pessoa seja gestor.
  Future<List<Map<String, dynamic>>> listarMateriaisPerformance({required bool gestor}) async {
    final res = await _client
        .from('performance_materiais')
        .select()
        .order('ordem')
        .order('criado_em');
    final lista = List<Map<String, dynamic>>.from(res);
    return gestor ? lista : lista.where((m) => m['publico_alvo'] != 'gestor').toList();
  }

  /// Mapa chave → URL do banner e dos ícones dos botões da Performance
  /// (banner, periodo_experiencia, avaliacao, avaliar_colegas, pdi, feedback,
  /// programa_carreira, to_na_trilha_banner).
  Future<Map<String, String>> listarPerformanceVisual() async {
    try {
      final res = await _client.from('performance_visual').select('chave, imagem_url');
      return {for (final r in res) r['chave'] as String: r['imagem_url'] as String};
    } catch (_) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> listarToNaTrilhaItens() async {
    final res = await _client
        .from('to_na_trilha_itens')
        .select()
        .order('ordem')
        .order('id');
    return List<Map<String, dynamic>>.from(res);
  }

  Future<String> obterToNaTrilhaDescricao() async {
    final r = await _client
        .from('to_na_trilha_config')
        .select('valor')
        .eq('chave', 'descricao')
        .maybeSingle();
    return (r?['valor'] as String?) ?? '';
  }

  // ─── Folha: contracheque ───────────────────────────────────────────────

  /// Interruptor geral do Contracheque (ligado/desligado pelo RH em
  /// Administração de Folha, enquanto a tela ainda está em construção):
  /// desligado, o item "Contracheque" some do menu de Serviços até religar.
  Future<bool> folhaContrachequeAtiva() async {
    final row = await _client
        .from('folha_config_geral')
        .select('ativo')
        .eq('id', 1)
        .maybeSingle();
    return row?['ativo'] as bool? ?? true;
  }

  // ─── Contracheque ───────────────────────────────────────────────────────────

  /// O colaborador nunca chama a TOTVS ao vivo — só lê `folha_eventos`, que
  /// o DP já populou pela tela "Administração de Folha > Execuções". Só
  /// mostra o mês se o período 2 (Folha Mensal) daquele mês/ano estiver
  /// com status 'ok' em `folha_execucoes`.
  Future<bool> contrachequeDisponivel({required int mes, required int ano}) async {
    final row = await _client
        .from('folha_execucoes')
        .select('status')
        .eq('mes', mes)
        .eq('ano', ano)
        .eq('periodo', 2)
        .maybeSingle();
    return row?['status'] == 'ok';
  }

  static const nomesPeriodoFolha = {
    2: 'Folha Mensal',
    3: 'Férias',
    6: 'Complementar',
    7: '13º Salário',
  };

  /// Competências (mês/ano) em que esse colaborador tem ao menos um evento
  /// de folha lançado, mais recente primeiro. Usada pra listar dinamicamente
  /// os meses disponíveis em vez de fixar um mês só.
  /// Competências (mês/ano) desativadas pelo DP, no formato 'ano-mes'
  /// (ex: '2026-9'). Sem registro = visível.
  Future<Set<String>> listarCompetenciasFolhaOcultas() async {
    final res = await _client
        .from('folha_competencia_visibilidade')
        .select('mes, ano')
        .eq('visivel', false);
    return List<Map<String, dynamic>>.from(res)
        .map((r) => '${r['ano']}-${r['mes']}')
        .toSet();
  }

  Future<List<Map<String, dynamic>>> listarCompetenciasContracheque() async {
    final matricula = colaboradorAtual?.matricula;
    if (matricula == null) return [];

    final linhas = await _client
        .from('folha_eventos')
        .select('mes, ano')
        .eq('matricula', matricula);
    final competencias = <String, Map<String, dynamic>>{};
    for (final l in List<Map<String, dynamic>>.from(linhas)) {
      final mes = l['mes'] as int;
      final ano = l['ano'] as int;
      competencias['$ano-$mes'] = {'mes': mes, 'ano': ano};
    }
    final ocultas = await listarCompetenciasFolhaOcultas();
    final lista = competencias.values
        .where((c) => !ocultas.contains('${c['ano']}-${c['mes']}'))
        .toList();
    lista.sort((a, b) {
      final anoCmp = (b['ano'] as int).compareTo(a['ano'] as int);
      return anoCmp != 0 ? anoCmp : (b['mes'] as int).compareTo(a['mes'] as int);
    });
    return lista;
  }

  /// Períodos que esse colaborador tem de verdade nesse mês/ano — se ele
  /// recebeu Folha Mensal + Férias no mesmo mês, por exemplo, são DOIS
  /// contracheques separados, nunca somados num só. Só considera período
  /// com execução 'ok' e que tenha ao menos uma linha pra essa matrícula.
  Future<List<Map<String, dynamic>>> listarPeriodosContracheque({
    required int mes,
    required int ano,
  }) async {
    final matricula = colaboradorAtual?.matricula;
    if (matricula == null) return [];
    // Mês desativado pelo DP: nenhum contracheque dele fica disponível.
    if ((await listarCompetenciasFolhaOcultas()).contains('$ano-$mes')) return [];

    final execucoesOk = await _client
        .from('folha_execucoes')
        .select('periodo')
        .eq('mes', mes)
        .eq('ano', ano)
        .eq('status', 'ok');
    final periodosOk = List<Map<String, dynamic>>.from(execucoesOk).map((e) => e['periodo'] as int).toList();
    if (periodosOk.isEmpty || !periodosOk.contains(2)) {
      // Sem a Folha Mensal 'ok', o mês inteiro fica indisponível.
      return [];
    }

    final linhas = await _client
        .from('folha_eventos')
        .select('periodo')
        .eq('mes', mes)
        .eq('ano', ano)
        .eq('matricula', matricula)
        .inFilter('periodo', periodosOk);
    final periodosComDado = List<Map<String, dynamic>>.from(linhas).map((l) => l['periodo'] as int).toSet();

    return periodosComDado
        .map((p) => {'periodo': p, 'nome': nomesPeriodoFolha[p] ?? 'Período $p'})
        .toList()
      ..sort((a, b) => (a['periodo'] as int).compareTo(b['periodo'] as int));
  }

  /// Busca o contracheque do colaborador logado, já traduzido (código ->
  /// descrição) e separado em proventos/descontos. [periodo]: 2 = Folha
  /// Mensal (padrão), 3 = Férias, 6 = Complementar, 7 = 13º Salário.
  Future<Map<String, dynamic>?> buscarContracheque({
    required int mes,
    required int ano,
    int periodo = 2,
  }) async {
    final matricula = colaboradorAtual?.matricula;
    if (matricula == null) return null;

    if (periodo == 2 && !await contrachequeDisponivel(mes: mes, ano: ano)) {
      return null;
    }

    final linhas = await _client
        .from('folha_eventos')
        .select('codigo_evento, valor')
        .eq('mes', mes)
        .eq('ano', ano)
        .eq('periodo', periodo)
        .eq('matricula', matricula);
    final lista = List<Map<String, dynamic>>.from(linhas);
    if (lista.isEmpty) {
      return {
        'ok': true,
        'eventos': [],
        'totalProventos': 0,
        'totalDescontos': 0,
        'liquido': 0,
      };
    }

    final codigos = lista.map((l) => l['codigo_evento'] as String).toSet().toList();
    final catalogo = await _client
        .from('eventos_folha')
        .select('codigo, descricao, tipo')
        .inFilter('codigo', codigos);
    final catalogoPorCodigo = {
      for (final e in List<Map<String, dynamic>>.from(catalogo)) e['codigo'] as String: e,
    };

    double totalProventos = 0;
    double totalDescontos = 0;
    final eventos = lista.map((l) {
      final info = catalogoPorCodigo[l['codigo_evento']];
      final tipo = info?['tipo'] as String? ?? 'Provento';
      final valor = (l['valor'] as num).toDouble();
      if (tipo == 'Provento') totalProventos += valor;
      if (tipo == 'Desconto') totalDescontos += valor;
      return {
        'codigo': l['codigo_evento'],
        'descricao': info?['descricao'] as String? ?? 'Evento ${l['codigo_evento']}',
        'tipo': tipo,
        'valor': valor,
      };
    }).toList();

    return {
      'ok': true,
      'eventos': eventos,
      'totalProventos': totalProventos,
      'totalDescontos': totalDescontos,
      'liquido': totalProventos - totalDescontos,
    };
  }

  // ─── Manual de Uso (Suporte Técnico) ───────────────────────────────────────

  /// Vídeos/PDFs de "como usar o app", cadastrados pelo Endomkt.
  Future<List<Map<String, dynamic>>> listarManuaisUso() async {
    final res = await _client
        .from('manuais_uso')
        .select()
        .order('ordem')
        .order('criado_em');
    return List<Map<String, dynamic>>.from(res);
  }

  /// Ações elegíveis e o valor de cada uma, configurado pelo RH.
  Future<List<Map<String, dynamic>>> listarPontosConfig() async {
    final data = await _client
        .from('pontos_config')
        .select()
        .eq('ativo', true)
        .order('chave');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Meta de pontos pra virar vaúcher (o RH entra em contato quando o
  /// colaborador atinge — não há resgate automático no app).
  Future<Map<String, dynamic>?> buscarMetaPontos() async {
    return await _client.from('pontos_meta').select().eq('id', 1).maybeSingle();
  }

  /// Saldo de Polens do colaborador logado.
  Future<int> buscarMeusPontos() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return 0;
    final row = await _client
        .from('vw_ranking_pontos')
        .select('total_pontos')
        .eq('colaborador_id', meuId)
        .maybeSingle();
    return row?['total_pontos'] as int? ?? 0;
  }

  /// Posicao do colaborador no ranking da filial (quantos tem mais pontos + 1)
  /// e total de pessoas no ranking da filial — igual ao web.
  Future<({int posicao, int totalFilial})> buscarMinhaPosicaoRanking({
    required String branch,
    required int meusPontos,
  }) async {
    final maiores = await _client
        .from('vw_ranking_pontos')
        .select('colaborador_id')
        .eq('branch', branch)
        .gt('total_pontos', meusPontos)
        .count();
    final total = await _client
        .from('vw_ranking_pontos')
        .select('colaborador_id')
        .eq('branch', branch)
        .count();
    return (posicao: maiores.count + 1, totalFilial: total.count);
  }

  /// Ranking de pontos da mesma filial do colaborador logado — nunca mostra
  /// gente de outra filial.
  Future<List<Map<String, dynamic>>> buscarRankingPontosDaMinhaFilial() async {
    final filial = colaboradorAtual?.filialEfetiva;
    if (filial == null || filial.isEmpty) return [];
    final data = await _client
        .from('vw_ranking_pontos')
        .select()
        .eq('branch', filial)
        .gt('total_pontos', 0)
        .order('total_pontos', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
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
    final inicioDia = DateTime(
      hoje.year,
      hoje.month,
      hoje.day,
    ).toIso8601String();
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
      PontosBus.notificarGanho();
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
      await _client
          .from('parabens')
          .update({
            'resposta': respostaLimpa,
            'respondido_em': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', parabensId);

      final colabAtual = colaboradorAtual;
      final meuPrimeiroNome = colabAtual == null
          ? 'Alguém'
          : nomeCurto(colabAtual.nome, colabAtual.apelido);
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

  static const _ordemNiveisHierarquia = [
    'gerente_geral',
    'gestor',
    'coordenador',
    'supervisor',
    'encarregado',
    'lider',
  ];

  /// Hierarquia já resolvida do colaborador (Administração de setor do
  /// painel): quem é o gerente geral, gestor, coordenador, supervisor etc.
  /// dele. Ignora responsáveis desligados e vem do nível mais alto ao mais
  /// baixo. Cada item: `{nivel, nome}`.
  Future<List<Map<String, String>>> buscarHierarquiaDoColaborador(
      int colaboradorId) async {
    final res = await _client
        .from('colaborador_hierarquia')
        .select(
            'nivel, responsavel:colaboradores!colaborador_hierarquia_responsavel_id_fkey(nome, demitido)')
        .eq('colaborador_id', colaboradorId);
    final itens = <Map<String, String>>[];
    for (final h in res as List) {
      final resp = h['responsavel'] as Map?;
      final nome = resp?['nome'] as String?;
      if (nome == null || resp?['demitido'] == true) continue;
      itens.add({'nivel': h['nivel'] as String, 'nome': nome});
    }
    itens.sort((a, b) {
      final ia = _ordemNiveisHierarquia.indexOf(a['nivel']!);
      final ib = _ordemNiveisHierarquia.indexOf(b['nivel']!);
      return ia.compareTo(ib);
    });
    return itens;
  }

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
        .eq('demitido', false)
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
    final meusAgrupamentos = (membros as List)
        .map((e) => e['agrupamento_id'] as int)
        .toSet();

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
        case 'setores': // o painel web grava 'setores'
          return _parseList(item['setores_alvo']).contains(colab.setor);
        case 'colaboradores':
          final colabs = _parseList(item['colaboradores_alvo']);
          return colabs.contains(colab.id) ||
              colabs.contains(colab.id.toString());
        case 'agrupamentos':
          final grupos = _parseList(item['agrupamentos_alvo']);
          return grupos.any(
            (g) => meusAgrupamentos.contains(
              g is int ? g : int.tryParse(g.toString()) ?? -1,
            ),
          );
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

    return filtrados.take(4).map((e) => ComunicadoModel.fromJson(e)).toList();
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
    final empresa = colaboradorAtual?.empresa;
    if (matricula == null || empresa == null) return false;

    // Verifica senha atual
    final ok = await validarLogin(
        matricula: matricula, empresa: empresa, senha: senhaAtual);
    if (!ok) return false;

    try {
      await _client
          .from('usuarios_auth')
          .update({'senha_hash': _hash(novaSenha)})
          .eq('matricula', matricula)
          .eq('empresa', empresa);
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
  /// Função efetiva de um template: a função associada (cargo da TOTVS) ou,
  /// se ainda não houver, o título — os templates antigos seguem funcionando.
  static String funcaoEfetivaDoTemplate(Map<String, dynamic> t) {
    final f = (t['funcao'] as String?)?.trim() ?? '';
    return f.isNotEmpty ? f : ((t['titulo'] as String?)?.trim() ?? '');
  }

  /// Comparação de função/cargo sem diferença de maiúsculas e espaços.
  static String normalizarFuncao(String? s) => (s ?? '').trim().toUpperCase();

  /// Pares (setor, função) em que o colaborador logado é requisitante de
  /// vaga (`vaga_requisitantes`) — definem os templates e a equipe que ele
  /// enxerga na abertura de vaga, mesmo sem liderar ninguém.
  Future<List<({String setor, String funcao})>> listarParesRequisitante() async {
    final colab = colaboradorAtual;
    if (colab == null) return [];
    final res = await _client
        .from('vaga_requisitantes')
        .select('setor, funcao')
        .eq('colaborador_id', colab.id);
    return List<Map<String, dynamic>>.from(res as List)
        .map((r) => (setor: r['setor'] as String, funcao: r['funcao'] as String))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarTemplatesGestor({
    String? setor,
    List<String>? setores,
    List<({String setor, String funcao})>? paresSetorFuncao,
  }) async {
    const colunas =
        'id, titulo, funcao, departamento, tipo_contrato, tipo_vaga, teste_pratico, descricao';
    final resultados = <int, Map<String, dynamic>>{};

    final listaSetores =
        setores?.where((s) => s.isNotEmpty).toList() ?? const [];
    if (listaSetores.isNotEmpty || (setor != null && setor.isNotEmpty)) {
      var q = _client.from('ats_templates').select(colunas).eq('ativo', true);
      q = listaSetores.isNotEmpty
          ? q.inFilter('departamento', listaSetores)
          : q.eq('departamento', setor!);
      final data = await q;
      for (final t in List<Map<String, dynamic>>.from(data as List)) {
        resultados[t['id'] as int] = t;
      }
    }

    // Requisitante de vaga: soma os templates exatos dos pares (setor, função)
    // dele — mesmo fora dos setores onde ele é gestor.
    final pares = paresSetorFuncao
            ?.where((p) => p.setor.isNotEmpty && p.funcao.isNotEmpty)
            .toList() ??
        const [];
    if (pares.isNotEmpty) {
      final setoresDosPares = pares.map((p) => p.setor).toSet().toList();
      final data = await _client
          .from('ats_templates')
          .select(colunas)
          .eq('ativo', true)
          .inFilter('departamento', setoresDosPares);
      for (final t in List<Map<String, dynamic>>.from(data as List)) {
        final bate = pares.any((p) =>
            p.setor == t['departamento'] &&
            normalizarFuncao(p.funcao) ==
                normalizarFuncao(funcaoEfetivaDoTemplate(t)));
        if (bate) resultados[t['id'] as int] = t;
      }
    }

    return resultados.values.toList()
      ..sort((a, b) =>
          (a['titulo'] as String? ?? '').compareTo(b['titulo'] as String? ?? ''));
  }

  /// Níveis da hierarquia de setor (ver Administração de Setor no painel web)
  /// que dão acesso ao módulo Gestão de Equipe. Mesmo conjunto de
  /// `ApiService.niveisComAcessoDeGestor` no gentepole_admin (lá a ordem é
  /// só de exibição; aqui, além disso, define prioridade de "mais próximo" —
  /// por isso a ordem aqui vai do nível mais próximo do colaborador pro mais
  /// distante, não a mesma ordem do admin. Faltava 'encarregado' e a posição
  /// de 'gestor' estava errada (2º lugar), fazendo cair direto nele antes de
  /// checar supervisor/coordenador.
  static const _niveisComAcessoDeGestor = [
    'lider',
    'encarregado',
    'supervisor',
    'coordenador',
    'gestor',
    'gerente_geral',
  ];

  /// Setores que o gestor logado efetivamente enxerga: o setor do próprio
  /// cadastro dele SEMPRE conta, somado aos setores extras associados
  /// manualmente em `gestor_setores` (gestor de mais de um setor) e aos
  /// setores onde ele está atribuído como gestor/coordenador/supervisor na
  /// Administração de Setor (`setor_hierarquia`) — mesma regra do painel web.
  Future<List<String>> buscarSetoresEfetivosDoGestor() async {
    final colab = colaboradorAtual;
    if (colab == null) return [];
    final matricula = colab.matricula;
    final empresa = colab.empresa ?? '';
    final data = await _client
        .from('gestor_setores')
        .select('setor')
        .eq('matricula_gestor', matricula)
        .eq('empresa', empresa);
    final setores = <String>{
      for (final row in (data as List)) row['setor'] as String,
    };
    final hierarquia = await _client
        .from('setor_hierarquia')
        .select('setor')
        .eq('colaborador_id', colab.id)
        .inFilter('nivel', _niveisComAcessoDeGestor);
    for (final h in (hierarquia as List)) {
      final s = h['setor'] as String?;
      if (s != null && s.isNotEmpty) setores.add(s);
    }
    // O setor de lotação só vale quando não há nenhum setor atribuído; senão
    // quem é lotado num setor mas gere outro veria a equipe errada.
    if (setores.isEmpty &&
        colab.setor != null &&
        colab.setor!.isNotEmpty &&
        colab.setor != '—') {
      setores.add(colab.setor!);
    }
    return setores.toList();
  }

  /// Equipe do gestor logado, já respeitando a Administração de Setor: quem
  /// está atribuído como supervisor de um grupo específico de liderados
  /// (`colaboradores_alvo`) só vê essas pessoas; gestor/coordenador (que
  /// cobrem o setor inteiro) veem todo mundo do setor. Setor sem hierarquia
  /// configurada continua mostrando todo mundo, como sempre foi — mantém
  /// compatibilidade com quem só está em `gestor_setores` (legado).
  ///
  /// [incluirDemitidos] só deve ser usado no picker de "colaborador a
  /// substituir" da abertura de vaga: junta, além da equipe ativa, os
  /// demitidos desses setores (menos prestadores) — o gestor precisa
  /// conseguir indicar quem acabou de sair. Quem já foi indicado como
  /// substituído em outra vaga é tirado depois, na tela.
  ///
  /// Com [apenasLiderDireto] (telas de avaliação, PDI, vagas), cada pessoa só
  /// entra na equipe do responsável do nível mais próximo dela: o líder avalia
  /// a equipe, quem está um nível acima avalia o líder, e assim por diante.
  /// Quem tem a [funcionalidade] bloqueada em `gestor_permissoes` não conta
  /// como líder direto — a pessoa sobe pro próximo nível liberado.
  Future<List<Map<String, dynamic>>> buscarEquipeGestorMultiSetor(
      List<String> setores,
      {int? responsavelId,
      bool incluirDemitidos = false,
      bool apenasLiderDireto = false,
      String? funcionalidade}) async {
    if (setores.isEmpty) return [];

    final ativos = await _buscarEquipeAtivaMultiSetor(setores, responsavelId,
        apenasLiderDireto: apenasLiderDireto, funcionalidade: funcionalidade);
    if (!incluirDemitidos) return ativos;

    var demitidos = List<Map<String, dynamic>>.from(await _client
        .from('colaboradores')
        .select()
        .inFilter('setor', setores)
        .eq('demitido', true)
        .not('cargo', 'ilike', 'PRESTADOR%') as List);
    if (responsavelId != null) {
      // Mesma regra dos ativos: só quem era liderado por [responsavelId]
      // (setor sem hierarquia configurada continua mostrando todos).
      final v = await _vinculosDoResponsavel(setores, responsavelId,
          apenasLiderDireto: apenasLiderDireto, funcionalidade: funcionalidade);
      demitidos = demitidos
          .where((c) =>
              !v.setoresComHierarquia.contains(c['setor']) ||
              v.meus.contains(c['id']))
          .toList();
    }
    final porId = <int, Map<String, dynamic>>{
      for (final c in ativos) c['id'] as int: c,
    };
    for (final c in (demitidos as List)) {
      porId.putIfAbsent(
          c['id'] as int, () => Map<String, dynamic>.from(c as Map));
    }
    return porId.values.toList()
      ..sort((a, b) =>
          (a['nome'] as String? ?? '').compareTo(b['nome'] as String? ?? ''));
  }

  Future<List<Map<String, dynamic>>> _buscarEquipeAtivaMultiSetor(
      List<String> setores, int? responsavelId,
      {bool apenasLiderDireto = false, String? funcionalidade}) async {
    if (responsavelId == null) {
      final data = await _client
          .from('colaboradores')
          .select()
          .inFilter('setor', setores)
          .eq('demitido', false)
          .order('nome');
      return List<Map<String, dynamic>>.from(data as List);
    }

    final vinculos = await _vinculosDoResponsavel(setores, responsavelId,
        apenasLiderDireto: apenasLiderDireto, funcionalidade: funcionalidade);
    final setoresComHierarquia = vinculos.setoresComHierarquia;
    final idsPermitidos = vinculos.meus;
    final setoresSemHierarquia =
        setores.where((s) => !setoresComHierarquia.contains(s)).toList();

    final resultados = <int, Map<String, dynamic>>{};

    if (idsPermitidos.isNotEmpty) {
      final data = await _client
          .from('colaboradores')
          .select()
          .inFilter('id', idsPermitidos.toList())
          .eq('demitido', false);
      for (final c in (data as List)) {
        resultados[c['id'] as int] = c as Map<String, dynamic>;
      }
    }
    if (setoresSemHierarquia.isNotEmpty) {
      final data = await _client
          .from('colaboradores')
          .select()
          .inFilter('setor', setoresSemHierarquia)
          .eq('demitido', false);
      for (final c in (data as List)) {
        resultados[c['id'] as int] = c as Map<String, dynamic>;
      }
    }

    // Ninguém é da própria equipe.
    resultados.remove(responsavelId);

    final lista = resultados.values.toList()
      ..sort((a, b) =>
          (a['nome'] as String? ?? '').compareTo(b['nome'] as String? ?? ''));
    return lista;
  }

  /// Quem [responsavelId] lidera nesses setores, lendo `colaborador_hierarquia`.
  /// Padrão: todos que têm ele como responsável em qualquer nível. Com
  /// [apenasLiderDireto], só quem o tem como responsável do nível mais
  /// próximo (pulando quem tem [funcionalidade] bloqueada). Havendo vários
  /// "gerais" no mesmo nível, vale o de menor id.
  Future<({Set<String> setoresComHierarquia, Set<int> meus})>
      _vinculosDoResponsavel(List<String> setores, int? responsavelId,
          {bool apenasLiderDireto = false, String? funcionalidade}) async {
    final hierarquia = await _client
        .from('colaborador_hierarquia')
        .select('setor, colaborador_id, responsavel_id, nivel')
        .inFilter('setor', setores);
    final setoresComHierarquia = <String>{};
    final meus = <int>{};
    final lideresDiretos = <int, ({int rank, int responsavel})>{};
    final bloqueados = (apenasLiderDireto && funcionalidade != null)
        ? await _colaboradoresComFuncionalidadeBloqueada(funcionalidade)
        : <int>{};
    for (final h in (hierarquia as List)) {
      setoresComHierarquia.add(h['setor'] as String);
      if (apenasLiderDireto) {
        final colabId = h['colaborador_id'] as int;
        // _niveisComAcessoDeGestor já vem do nível mais próximo ao mais distante.
        final rank = _niveisComAcessoDeGestor.indexOf(h['nivel'] as String);
        if (rank < 0) continue;
        final resp = h['responsavel_id'] as int;
        if (bloqueados.contains(resp)) continue;
        final atual = lideresDiretos[colabId];
        if (atual == null ||
            rank < atual.rank ||
            (rank == atual.rank && resp < atual.responsavel)) {
          lideresDiretos[colabId] = (rank: rank, responsavel: resp);
        }
      } else if (h['responsavel_id'] == responsavelId) {
        meus.add(h['colaborador_id'] as int);
      }
    }
    if (apenasLiderDireto) {
      lideresDiretos.forEach((colabId, l) {
        if (l.responsavel == responsavelId) meus.add(colabId);
      });
    }
    return (setoresComHierarquia: setoresComHierarquia, meus: meus);
  }

  Future<Set<int>> _colaboradoresComFuncionalidadeBloqueada(
      String funcionalidade) async {
    final res = await _client
        .from('gestor_permissoes')
        .select('colaborador_id')
        .eq('funcionalidade', funcionalidade);
    return {for (final r in (res as List)) (r['colaborador_id'] as num).toInt()};
  }

  /// IDs da equipe sob [responsavelId] nesses setores, no modelo de líder
  /// direto. `null` = sem filtro.
  Future<Set<int>?> _idsEquipeDoResponsavel(
      List<String> setores, int? responsavelId, String funcionalidade) async {
    if (responsavelId == null) return null;
    final equipe = await buscarEquipeGestorMultiSetor(setores,
        responsavelId: responsavelId,
        apenasLiderDireto: true,
        funcionalidade: funcionalidade);
    return equipe.map((c) => c['id'] as int).toSet();
  }

  /// Coordenador, gestor ou gerente geral (em qualquer setor) enxergam toda a
  /// equipe abaixo deles em "Minha Equipe"; supervisor/encarregado/líder só a
  /// equipe direta. Quem não está na hierarquia (legado) segue vendo tudo.
  Future<bool> veTodaEquipeAbaixo(int colaboradorId) async {
    final res = await _client
        .from('setor_hierarquia')
        .select('nivel')
        .eq('colaborador_id', colaboradorId);
    final niveis = {for (final r in (res as List)) r['nivel'] as String};
    if (niveis.isEmpty) return true;
    return niveis
        .any((n) => const ['coordenador', 'gestor', 'gerente_geral'].contains(n));
  }

  // ─── Requisitantes de Vaga (Gestão de Equipe) ──────────────────────────────

  Future<List<Map<String, dynamic>>> listarRequisitantesVaga({
    String? setor,
    String? funcao,
    int? colaboradorId,
  }) async {
    var q = _client
        .from('vaga_requisitantes')
        .select('id, colaborador_id, setor, funcao, empresa, criado_em, colaboradores(nome, matricula, cargo)');
    if (setor != null) q = q.eq('setor', setor);
    if (funcao != null) q = q.eq('funcao', funcao);
    if (colaboradorId != null) q = q.eq('colaborador_id', colaboradorId);
    final data = await q.order('criado_em');
    return List<Map<String, dynamic>>.from(data as List).map((r) {
      final colab = r['colaboradores'] as Map<String, dynamic>?;
      return {
        ...r,
        'colaborador_nome': colab?['nome'],
        'colaborador_matricula': colab?['matricula'],
        'colaborador_cargo': colab?['cargo'],
      };
    }).toList();
  }

  Future<void> removerRequisitanteVaga(int id) async {
    await _client.from('vaga_requisitantes').delete().eq('id', id);
  }

  /// Insere vários requisitantes de uma vez (colaborador associado a N
  /// setores × M funções de uma tacada só, via seletor de múltipla escolha).
  Future<void> adicionarRequisitantesVagaEmLote(
      List<({int colaboradorId, String setor, String funcao, int? atribuidoPorId})> linhas) async {
    if (linhas.isEmpty) return;
    await _client.from('vaga_requisitantes').insert([
      for (final l in linhas)
        {
          'colaborador_id': l.colaboradorId,
          'setor': l.setor,
          'funcao': l.funcao,
          if (l.atribuidoPorId != null) 'atribuido_por_id': l.atribuidoPorId,
        },
    ]);
  }

  /// Funções (templates de vaga ativos) cadastradas pra um setor — usadas
  /// pra popular o seletor de função ao associar um requisitante.
  Future<List<String>> listarFuncoesTemplateDoSetor(String setor) async {
    final data = await _client
        .from('ats_templates')
        .select('titulo')
        .eq('departamento', setor)
        .eq('ativo', true);
    final titulos = <String>{};
    for (final t in data as List) {
      final titulo = (t as Map)['titulo'] as String?;
      if (titulo != null && titulo.isNotEmpty) titulos.add(titulo);
    }
    final lista = titulos.toList()..sort();
    return lista;
  }

  /// Busca colaboradores por nome, pra escolher quem vira requisitante.
  Future<List<Map<String, dynamic>>> buscarColaboradoresFeed(
      String query) async {
    if (query.isEmpty) return [];
    final res = await _client
        .from('colaboradores')
        .select('id, nome, setor, cargo')
        .ilike('nome', '%$query%')
        .limit(8);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Todas as atribuições de um setor (gestor/coordenador/supervisor/líder),
  /// com o colaborador responsável embutido — usado para o gestor escolher a
  /// liderança de uma vaga nova (aumento de quadro). Mesmo formato de
  /// `ApiService.listarHierarquiaDoSetor` no gentepole_admin.
  Future<List<Map<String, dynamic>>> listarHierarquiaDoSetor(String setor) async {
    final res = await _client
        .from('setor_hierarquia')
        .select('id, setor, empresa, nivel, turno, colaborador_id, colaboradores_alvo, '
            'colaboradores(id, nome, matricula, cargo)')
        .eq('setor', setor);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Funcionalidades do módulo Gestão de Equipe — mesmos 10 itens e ids do painel web
  /// (`ApiService.funcionalidadesGestor` em gentepole_admin), pra bloqueio
  /// individual por pessoa (`gestor_permissoes`) valer igual nos dois apps.
  static const funcionalidadesGestor = [
    {'id': 'minha_equipe_gestor', 'label': 'Minha Equipe'},
    {'id': 'vagas_gestor', 'label': 'Vagas'},
    {'id': 'avaliar_equipe_gestor', 'label': 'Avaliar Equipe'},
    {'id': 'avaliar_periodo_experiencia_gestor', 'label': 'Período de Experiência'},
    {'id': 'pdi_gestor', 'label': 'PDI'},
    {'id': 'feedback_gestor', 'label': 'Feedback'},
    {'id': 'exames_gestor', 'label': 'Exames'},
    {'id': 'solicitacoes_gestor', 'label': 'Solicitações'},
    {'id': 'facilites_gestor', 'label': 'Facilites'},
    {'id': 'candidaturas_gestor', 'label': 'Candidaturas'},
  ];

  /// Funcionalidades do módulo Gestão de Equipe bloqueadas pro colaborador logado —
  /// sem nenhum registro em `gestor_permissoes`, tudo fica liberado (mesmo
  /// comportamento do painel web).
  Future<Set<String>> listarFuncionalidadesGestorBloqueadas() async {
    final colab = colaboradorAtual;
    if (colab == null) return {};
    final data = await _client
        .from('gestor_permissoes')
        .select('funcionalidade')
        .eq('colaborador_id', colab.id);
    return {for (final r in (data as List)) r['funcionalidade'] as String};
  }

  Future<String?> uploadDocAprovacaoDiretoria({
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final path =
          'aprovacoes_diretoria/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      await _client.storage
          .from('documentos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: _mimeType(fileName),
              upsert: true,
            ),
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

  /// Retorna o id da vaga criada, ou null se falhar.
  Future<int?> solicitarVaga(VagaModel vaga) async {
    try {
      final res = await _client
          .from('vagas')
          .insert(vaga.toInsertMap())
          .select('id')
          .single();
      return res['id'] as int;
    } catch (_) {
      return null;
    }
  }

  /// Passo 3 do "Solicitar Vaga": registra o chamado de TI vinculado, se o
  /// gestor marcou que a vaga precisa de algum provisionamento.
  Future<void> criarChamadoTIVaga({
    required int vagaId,
    required bool precisaUsuarioRede,
    int? acessoIgualColaboradorId,
    required bool precisaOffice365,
    required bool precisaMaquina,
    String? observacao,
  }) async {
    await _client.from('ti_chamados_vaga').insert({
      'vaga_id': vagaId,
      'precisa_usuario_rede': precisaUsuarioRede,
      if (acessoIgualColaboradorId != null)
        'acesso_igual_colaborador_id': acessoIgualColaboradorId,
      'precisa_office365': precisaOffice365,
      'precisa_maquina': precisaMaquina,
      if (observacao != null && observacao.isNotEmpty) 'observacao': observacao,
    });
  }

  /// Lista as requisições do gestor logado (por supervisorId ou pelo id direto)
  ///
  /// Também traz as vagas de setores onde o colaborador lidera (abertas por
  /// outra pessoa, ex: um requisitante) e as que batem com os pares (setor +
  /// função) em que ele é requisitante. As abertas por outra pessoa vêm com
  /// `requisitanteNome`.
  Future<List<VagaModel>> listarMinhasRequisicoes(int gestorId) async {
    final porId = <int, Map<String, dynamic>>{};
    void juntar(dynamic data) {
      for (final v in List<Map<String, dynamic>>.from(data as List)) {
        porId[v['id'] as int] = v;
      }
    }

    juntar(await _client
        .from('vagas')
        .select()
        .eq('requisitado_por_id', gestorId));

    if (await colaboradorEhLiderAutorizado()) {
      final setores = await buscarSetoresEfetivosDoGestor();
      if (setores.isNotEmpty) {
        juntar(await _client
            .from('vagas')
            .select()
            .inFilter('departamento', setores));
      }
    }

    final pares = (await listarParesRequisitante())
        .where((p) => p.setor.isNotEmpty && p.funcao.isNotEmpty)
        .toList();
    if (pares.isNotEmpty) {
      // Templates cujo (setor, função efetiva) bate com algum par; as vagas
      // desses templates é que o requisitante enxerga.
      final templates = await _client
          .from('ats_templates')
          .select('id, titulo, funcao, departamento')
          .inFilter('departamento', pares.map((p) => p.setor).toSet().toList());
      final idsTemplates = <int>[
        for (final t in List<Map<String, dynamic>>.from(templates as List))
          if (pares.any((p) =>
              p.setor == t['departamento'] &&
              normalizarFuncao(p.funcao) ==
                  normalizarFuncao(funcaoEfetivaDoTemplate(t))))
            t['id'] as int,
      ];
      if (idsTemplates.isNotEmpty) {
        final data = await _client
            .from('vagas')
            .select()
            .inFilter('template_id', idsTemplates);
        for (final v in List<Map<String, dynamic>>.from(data as List)) {
          porId[v['id'] as int] = v;
        }
      }
    }

    final lista = porId.values.toList()
      ..sort((a, b) => (b['created_at'] as String? ?? '')
          .compareTo(a['created_at'] as String? ?? ''));

    // Nome de quem abriu, quando não fui eu.
    final outros = lista
        .map((v) => (v['requisitado_por_id'] as num?)?.toInt())
        .whereType<int>()
        .where((id) => id != gestorId)
        .toSet()
        .toList();
    if (outros.isNotEmpty) {
      final nomes = await _client
          .from('colaboradores')
          .select('id, nome')
          .inFilter('id', outros);
      final mapa = {
        for (final n in (nomes as List)) n['id'] as int: n['nome'] as String?,
      };
      for (final v in lista) {
        final id = (v['requisitado_por_id'] as num?)?.toInt();
        if (id != null && id != gestorId && mapa[id] != null) {
          v['requisitante_nome'] = mapa[id];
        }
      }
    }

    return lista.map((e) => VagaModel.fromJson(e)).toList();
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
      await _client
          .from('vagas')
          .update({'status': 'ENCERRADA'})
          .eq('id', vagaId);
    }
  }

  // ─── Candidaturas — visão do gestor ──────────────────────────────────────────

  /// Candidatos de uma vaga, do início da triagem até a admissão concluída
  /// — inclui quem já terminou o processo (não filtra por admissaoStatus),
  /// pra o board do gestor continuar mostrando o restante do fluxo mesmo
  /// depois da vaga ficar preenchida/encerrada, igual ao painel web.
  Future<List<CandidaturaGestorModel>> listarCandidatosGestor(
    int vagaId,
  ) async {
    final data = await _client
        .from('candidaturas')
        .select('*, candidatos(*), admissoes(id, status)')
        .eq('vaga_id', vagaId)
        .inFilter('status', [
          'INSCRITO',
          'TRIAGEM',
          'AVALIACAO_COMP',
          'ENTREV_RH',
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
    return (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
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
  /// filial. Sem regra global — retorna false se nem a filial tiver
  /// configuração (ver [filialTemMassoterapiaConfigurada]).
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
      final achado = linhas.where(
        (l) => l['escopo'] == escopo && l['chave'] == chave,
      );
      return achado.isEmpty ? null : achado.first['ativo'] as bool;
    }

    return buscar('setor', setor) ??
        buscar('segmento', segmento) ??
        buscar('filial', filial) ??
        false;
  }

  /// Massoterapia não tem mais regra global — só existe pra colaborador de
  /// filial que a RH configurou explicitamente. Usado pra esconder o
  /// módulo por completo de quem está numa filial sem nenhuma config
  /// (nenhum dia cadastrado pra essa filial, direto ou por segmento/setor
  /// dela).
  Future<bool> filialTemMassoterapiaConfigurada(String? filial) async {
    if (filial == null || filial.isEmpty) return false;
    final res = await _client
        .from('massoterapia_dias_config')
        .select('id')
        .eq('escopo', 'filial')
        .eq('chave', filial)
        .limit(1);
    return (res as List).isNotEmpty;
  }

  /// Nutrição não tem regra global — só existe pra colaborador de filial
  /// com pelo menos uma data cadastrada.
  Future<bool> filialTemNutricaoConfigurada(String? filial) async {
    if (filial == null || filial.isEmpty) return false;
    final res = await _client
        .from('nutricionista_config_dias')
        .select('id')
        .eq('filial', filial)
        .limit(1);
    return (res as List).isNotEmpty;
  }

  /// Status do ciclo atual: quantas sessões do ciclo já usou, limite do ciclo,
  /// custo da extra, saldo de PoleCoins e se a PRÓXIMA sessão sairia paga —
  /// pra mostrar o contador e confirmar cobrança antes de agendar.
  Future<Map<String, dynamic>> buscarStatusCicloMassoterapia() async {
    final colaborador = colaboradorAtual;
    if (colaborador == null) {
      return {
        'usadas': 0,
        'limite': 0,
        'custo_polecoins_extra': 0,
        'saldo_polecoins': 0,
        'proxima_paga': false,
        'bloqueado': false,
      };
    }
    final res = await _client.rpc(
      'status_ciclo_massoterapia',
      params: {'p_colaborador_id': colaborador.id},
    );
    final status = Map<String, dynamic>.from(res as Map);
    // RPC nova devolve `polecoins_ativo`; versão antiga não — usa o
    // interruptor geral da gamificação como fallback.
    if (status['polecoins_ativo'] is! bool) {
      try {
        status['polecoins_ativo'] = await gamificacaoAtiva();
      } catch (_) {
        status['polecoins_ativo'] = true;
      }
    }
    return status;
  }

  /// Config geral de massoterapia (janela de dias, limite de sessões por ciclo e
  /// custo em PoleCoins da sessão extra) — linha única configurada pelo admin.
  Future<Map<String, dynamic>> buscarConfigGeralMassoterapia() async {
    final data = await _client
        .from('massoterapia_config_geral')
        .select()
        .eq('id', 1)
        .single();
    return Map<String, dynamic>.from(data);
  }

  /// Resolve o período de calendário do ciclo vigente conforme [janelaDias]:
  /// 7 = semana (segunda a domingo), 14 = quinzena (1-15 ou 16-fim do mês),
  /// 30 (ou qualquer outro valor) = mês calendário inteiro. Espelha
  /// `_periodo_ciclo_massoterapia` no banco — não é janela rolante, é sempre
  /// o mesmo bloco fixo do calendário.
  ({DateTime inicio, DateTime fim}) _periodoCicloMassoterapia(
    DateTime hoje,
    int janelaDias,
  ) {
    if (janelaDias == 7) {
      final inicio = hoje.subtract(Duration(days: hoje.weekday - 1));
      return (inicio: inicio, fim: inicio.add(const Duration(days: 6)));
    }
    if (janelaDias == 14) {
      if (hoje.day <= 15) {
        return (
          inicio: DateTime(hoje.year, hoje.month, 1),
          fim: DateTime(hoje.year, hoje.month, 15),
        );
      }
      return (
        inicio: DateTime(hoje.year, hoje.month, 16),
        fim: DateTime(hoje.year, hoje.month + 1, 0),
      );
    }
    return (
      inicio: DateTime(hoje.year, hoje.month, 1),
      fim: DateTime(hoje.year, hoje.month + 1, 0),
    );
  }

  /// Retorna todos os dias do ciclo vigente (período de calendário completo
  /// — semana/quinzena/mês, conforme configurado), incluindo dias passados
  /// (pra ver onde a vaga já foi usada) e futuros (pra agendar).
  ///
  /// Uma única query pras regras relevantes, em vez de uma consulta por
  /// dia do período (até 30+ round-trips sequenciais pra uma janela de
  /// mês, antes desta correção — era o motivo da tela demorar pra abrir).
  Future<List<String>> buscarDiasDisponiveisMassoterapia() async {
    final colaborador = colaboradorAtual;
    final setor = colaborador?.setor;
    final segmento = colaborador?.codSegmento;
    final filial = colaborador?.filialEfetiva;
    final agora = _brasilia();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final config = await buscarConfigGeralMassoterapia();
    final janelaDias = config['janela_dias'] as int? ?? 14;
    final periodo = _periodoCicloMassoterapia(hoje, janelaDias);

    // Setor em grupo universal: os dias vêm do grupo (RPC), não de
    // filial/segmento/setor. Setor sem grupo não tem dias de massoterapia.
    List<int>? diasDoGrupo;
    if (setor != null && setor.isNotEmpty) {
      final r = await _client
          .rpc('massoterapia_dias_do_setor', params: {'p_setor': setor});
      diasDoGrupo = r == null
          ? <int>[]
          : (r as List).map((e) => (e as num).toInt()).toList();
    }

    final chaves = [setor, segmento, filial].whereType<String>().toList();
    final regras = chaves.isEmpty || diasDoGrupo != null
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(await _client
            .from('massoterapia_dias_config')
            .select('escopo, chave, dia_semana, ativo')
            .inFilter('chave', chaves));

    bool? buscar(String escopo, String? chave, int diaSemana) {
      if (chave == null) return null;
      final achado = regras.where((l) =>
          l['escopo'] == escopo &&
          l['chave'] == chave &&
          l['dia_semana'] == diaSemana);
      return achado.isEmpty ? null : achado.first['ativo'] as bool;
    }

    bool ativoNoDia(int diaSemana) =>
        (diasDoGrupo != null ? diasDoGrupo.contains(diaSemana) : null) ??
        buscar('setor', setor, diaSemana) ??
        buscar('segmento', segmento, diaSemana) ??
        buscar('filial', filial, diaSemana) ??
        false;

    final dias = <String>[];
    for (var d = periodo.inicio;
        !d.isAfter(periodo.fim);
        d = d.add(const Duration(days: 1))) {
      if (ativoNoDia(d.weekday)) {
        final str =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        dias.add(str);
      }
    }
    return dias;
  }

  /// Últimas faltas (não veio) do colaborador logado, com a situação da
  /// justificativa (view v_massoterapia_faltas).
  Future<List<Map<String, dynamic>>> listarMinhasFaltasMassoterapia() async {
    final id = colaboradorAtual?.id;
    if (id == null) return [];
    try {
      final res = await _client
          .from('v_massoterapia_faltas')
          .select('id, data, horario, falta_justificada, justificativa')
          .eq('colaborador_id', id)
          .order('data', ascending: false)
          .limit(5);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
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
  /// Sem regra global — sem [filial] (ou sem regra própria dessa filial)
  /// retorna null, tratado como "sem limite" pelo restante do fluxo.
  Future<MassoterapiaConfigSetorModel?> buscarConfigSetorMassoterapia(
    String setor, {
    String? filial,
  }) async {
    if (filial == null || filial.isEmpty) return null;
    final data = await _client
        .from('massoterapia_config_setor')
        .select()
        .eq('setor', setor)
        .eq('filial', filial)
        .eq('ativo', true)
        .maybeSingle();
    if (data == null) return null;
    return MassoterapiaConfigSetorModel.fromJson(data);
  }

  /// Cria um agendamento para o colaborador logado, respeitando o limite
  /// do ciclo — se estourado, debita PoleCoins (ou recusa por saldo
  /// insuficiente). Toda a regra roda atômica na RPC `agendar_massoterapia_com_limite`.
  /// Retorna `ok=false` se o slot já estiver ocupado, o setor estiver lotado,
  /// ou o saldo de PoleCoins for insuficiente (`motivo == 'saldo_insuficiente'`).
  /// `motivo` também pode ser 'bloqueado' (com [bloqueioFim], 'yyyy-MM-dd') ou
  /// 'grupo_lotado' (vagas do grupo do dia esgotadas).
  Future<({bool ok, bool pagoComPolecoins, String? motivo, String? bloqueioFim})>
      agendarMassoterapia({
    required String data,
    required String horario,
  }) async {
    final colaborador = colaboradorAtual;
    if (colaborador == null) {
      return (
        ok: false,
        pagoComPolecoins: false,
        motivo: null,
        bloqueioFim: null
      );
    }
    try {
      final res = await _client.rpc(
        'agendar_massoterapia_com_limite',
        params: {
          'p_colaborador_id': colaborador.id,
          'p_data': data,
          'p_horario': horario,
        },
      );
      final map = Map<String, dynamic>.from(res as Map);
      return (
        ok: map['ok'] as bool? ?? false,
        pagoComPolecoins: map['pago_com_polecoins'] as bool? ?? false,
        motivo: map['motivo'] as String?,
        bloqueioFim: map['bloqueio_fim']?.toString(),
      );
    } catch (_) {
      return (
        ok: false,
        pagoComPolecoins: false,
        motivo: null,
        bloqueioFim: null
      );
    }
  }

  /// Vagas do grupo de setores do colaborador numa [data] (RPC
  /// `massoterapia_vagas_grupo`). `modo == 'setor'` = regra antiga (vagas por
  /// setor); `modo == 'grupo'` traz `grupo`, `vagas_grupo`, `usadas`, `restantes`.
  /// Em caso de erro devolve `{'modo': 'setor'}` (mantém o fluxo antigo).
  Future<Map<String, dynamic>> buscarVagasGrupoMassoterapia(String data) async {
    final colaborador = colaboradorAtual;
    if (colaborador == null) return {'modo': 'setor'};
    try {
      final res = await _client.rpc(
        'massoterapia_vagas_grupo',
        params: {'p_colab': colaborador.id, 'p_data': data},
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (_) {
      return {'modo': 'setor'};
    }
  }

  /// Cancela (soft delete, marca CANCELADO) e estorna os PoleCoins
  /// automaticamente se a sessão tinha sido paga (RPC `cancelar_massoterapia_com_estorno`).
  Future<bool> cancelarMassoterapia(int agendamentoId) async {
    try {
      final ok = await _client.rpc(
        'cancelar_massoterapia_com_estorno',
        params: {
          'p_agendamento_id': agendamentoId,
          'p_colaborador_id': colaboradorAtual!.id,
        },
      );
      return ok as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Retorna true se o colaborador logado tem o perfil "gestor" — tanto pelo
  /// jeito antigo (colaboradores.eh_gestor, mantido em sincronia com
  /// usuarios_admin.roles) quanto por estar atribuído em algum nível com
  /// acesso ao módulo (`_niveisComAcessoDeGestor`) de algum setor na
  /// Administração de Setor do painel web (`setor_hierarquia`). Os dois
  /// coexistem, igual no painel.
  Future<bool> verificarSeEhGestor() async {
    if (colaboradorAtual?.ehGestor ?? false) return true;
    final colab = colaboradorAtual;
    if (colab == null) return false;
    final data = await _client
        .from('setor_hierarquia')
        .select('id')
        .eq('colaborador_id', colab.id)
        .inFilter('nivel', _niveisComAcessoDeGestor)
        .limit(1);
    if ((data as List).isNotEmpty) return true;
    // Igual ao web: perfil 'gestor' ou 'admin' em usuarios_admin (ativo).
    try {
      final adm = await _client
          .from('usuarios_admin')
          .select('roles')
          .eq('matricula', colab.matricula)
          .eq('empresa', colab.empresa ?? '')
          .eq('ativo', true)
          .maybeSingle();
      final roles = (adm?['roles']?.toString() ?? '').toLowerCase();
      return roles.contains('gestor') || roles.contains('admin');
    } catch (_) {
      return false;
    }
  }

  /// Verdadeiro quando este colaborador está associado como requisitante de
  /// vaga (`vaga_requisitantes`), mesmo sem ser gestor/líder de ninguém —
  /// dá acesso só à tela de Vagas dentro de "Gestão de Equipe" (ver
  /// [GestorScreen.apenasVagas]), nunca às demais (Minha Equipe, Avaliar
  /// Equipe, Feedback, Exames, Solicitações, Requisitantes) — mesma regra
  /// do painel web (`_ehRequisitanteDeVaga`, que só libera a área de
  /// "Vagas", não o papel de gestor inteiro).
  Future<bool> verificarSeEhRequisitanteDeVaga() async {
    final colab = colaboradorAtual;
    if (colab == null) return false;
    final data = await _client
        .from('vaga_requisitantes')
        .select('id')
        .eq('colaborador_id', colab.id)
        .limit(1);
    return (data as List).isNotEmpty;
  }

  /// Verdadeiro só quando este colaborador aparece como responsável de
  /// alguém em `colaborador_hierarquia` — usado pra só mostrar "Gestão de
  /// Equipe" pra quem lidera de fato, além do check de nível em
  /// [verificarSeEhGestor] (que sozinho pode dar acesso a quem tem o
  /// cadastro `eh_gestor`/nível de gestão mas não lidera ninguém hoje).
  Future<bool> colaboradorEhLiderAutorizado() async {
    final colab = colaboradorAtual;
    if (colab == null) return false;
    final data = await _client
        .from('colaborador_hierarquia')
        .select('colaborador_id')
        .eq('responsavel_id', colab.id)
        .limit(1);
    return (data as List).isNotEmpty;
  }

  /// Busca a equipe do gestor logado — respeitando a Administração de Setor
  /// (supervisor com liderados específicos só vê essas pessoas).
  // ─── Celebrações coletivas (tempo de empresa e novos polevalentes) ───────

  static String _isoData(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Data de hoje no formato do banco (yyyy-MM-dd).
  static String dataHojeIso() => _isoData(DateTime.now());

  /// Quem já celebrou [colaboradorId] neste evento, do mais antigo ao mais novo.
  Future<List<Map<String, dynamic>>> listarCelebracoes({
    required String tipo,
    required int colaboradorId,
    required String dataEvento,
  }) async {
    final res = await _client
        .from('celebracoes')
        .select('id, autor_id, mensagem, criado_em, '
            'autor:colaboradores!autor_id(nome, foto_url, setor)')
        .eq('tipo', tipo)
        .eq('colaborador_id', colaboradorId)
        .eq('data_evento', dataEvento)
        .order('criado_em', ascending: true);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Registra a celebração do colaborador logado. Retorna false se ele já
  /// celebrou esse evento (chave única) ou em caso de erro.
  Future<bool> celebrar({
    required String tipo,
    required int colaboradorId,
    required String dataEvento,
    required String mensagem,
  }) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return false;
    try {
      await _client.from('celebracoes').insert({
        'tipo': tipo,
        'colaborador_id': colaboradorId,
        'autor_id': meuId,
        'data_evento': dataEvento,
        'mensagem': mensagem.trim(),
      });
      PontosBus.notificarGanho();
      return true;
    } catch (e, st) {
      ErrorReporter.report(e, st, contexto: 'Celebrar colaborador');
      return false;
    }
  }

  /// Celebrações que o colaborador logado recebeu e que ainda valem: tempo de
  /// empresa só no dia; novo polevalente na semana da chegada. Agrupadas por
  /// evento — cada item: `{tipo, data_evento, celebracoes: [...]}`.
  Future<List<Map<String, dynamic>>> listarCelebracoesRecebidas() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return [];
    final hoje = DateTime.now();
    final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);
    final inicioSemana =
        hojeSemHora.subtract(Duration(days: hoje.weekday - 1));
    final res = await _client
        .from('celebracoes')
        .select('tipo, data_evento, mensagem, criado_em, '
            'autor:colaboradores!autor_id(nome, foto_url)')
        .eq('colaborador_id', meuId)
        .gte('data_evento', _isoData(inicioSemana))
        .lte('data_evento', _isoData(hojeSemHora))
        .order('criado_em', ascending: true);
    final grupos = <String, Map<String, dynamic>>{};
    for (final c in res as List) {
      final tipo = c['tipo'] as String;
      final data = c['data_evento'] as String;
      if (tipo == 'tempo_empresa' && data != _isoData(hojeSemHora)) continue;
      final g = grupos.putIfAbsent(
        '$tipo|$data',
        () => {
          'tipo': tipo,
          'data_evento': data,
          'celebracoes': <Map<String, dynamic>>[],
        },
      );
      (g['celebracoes'] as List).add(Map<String, dynamic>.from(c as Map));
    }
    return grupos.values.toList();
  }

  /// Ids de colaboradores já indicados como "substituído" em vagas
  /// aguardando aprovação do RH ou aprovadas. Por padrão só vagas ainda em
  /// aberto; com [incluirEncerradas] também as já preenchidas (vale para os
  /// demitidos: quem já foi substituído uma vez não volta ao picker).
  Future<Set<int>> listarColaboradoresJaIndicadosComoSubstituto({
    bool incluirEncerradas = false,
  }) async {
    final res = await _client
        .from('vagas')
        .select(
            'colaborador_substituido_id, colaboradores_substituidos_ids, status, status_requisicao')
        .inFilter('status_requisicao', ['AGUARDANDO_APROVACAO_RH', 'APROVADA']);
    final ids = <int>{};
    for (final r in res as List) {
      final aindaEmAberto =
          r['status_requisicao'] == 'AGUARDANDO_APROVACAO_RH' ||
              r['status'] != 'ENCERRADA';
      if (!aindaEmAberto && !incluirEncerradas) continue;
      final unico = (r['colaborador_substituido_id'] as num?)?.toInt();
      if (unico != null) ids.add(unico);
      final lista = r['colaboradores_substituidos_ids'] as List?;
      if (lista != null) {
        ids.addAll(lista.map((v) => (v as num).toInt()));
      }
    }
    return ids;
  }

  /// [incluirDemitidos] só para o picker de "colaborador a substituir" na
  /// abertura de vaga (ver [buscarEquipeGestorMultiSetor]).
  ///
  /// [incluirSetoresDeRequisitante]: soma a equipe dos setores em que o
  /// colaborador é requisitante de vaga (sem exigir que ele lidere ali) —
  /// só para o picker de substituição da abertura de vaga.
  Future<List<ColaboradorModel>> buscarMinhaEquipe({
    bool incluirDemitidos = false,
    bool incluirSetoresDeRequisitante = false,
    bool apenasLiderDireto = false,
    String? funcionalidade,
  }) async {
    final setores = await buscarSetoresEfetivosDoGestor();
    final equipe = <int, Map<String, dynamic>>{};
    if (setores.isNotEmpty) {
      final res = await buscarEquipeGestorMultiSetor(
        setores,
        responsavelId: colaboradorAtual?.id,
        incluirDemitidos: incluirDemitidos,
        apenasLiderDireto: apenasLiderDireto,
        funcionalidade: funcionalidade,
      );
      for (final c in res) {
        equipe[c['id'] as int] = c;
      }
    }
    if (incluirSetoresDeRequisitante) {
      final pares = await listarParesRequisitante();
      // Mesmo que o setor do par também seja um setor "do líder" (ex: o próprio
      // setor do colaborador), a equipe inteira dele entra: a lista do líder
      // é restrita à hierarquia e ficaria vazia pra quem não lidera ninguém ali.
      final setoresPar = pares.map((p) => p.setor).toSet().toList();
      if (setoresPar.isNotEmpty) {
        final res = await buscarEquipeGestorMultiSetor(
          setoresPar,
          incluirDemitidos: incluirDemitidos,
        );
        // Quem veio só pelo par de requisitante é marcado: na substituição só
        // aparece se o cargo bater com a função do template escolhido.
        for (final c in res) {
          final id = c['id'] as int;
          equipe.putIfAbsent(id, () => {...c, '_origem_requisitante': true});
        }
      }
    }
    final lista = equipe.values.toList()
      ..sort((a, b) =>
          (a['nome'] as String? ?? '').compareTo(b['nome'] as String? ?? ''));
    return lista.map((e) => ColaboradorModel.fromJson(e)).toList();
  }

  /// Centros de custo (cod_centro distintos) da equipe que o usuário lidera ou
  /// responde (inclui setores em que é requisitante de vaga) + o do próprio
  /// usuário — alimenta o dropdown de "Solicitar vaga". Cada item:
  /// {'cod': cod_centro, 'setor': setor}. Vazio se nada for encontrado.
  Future<List<Map<String, String>>> listarCentrosCustoParaVaga() async {
    final porCodigo = <String, String>{};
    void add(String? cod, String? setor) {
      final c = cod?.trim() ?? '';
      if (c.isEmpty) return;
      porCodigo.putIfAbsent(c, () => setor?.trim() ?? '');
    }

    final eu = colaboradorAtual;
    if (eu == null) return [];

    // Mesma consulta do web (listarCentrosCustoDoLider): subordinados da
    // hierarquia + colaboradores dos setores de gestor_setores + setores dos
    // pares de requisitante; sem nada disso, lista vazia (campo livre).
    try {
      final hier = await _client
          .from('colaborador_hierarquia')
          .select('colaborador_id')
          .eq('responsavel_id', eu.id);
      final subordinados = <int>{
        for (final h in (hier as List))
          if (h['colaborador_id'] is int) h['colaborador_id'] as int,
      };
      if (subordinados.isNotEmpty) {
        final cols = await _client
            .from('colaboradores')
            .select('cod_centro, setor')
            .eq('demitido', false)
            .inFilter('id', subordinados.toList());
        for (final c in (cols as List)) {
          add(c['cod_centro']?.toString(), c['setor']?.toString());
        }
      }
    } catch (_) {}
    try {
      final extras = await _client
          .from('gestor_setores')
          .select('setor')
          .eq('matricula_gestor', eu.matricula);
      final setores = (extras as List)
          .map((e) => e['setor']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      if (setores.isNotEmpty) {
        final cols = await _client
            .from('colaboradores')
            .select('cod_centro, setor')
            .eq('demitido', false)
            .inFilter('setor', setores);
        for (final c in (cols as List)) {
          add(c['cod_centro']?.toString(), c['setor']?.toString());
        }
      }
    } catch (_) {}
    try {
      final pares = await listarParesRequisitante();
      final setoresPar = pares.map((p) => p.setor).toSet().toList();
      if (setoresPar.isNotEmpty) {
        final cols = await _client
            .from('colaboradores')
            .select('cod_centro, setor')
            .eq('demitido', false)
            .inFilter('setor', setoresPar);
        for (final c in (cols as List)) {
          add(c['cod_centro']?.toString(), c['setor']?.toString());
        }
      }
    } catch (_) {}
    if (porCodigo.isEmpty) return []; // sem equipe → campo de texto livre
    add(eu.codCentro, eu.setor);
    final lista = porCodigo.entries
        .map((e) => {'cod': e.key, 'setor': e.value})
        .toList()
      ..sort((a, b) => a['cod']!.compareTo(b['cod']!));
    return lista;
  }

  /// "Minha Equipe": coordenador pra cima vê toda a equipe abaixo; supervisor,
  /// encarregado e líder só a equipe direta.
  Future<List<ColaboradorModel>> buscarMinhaEquipeVisao() async {
    final id = colaboradorAtual?.id;
    final veTudo = id == null ? true : await veTodaEquipeAbaixo(id);
    return buscarMinhaEquipe(
      apenasLiderDireto: !veTudo,
      funcionalidade: 'minha_equipe_gestor',
    );
  }

  /// Hierarquia já resolvida de UM colaborador (nível + nome do responsável)
  /// — usada em "Dados do colaborador" na Minha Equipe.
  Future<List<Map<String, dynamic>>> buscarHierarquiaResolvidaDoColaborador(
      int colaboradorId) async {
    final res = await _client
        .from('colaborador_hierarquia')
        .select(
            'nivel, responsavel_id, colaboradores!colaborador_hierarquia_responsavel_id_fkey(nome)')
        .eq('colaborador_id', colaboradorId);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Campos cadastrais extras (e-mail, horário de trabalho) de um
  /// colaborador da equipe, que não vêm no [ColaboradorModel].
  Future<Map<String, dynamic>?> buscarDadosExtrasColaborador(
      int colaboradorId) async {
    final res = await _client
        .from('colaboradores')
        .select('email, horario_trabalho')
        .eq('id', colaboradorId)
        .maybeSingle();
    return res == null ? null : Map<String, dynamic>.from(res);
  }

  /// Exames agendados pelo SESMT pra equipe do gestor, ainda aguardando
  /// confirmação dele — só depois de confirmado o colaborador vê no feed.
  Future<List<Map<String, dynamic>>> listarExamesAguardandoConfirmacao() async {
    final setores = await buscarSetoresEfetivosDoGestor();
    if (setores.isEmpty) return [];
    final data = await _client
        .from('exames')
        .select('id, tipo, clinica, data_agendamento, observacoes, '
            'colaborador:colaborador_id(id, nome, setor, cargo)')
        .eq('status_confirmacao', 'AGUARDANDO_GESTOR')
        .order('data_agendamento');
    return List<Map<String, dynamic>>.from(data as List)
        .where((e) => setores.contains(
            (e['colaborador'] as Map<String, dynamic>?)?['setor']))
        .toList();
  }

  Future<void> confirmarExame(int exameId) async {
    await _client
        .from('exames')
        .update({'status_confirmacao': 'CONFIRMADO'}).eq('id', exameId);
  }

  /// Busca a mensagem institucional da empresa para o aniversariante.
  /// Retorna o registro ativo mais recente da tabela
  /// [mensagens_empresa_aniversario], ou null se não houver nenhum.
  ///
  /// [tipo] ('natalicio' | 'empresa') filtra pela coluna `tipo`; sem registro
  /// do tipo (ou coluna ainda ausente) cai pra qualquer mensagem ativa.
  Future<Map<String, dynamic>?> buscarMensagemEmpresaAniversario(
      {String? tipo}) async {
    if (tipo != null) {
      try {
        final porTipo = await _client
            .from('mensagens_empresa_aniversario')
            .select('titulo, corpo')
            .eq('ativo', true)
            .eq('tipo', tipo)
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (porTipo != null) return porTipo;
      } catch (_) {/* coluna tipo ausente: fallback abaixo */}
    }
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
    ]);

    final fotos = <String, String>{
      for (final f in (results[1] as List))
        (f['material'] as String): (f['foto_url'] as String),
    };

    // Produtos regulares (SAP) não são afetados pelas regras de
    // disponibilidade (dias da semana): essas regras valem só para os
    // exclusivos — igual ao web.
    return (results[0] as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final matSemZeros = (m['material'] as String).replaceAll(
        RegExp(r'^0+'),
        '',
      );
      m['foto_url'] = fotos[matSemZeros];
      m['dias_semana'] = null;
      m['limite_qtd'] = null;
      m['periodo_limite'] = null;
      return LojinhaProdutoModel.fromJson(m);
    }).toList();
  }

  /// A Lojinha só libera compra pra filiais explicitamente cobertas por uma
  /// regra do tipo 'geral' — sem isso, fica só consulta (ver histórico),
  /// sem catálogo pra comprar. [branch] é `ColaboradorModel.branch`. Regra
  /// 'geral' também respeita dia/horário, igual as de exclusivo.
  Future<bool> lojinhaLiberadaParaFilial(String? branch) async {
    if (branch == null || branch.isEmpty) return false;
    final data = await _client
        .from('lojinha_regras')
        .select('filiais, dias_semana, hora_inicio, hora_fim, horarios_dia')
        .eq('tipo', 'geral');
    final agora = DateTime.now();
    for (final r in data as List) {
      final filiais = (r['filiais'] as List?)?.cast<String>() ?? [];
      if (filiais.isNotEmpty && !filiais.contains(branch)) continue;
      if (_regraGeralDisponivelAgora(r as Map<String, dynamic>, agora)) return true;
    }
    return false;
  }

  bool _regraGeralDisponivelAgora(Map<String, dynamic> regra, DateTime agora) {
    final diasSemana = (regra['dias_semana'] as List?)?.cast<int>();
    final diaAtivo = diasSemana == null || diasSemana.isEmpty;
    if (!diaAtivo && !diasSemana!.contains(agora.weekday)) return false;

    final horaAgora =
        '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}:00';

    if (!diaAtivo) {
      final horariosDia = regra['horarios_dia'] as Map<String, dynamic>?;
      if (horariosDia == null) return true;
      final intervalo = horariosDia[agora.weekday.toString()] as Map?;
      if (intervalo == null) return true;
      final ini = intervalo['inicio'] as String?;
      final fim = intervalo['fim'] as String?;
      if (ini == null || fim == null) return true;
      return horaAgora.compareTo(ini) >= 0 && horaAgora.compareTo(fim) <= 0;
    }

    final horaInicio = regra['hora_inicio'] as String?;
    final horaFim = regra['hora_fim'] as String?;
    if (horaInicio == null || horaFim == null) return true;
    return horaAgora.compareTo(horaInicio) >= 0 && horaAgora.compareTo(horaFim) <= 0;
  }

  Future<Map<String, dynamic>> buscarConfigLojinha() async {
    final data = await _client
        .from('lojinha_config')
        .select(
            'limite_qtd, limite_qtd_exclusivo, periodo_dias, limite_pedidos_sap, limite_pedidos_exclusivo, periodo_dias_pedidos')
        .eq('id', 1)
        .maybeSingle();
    if (data == null) {
      return {
        'limite_qtd': null,
        'limite_qtd_exclusivo': null,
        'periodo_dias': null,
        'limite_pedidos_sap': null,
        'limite_pedidos_exclusivo': null,
        'periodo_dias_pedidos': null,
      };
    }
    return Map<String, dynamic>.from(data as Map);
  }

  /// Quantos PEDIDOS (não itens) o colaborador já fez nos últimos
  /// [periodoDias] dias, separado por tipo — usado pelo limite "1 pedido
  /// regular + 1 exclusivo por semana" configurado no gentepole_admin.
  Future<({int regular, int exclusivo})> buscarPedidosPorTipoRecentesColab(
      String colaboradorId, int periodoDias) async {
    final desde = DateTime.now().subtract(Duration(days: periodoDias - 1));
    final dataStr =
        '${desde.year}-${desde.month.toString().padLeft(2, '0')}-${desde.day.toString().padLeft(2, '0')}';
    final data = await _client
        .from('lojinha_compras')
        .select('teve_regular, teve_exclusivo')
        .eq('colaborador_id', colaboradorId)
        .gte('data', dataStr);
    final list = data as List;
    final regular = list.where((r) => r['teve_regular'] == true).length;
    final exclusivo = list.where((r) => r['teve_exclusivo'] == true).length;
    return (regular: regular, exclusivo: exclusivo);
  }

  Future<int> buscarComprasRecentesColab(
    String colaboradorId,
    int periodoDias,
  ) async {
    final desde = DateTime.now().subtract(Duration(days: periodoDias - 1));
    final dataStr =
        '${desde.year}-${desde.month.toString().padLeft(2, '0')}-${desde.day.toString().padLeft(2, '0')}';
    final data = await _client
        .from('lojinha_compras')
        .select('quantidade_total')
        .eq('colaborador_id', colaboradorId)
        .gte('data', dataStr);
    final list = data as List;
    return list.fold<int>(
      0,
      (s, r) => s + ((r['quantidade_total'] as int?) ?? 0),
    );
  }

  /// Quantos itens o colaborador comprou nos últimos [periodoDias] dias,
  /// separado por tipo: SAP (regulares) x exclusivo — usado pelos limites de
  /// itens `limite_qtd` (SAP) e `limite_qtd_exclusivo`.
  Future<({int sap, int exclusivo})> buscarComprasRecentesPorTipoColab(
    String colaboradorId,
    int periodoDias,
  ) async {
    final desde = DateTime.now().subtract(Duration(days: periodoDias - 1));
    final dataStr =
        '${desde.year}-${desde.month.toString().padLeft(2, '0')}-${desde.day.toString().padLeft(2, '0')}';
    final data = await _client
        .from('lojinha_compras')
        .select('quantidade_total, quantidade_exclusivo')
        .eq('colaborador_id', colaboradorId)
        .gte('data', dataStr);
    final list = data as List;
    var total = 0;
    var excl = 0;
    for (final r in list) {
      total += (r['quantidade_total'] as int?) ?? 0;
      excl += (r['quantidade_exclusivo'] as int?) ?? 0;
    }
    return (sap: total - excl, exclusivo: excl);
  }

  /// Regras de disponibilidade: em quais dias/horários/filiais cada produto
  /// EXCLUSIVO pode ser comprado (o catálogo regular, vindo do SAP, não é
  /// afetado por essas regras no web).
  Future<List<Map<String, dynamic>>> listarRegrasLojinha() async {
    final data = await _client
        .from('lojinha_regras')
        .select(
            'id, nome, tipo, dias_semana, materiais, filiais, hora_inicio, hora_fim, horarios_dia')
        .order('nome');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Mapa material → regra, usado ao montar o catálogo de exclusivos — só
  /// considera regras do tipo 'exclusivo'.
  Future<Map<String, Map<String, dynamic>>> regrasLojinhaPorMaterial() async {
    final regras = await listarRegrasLojinha();
    final mapa = <String, Map<String, dynamic>>{};
    for (final r in regras) {
      if ((r['tipo'] as String? ?? 'exclusivo') != 'exclusivo') continue;
      final materiais = (r['materiais'] as List?)?.cast<String>() ?? [];
      for (final mat in materiais) {
        mapa[mat] = r;
      }
    }
    return mapa;
  }

  /// Dados do funcionário no SAP: limites + histórico de pedidos
  /// (mesclado com compras de produtos exclusivos, que não passam pelo SAP)
  /// O limite disponível já desconta as compras exclusivas do ciclo (dia 21
  /// a dia 20), que o SAP não enxerga.
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

      // Desconto das compras exclusivas do ciclo atual (desde o dia 21) no
      // limite disponível — o SAP não enxerga essas compras.
      final hoje = DateTime.now();
      final inicioCiclo = hoje.day >= 21
          ? DateTime(hoje.year, hoje.month, 21)
          : DateTime(hoje.year, hoje.month - 1, 21);
      var descontoCiclo = 0.0;
      for (final c in exclusivos) {
        final dt =
            DateTime.tryParse(c['criado_em']?.toString() ?? '')?.toLocal();
        if (dt == null || dt.isBefore(inicioCiclo)) continue;
        descontoCiclo += ((c['preco'] as num?)?.toDouble() ?? 0) *
            ((c['quantidade'] as num?)?.toInt() ?? 0);
      }
      final limiteDispAjustado =
          (dados.limiteDisp - descontoCiclo).clamp(0.0, double.infinity).toDouble();

      return LojinhaFuncionarioModel(
        limiteTotal: dados.limiteTotal,
        limiteDisp: limiteDispAjustado,
        limiteBruto: dados.limiteBruto,
        pensao: dados.pensao,
        emprestimos: dados.emprestimos,
        planoSaude: dados.planoSaude,
        bonificacao: dados.bonificacao,
        bloqueio: dados.bloqueio,
        centro: dados.centro,
        mensagem: dados.mensagem,
        pedidos: [
          ...dados.pedidos,
          ..._agruparExclusivosPorPedido(exclusivos),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  /// Compras de produtos exclusivos (fora do SAP) do colaborador, já
  /// enriquecidas com descrição e preço do catálogo de exclusivos.
  Future<List<Map<String, dynamic>>> buscarComprasExclusivasLojinha(
    String matricula,
  ) async {
    final compras = await _client
        .from('lojinha_compras_itens')
        .select('material, quantidade, data, criado_em, pedido_id')
        .eq('colaborador_id', matricula)
        .order('criado_em', ascending: false);
    final comprasList = List<Map<String, dynamic>>.from(compras as List);
    if (comprasList.isEmpty) return [];

    final materiais = comprasList
        .map((c) => c['material'] as String)
        .toSet()
        .toList();
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
        'pedido_id': c['pedido_id'],
        'descricao': info?['nome'] as String? ?? 'Produto exclusivo',
        'preco': (info?['preco'] as num?)?.toDouble() ?? 0.0,
      };
    }).toList();
  }

  /// Junta os itens exclusivos do mesmo carrinho (mesmo `pedido_id`) num único
  /// pedido da lista, como no web. Compras antigas, sem `pedido_id`, continuam
  /// uma por uma (não dá pra saber retroativamente o que era do mesmo carrinho).
  List<LojinhaPedidoResumoModel> _agruparExclusivosPorPedido(
      List<Map<String, dynamic>> exclusivos) {
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final c in exclusivos) {
      final chave = (c['pedido_id'] as String?) ??
          'avulso_${c['criado_em']}_${c['material']}';
      grupos.putIfAbsent(chave, () => []).add(c);
    }
    return grupos.values.map((itensDoGrupo) {
      final primeiro = itensDoGrupo.first;
      return LojinhaPedidoResumoModel.exclusivoAgrupado(
        data: primeiro['data'] as String,
        itens: [
          for (final c in itensDoGrupo)
            (
              descricao: c['descricao'] as String,
              quantidade: c['quantidade'] as int,
              preco: c['preco'] as double,
            )
        ],
        criadoEm: primeiro['criado_em'] as String?,
      );
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
      final uri = Uri.parse(_nfeBaseUrl).replace(
        queryParameters: {
          'docnum': 'eq.$docnum',
          'select': 'danfe_url',
          'limit': '1',
        },
      );
      final res = await http
          .get(
            uri,
            headers: {'Content-Type': 'application/json', 'apikey': _nfeApiKey},
          )
          .timeout(const Duration(seconds: 10));
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
  Future<Map<String, int>> buscarEstoqueVisivel(
    List<LojinhaProdutoModel> produtos,
  ) async {
    final colaborador = colaboradorAtual!;
    try {
      final res = await _client.functions.invoke(
        'get-estoque-produto',
        body: {
          'colaborador_id': colaborador.id,
          'materiais': produtos
              .map(
                (p) => {
                  'material': p.material,
                  'centro': p.centro ?? '',
                  'deposito': p.deposito ?? '',
                },
              )
              .toList(),
        },
      );
      debugPrint('buscarEstoqueVisivel raw: ${res.data}');
      final data = res.data as Map<String, dynamic>;
      debugPrint(
        'buscarEstoqueVisivel ok=${data['ok']} estoques=${data['estoques']}',
      );
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
    final results = await Future.wait<dynamic>([
      _client
          .from('lojinha_exclusivos')
          .select('id, material, nome, descricao, foto_url, preco, estoque')
          .eq('ativo', true)
          .order('ordem', ascending: true),
      regrasLojinhaPorMaterial(),
    ]);
    final regrasPorMaterial =
        results[1] as Map<String, Map<String, dynamic>>;
    final branch = colaboradorAtual?.branch;
    return (results[0] as List)
        .map((e) {
          final j = e as Map<String, dynamic>;
          final mat =
              (j['material'] as String? ?? '').replaceAll(RegExp(r'^0+'), '');
          final regra = regrasPorMaterial[mat] ?? regrasPorMaterial[j['material']];
          return LojinhaProdutoModel.fromExclusivo(j, regra: regra);
        })
        .where((p) => p.disponivelParaFilial(branch))
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
            .map(
              (p) =>
                  LojinhaPedidoCentroResult.fromJson(p as Map<String, dynamic>),
            )
            .toList();
      }

      // Itens exclusivos → Supabase, SÓ depois do SAP dar ok (igual ao web):
      // se o SAP falhar, nada de exclusivo é debitado nem registrado.
      // `comprar_exclusivo` debita o estoque e registra a compra numa única
      // transação atômica no banco — só registra se realmente havia
      // estoque suficiente (ver migrations/2026-07-04g_comprar_exclusivo_atomico.sql).
      if (itensExclusivos.isNotEmpty && ok) {
        final matricula = colaborador.matricula;
        final colabNome = colaborador.nome;
        final semEstoque = <String>[];
        // Mesmo pedido_id para todos os exclusivos desse checkout: é o que
        // agrupa os itens num único card em "Meus pedidos".
        final pedidoId = '${matricula}_${hoje.microsecondsSinceEpoch}';
        for (final item in itensExclusivos) {
          final sucesso =
              await _client.rpc(
                    'comprar_exclusivo',
                    params: {
                      'p_material': item.produto.material,
                      'p_quantidade': item.quantidade,
                      'p_colaborador_id': matricula,
                      'p_colaborador_nome': colabNome,
                      'p_data': dataStr,
                      'p_pedido_id': pedidoId,
                    },
                  )
                  as bool;
          if (!sucesso) semEstoque.add(item.produto.descricao);
        }
        if (itensRegulares.isEmpty) {
          ok = semEstoque.length < itensExclusivos.length;
          retorno = semEstoque.isEmpty
              ? 'Pedido exclusivo registrado com sucesso!'
              : 'Sem estoque suficiente para: ${semEstoque.join(', ')}.';
        } else if (semEstoque.isNotEmpty) {
          retorno =
              '$retorno\nSem estoque suficiente para: ${semEstoque.join(', ')}.';
        }
      }

      // Registra total em lojinha_compras (para controle de limite global)
      if (ok) {
        final qtdTotal = itens.fold<int>(0, (s, i) => s + i.quantidade);
        final qtdExclusivo =
            itensExclusivos.fold<int>(0, (s, i) => s + i.quantidade);
        await _client.from('lojinha_compras').insert({
          'colaborador_id': colaborador.matricula,
          'quantidade_total': qtdTotal,
          'quantidade_exclusivo': qtdExclusivo,
          'data': dataStr,
          'teve_regular': itensRegulares.isNotEmpty,
          'teve_exclusivo': itensExclusivos.isNotEmpty,
        });
      }

      return (ok: ok, retorno: retorno, pedidos: pedidos);
    } catch (e, st) {
      ErrorReporter.report(e, st, contexto: 'Finalizar pedido na lojinha');
      return (
        ok: false,
        retorno:
            'Não foi possível concluir o pedido. Verifique sua conexão e tente novamente.',
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
    String matricula,
    String empresa,
  ) async {
    final data = await _client
        .from('colaboradores')
        .select()
        .eq('matricula', matricula)
        .eq('empresa', empresa)
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
        apelido: colaboradorAtual!.apelido,
        branch: colaboradorAtual!.branch,
        ehGestor: colaboradorAtual!.ehGestor,
      );

      return urlFinal;
    } catch (_) {
      return null;
    }
  }

  // ─── Humor do Dia ────────────────────────────────────────────

  /// Retorna o registro de humor do colaborador para hoje, ou null se não registrou.
  ///
  /// Humor registrado a partir das 18h conta como do dia seguinte (pensado
  /// no turno da noite: fica visível para quem trabalha de dia). Quem já
  /// respondeu hoje não responde de novo depois das 18h.
  static const int horaCorteHumor = 18;

  static String _dataHumorStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

  /// Dia (yyyy-MM-dd) a que um humor feito em [momento] pertence.
  static String diaDoHumor(DateTime momento) => _dataHumorStr(
      momento.hour >= horaCorteHumor
          ? DateTime(momento.year, momento.month, momento.day + 1)
          : momento);

  Future<Map<String, dynamic>?> buscarHumorHoje() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return null;
    final agora = DateTime.now();
    // Depois das 18h, um registro de hoje (feito antes) ou de amanhã (feito
    // depois) já vale como "respondeu".
    final datas = {_dataHumorStr(agora), diaDoHumor(agora)}.toList();
    return await _client
        .from('humor_registros')
        .select()
        .eq('colaborador_id', meuId)
        .inFilter('data', datas)
        .order('data', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  /// Salva o humor do dia. Retorna false se já registrado ou erro.
  Future<bool> registrarHumor({required int nivel, String? motivo}) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return false;
    try {
      final dataStr = diaDoHumor(DateTime.now());
      await _client.from('humor_registros').insert({
        'colaborador_id': meuId,
        'nivel': nivel,
        'data': dataStr,
        if (motivo != null && motivo.isNotEmpty) 'motivo': motivo,
      });
      PontosBus.notificarGanho();
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
          .eq('status_confirmacao', 'CONFIRMADO')
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

  /// Feedbacks formais do gestor ainda não visualizados (badge em Performance).
  Future<int> contarFeedbacksGestorNaoLidos() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return 0;
    try {
      final res = await _client
          .from('avaliacao_feedbacks')
          .select('id')
          .eq('colaborador_id', meuId)
          .filter('visualizado_em', 'is', null);
      return (res as List).length;
    } catch (_) {
      return 0;
    }
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
    // Sem paginar, o Supabase corta em 1000 linhas por padrão — com mais de
    // 2000 colaboradores cadastrados, isso fazia a busca de "Elogiar" nunca
    // encontrar quem tivesse nome ordenado depois do corte alfabético.
    final todos = <dynamic>[];
    int from = 0;
    const pageSize = 1000;
    while (true) {
      final res = await _client
          .from('colaboradores')
          .select('id, nome, setor, cargo')
          .eq('demitido', false)
          .neq('id', meuId ?? 0)
          .order('nome', ascending: true)
          .range(from, from + pageSize - 1);
      final page = res as List;
      todos.addAll(page);
      if (page.length < pageSize) break;
      from += pageSize;
    }
    return List<Map<String, dynamic>>.from(todos);
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
        .select(
          'id, pesquisa_id, tipo_destinatario, setores_alvo, '
          'agrupamentos_alvo, data_inicio, data_fim, pesquisas(*)',
        )
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
    meusAgrupamentos.addAll(
      (membros as List).map((e) => e['agrupamento_id'] as int),
    );

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
          visivel = parseLista(envio['agrupamentos_alvo']).any(
            (g) => meusAgrupamentos.contains(
              g is int ? g : int.tryParse(g.toString()) ?? -1,
            ),
          );
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

    final pesquisaIds = pesquisasVisiveis.values
        .map((p) => p['id'] as int)
        .toSet()
        .toList();
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
        'ja_respondeu': respondidasSet.contains(
          '${p['id']}_${p['colaborador_alvo_id']}',
        ),
      };
    }).toList()..sort(
      (a, b) => (b['criado_em'] as String? ?? '').compareTo(
        a['criado_em'] as String? ?? '',
      ),
    );
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
              .then(
                (r) => (r as List).map((e) => e['envio_id'] as int).toSet(),
              );
          visivel = meusEnviosColab!.contains(envio['id'] as int);
          break;
        case 'agrupamentos':
          meusAgrupamentos ??= await _client
              .from('agrupamento_membros')
              .select('agrupamento_id')
              .eq('colaborador_id', colab.id)
              .then(
                (r) =>
                    (r as List).map((e) => e['agrupamento_id'] as int).toSet(),
              );
          visivel = parseLista(envio['agrupamentos_alvo']).any(
            (g) => meusAgrupamentos!.contains(
              g is int ? g : int.tryParse(g.toString()) ?? -1,
            ),
          );
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
    Map<int, String>? motivosNao,
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
        // Motivo de um "Não" (pedir_motivo_se_nao) — igual ao web.
        final motivo = motivosNao?[e.key];
        if (e.value == false && motivo != null && motivo.trim().isNotEmpty) {
          mapa['valor_texto'] = motivo.trim();
        }
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
        PontosBus.notificarGanho();
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
    // Vaga sigilosa não aparece no Eu Crio Oportunidades.
    return (data as List)
        .map((e) => VagaModel.fromJson(e as Map<String, dynamic>))
        .where((v) => !v.sigilosa)
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
      final novo = await _client
          .from('candidatos')
          .insert({
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
          })
          .select('id')
          .single();
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

  // ─── Candidatura de colaborador: aprovação do gestor direto ─────────────
  // Mesma tabela/regra do painel web (`candidaturas_gestor_aprovacao`, ids
  // como texto).

  bool _ehJaInscrito(Object e) => e.toString().contains('já inscrito');

  /// Pede a candidatura do colaborador a uma vaga. Com gestor, cria pedido
  /// pendente e devolve 'pendente' (a candidatura real só nasce na aprovação);
  /// sem gestor (ou se ele mesmo é o gestor), inscreve direto ('direto').
  /// 'ja_existe' se já há pedido pendente/aprovado pra essa vaga.
  Future<String> solicitarCandidaturaColab({
    required int vagaId,
    required String vagaTitulo,
    required ColaboradorModel colaborador,
  }) async {
    final existente = await _client
        .from('candidaturas_gestor_aprovacao')
        .select('id')
        .eq('vaga_id', vagaId.toString())
        .eq('colaborador_id', colaborador.id.toString())
        .inFilter('status', ['pendente', 'aprovada']);
    if ((existente as List).isNotEmpty) return 'ja_existe';

    final gestor = await buscarGestorDoSetor(
      colaborador.setor ?? '',
      colaborador.empresa ?? '',
      colaboradorId: colaborador.id,
    );
    if (gestor == null || gestor.id == colaborador.id) {
      try {
        await inscreverColaboradorNaVaga(
          colaboradorId: colaborador.id,
          vagaId: vagaId,
          nome: colaborador.nome,
          cpf: colaborador.cpf ?? '',
          email: '',
          telefone: '',
        );
      } catch (e) {
        if (_ehJaInscrito(e)) return 'ja_existe';
        rethrow;
      }
      return 'direto';
    }
    await _client.from('candidaturas_gestor_aprovacao').insert({
      'vaga_id': vagaId.toString(),
      'vaga_titulo': vagaTitulo,
      'colaborador_id': colaborador.id.toString(),
      'colaborador_nome': colaborador.nome,
      'colaborador_cpf': colaborador.cpf,
      'gestor_id': gestor.id.toString(),
    });
    return 'pendente';
  }

  /// Pedidos de candidatura aguardando a decisão deste gestor.
  Future<List<Map<String, dynamic>>> listarCandidaturasPendentesGestor(
      int gestorId) async {
    final res = await _client
        .from('candidaturas_gestor_aprovacao')
        .select()
        .eq('gestor_id', gestorId.toString())
        .eq('status', 'pendente')
        .order('criado_em');
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Pedidos do próprio colaborador (qualquer status), mais recentes primeiro.
  Future<List<Map<String, dynamic>>> listarPedidosCandidaturaColab(
      int colaboradorId) async {
    final res = await _client
        .from('candidaturas_gestor_aprovacao')
        .select()
        .eq('colaborador_id', colaboradorId.toString())
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Aprova (cria a candidatura real pro RH) ou reprova (com motivo).
  Future<void> decidirCandidaturaGestor({
    required Map<String, dynamic> pedido,
    required bool aprovado,
    String? motivo,
  }) async {
    if (aprovado) {
      // Só marca 'aprovada' se a candidatura real existe. Já inscrito = já
      // existe, segue (igual ao web); falha de verdade aborta.
      try {
        await inscreverColaboradorNaVaga(
          colaboradorId: int.parse(pedido['colaborador_id'].toString()),
          vagaId: int.parse(pedido['vaga_id'].toString()),
          nome: pedido['colaborador_nome'] as String,
          cpf: (pedido['colaborador_cpf'] as String?) ?? '',
          email: '',
          telefone: '',
        );
      } catch (e) {
        if (!_ehJaInscrito(e)) rethrow;
      }
    }
    await _client.from('candidaturas_gestor_aprovacao').update({
      'status': aprovado ? 'aprovada' : 'reprovada',
      'motivo_reprovacao': aprovado ? null : motivo?.trim(),
      'decidido_em': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', pedido['id']);
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
    String? matriculaIndicador,
  }) async {
    // Verifica se já existe candidatura para esse candidato+vaga
    final existente = await _client
        .from('candidaturas')
        .select('id, indicado_por_id')
        .eq('candidato_id', candidatoId)
        .eq('vaga_id', vagaId)
        .maybeSingle();

    // Igual ao web: a indicação nasce 'pendente' (o indicador confirma depois
    // em "Eu crio oportunidades"), que é o que dispara os pontos.
    final indicacao = {
      'indicado_por_id': colaboradorId,
      'tipo_origem': 'INDICACAO',
      if (matriculaIndicador != null && matriculaIndicador.isNotEmpty)
        'matricula_indicador': matriculaIndicador,
      'status_indicacao': 'pendente',
    };

    if (existente != null) {
      // Já tem candidatura — atualiza o indicador
      if (existente['indicado_por_id'] != null) throw Exception('já indicado');
      await _client
          .from('candidaturas')
          .update(indicacao)
          .eq('id', existente['id'] as int);
    } else {
      // Sem candidatura ainda — cria vinculada ao indicador
      await _client.from('candidaturas').insert({
        'candidato_id': candidatoId,
        'vaga_id': vagaId,
        'status': 'INSCRITO',
        'salario_esperado': 0,
        ...indicacao,
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
    final candidato = await _client
        .from('candidatos')
        .insert({
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
        })
        .select('id')
        .single();
    await _client.from('candidaturas').insert({
      'candidato_id': candidato['id'] as int,
      'vaga_id': vagaId,
      'status': 'INSCRITO',
      'salario_esperado': 0,
      'tipo_origem': 'INDICACAO',
      'indicado_por_id': colaboradorId,
    });
  }

  /// Vagas para as quais o colaborador logado já se candidatou (via CPF),
  /// usado para avisar na tela "Eu Crio Oportunidades" que já existe uma
  /// candidatura dele pra aquela vaga.
  Future<Set<int>> buscarVagasJaCandidatadas() async {
    final cpf = colaboradorAtual?.cpf?.replaceAll(RegExp(r'\D'), '');
    if (cpf == null || cpf.isEmpty) return {};
    final candidato = await buscarCandidatoPorCpf(cpf);
    if (candidato == null) return {};
    final res = await _client
        .from('candidaturas')
        .select('vaga_id')
        .eq('candidato_id', candidato['id'] as int);
    return (res as List).map((e) => e['vaga_id'] as int).toSet();
  }

  /// Vagas para as quais o colaborador logado já indicou algum candidato,
  /// com o nome do candidato indicado — usado para avisar na tela "Eu Crio
  /// Oportunidades" que já existe uma indicação dele pra aquela vaga.
  Future<Map<int, String>> buscarIndicacoesDoColaborador() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return {};
    final res = await _client
        .from('candidaturas')
        .select('vaga_id, candidatos(nome)')
        .eq('indicado_por_id', meuId);
    final mapa = <int, String>{};
    for (final item in res as List) {
      final nome =
          (item['candidatos'] as Map<String, dynamic>?)?['nome'] as String?;
      if (nome != null) mapa[item['vaga_id'] as int] = nome;
    }
    return mapa;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ADICIONAR NO api_service.dart — cole cada bloco na seção correspondente
  // ════════════════════════════════════════════════════════════════════════════

  // ─── Cardápio do Refeitório (imagem única) ─────────────────────────────────

  /// Busca a imagem única do cardápio (ex: foto do quadro semanal). Retorna
  /// null se ainda não houver imagem cadastrada.
  /// Textos do cardápio entre [inicio] e [fim] (inclusive), chaveados por
  /// 'yyyy-MM-dd'. Dias sem cadastro não aparecem no mapa.
  Future<Map<String, String>> buscarCardapioDias(
      DateTime inicio, DateTime fim) async {
    String iso(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final res = await _client
        .from('cardapio_dias')
        .select('data, texto')
        .gte('data', iso(inicio))
        .lte('data', iso(fim));
    return {
      for (final r in (res as List))
        (r['data'] as String).substring(0, 10): (r['texto'] as String? ?? '')
    };
  }

  Future<String?> buscarCardapioImagem() async {
    final res = await _client
        .from('cardapio_config')
        .select('imagem_url')
        .eq('id', 1)
        .maybeSingle();
    return res?['imagem_url'] as String?;
  }

  // ─── Reserva de Salas ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listarSalasReserva({
    bool apenasAtivas = false,
  }) async {
    var query = _client.from('salas_reserva').select();
    if (apenasAtivas) query = query.eq('ativo', true);
    final res = await query
        .order('ordem', ascending: true)
        .order('nome', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Todas as reservas de uma sala num intervalo de datas — usado pra montar
  /// a agenda do dia antes de escolher o horário.
  Future<List<Map<String, dynamic>>> listarTodasReservasSalas({
    int? salaId,
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    var query = _client.from('reservas_salas').select();
    if (salaId != null) query = query.eq('sala_id', salaId);
    if (dataInicio != null) query = query.gte('data', fmt(dataInicio));
    if (dataFim != null) query = query.lte('data', fmt(dataFim));
    final res = await query
        .order('data', ascending: true)
        .order('hora_inicio', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> listarMinhasReservasSalas(
    String colaboradorId,
  ) async {
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
      await _client.rpc(
        'reservar_sala',
        params: {
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
        },
      );
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

  /// Sem regra global — só existe pra colaborador de filial com pelo menos
  /// uma data cadastrada.
  Future<List<String>> buscarDiasDisponiveisNutricionista() async {
    final colaborador = colaboradorAtual;
    final filial = colaborador?.filialEfetiva;
    if (filial == null || filial.isEmpty) return [];

    final hoje = _brasilia();
    final hojeStr =
        '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';

    // Janela de datas: hoje ate +90 dias (igual ao web).
    final limiteDias = hoje.add(const Duration(days: 90));
    final limiteDiasStr =
        '${limiteDias.year}-${limiteDias.month.toString().padLeft(2, '0')}-${limiteDias.day.toString().padLeft(2, '0')}';

    final data = await _client
        .from('nutricionista_config_dias')
        .select('data')
        .eq('ativo', true)
        .eq('filial', filial)
        .gte('data', hojeStr)
        .lte('data', limiteDiasStr)
        .order('data', ascending: true);

    return (data as List).map((e) => e['data'] as String).toList();
  }

  Future<List<NutricionistaAgendamentoModel>>
  buscarAgendamentosNutricionista() async {
    // Busca os agendamentos dos próximos 90 dias para montar a grade de horários.
    final hoje = _brasilia();
    final limite = hoje.add(const Duration(days: 90));
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
        .map(
          (e) =>
              NutricionistaAgendamentoModel.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  /// Pre-checagem (mesma query do web): ja existe agendamento nao cancelado
  /// do colaborador logado nessa data?
  Future<bool> jaTemAgendamentoNutricionistaNoDia(String data) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return false;
    try {
      final existing = await _client
          .from('nutricionista_agendamentos')
          .select('id')
          .eq('colaborador_id', meuId)
          .eq('data', data)
          .neq('status', 'CANCELADO')
          .maybeSingle();
      return existing != null;
    } catch (_) {
      return false;
    }
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
    return _client.storage.from('assinaturas-massoterapia').getPublicUrl(path);
  }

  // ─── Fisioterapia ────────────────────────────────────────────────────────────
  // Tela do prestador (fisioterapeuta) e do colaborador (somente leitura).
  // Mesmas tabelas/buckets já criados e usados pelo app Admin.

  // -- Prestador -------------------------------------------------------------

  Future<List<FisioterapiaCaso>> listarMeusCasosFisioterapia(
    int fisioterapeutaId,
  ) async {
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
    List<int> casoIds,
  ) async {
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
    int id,
    Map<String, dynamic> dados,
  ) async {
    try {
      await _client.from('fisioterapia_sessoes').update(dados).eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<FisioterapiaExercicio>> listarExerciciosFisioterapia(
    int casoId,
  ) async {
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
    int casoId,
  ) async {
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

  // ─── Consulta médica ─────────────────────────────────────────────────────────
  // O colaborador solicita e o SESMT marca dia e hora (tela do painel admin).

  Future<List<Map<String, dynamic>>> listarMinhasConsultasMedicas() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return [];
    final res = await _client
        .from('consultas_medicas')
        .select()
        .eq('colaborador_id', meuId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<bool> solicitarConsultaMedica(String motivo) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null || motivo.trim().isEmpty) return false;
    try {
      await _client.from('consultas_medicas').insert({
        'colaborador_id': meuId,
        'motivo': motivo.trim(),
      });
      return true;
    } catch (_) {
      return false;
    }
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
  /// Tamanho da página do feed (linhas lidas do banco por chamada).
  static const _tamanhoPaginaFeed = 20;

  /// true quando a última página lida do banco veio cheia — ou seja, ainda
  /// pode haver mais posts. O filtro por destinatário roda depois da busca e
  /// pode reduzir a lista devolvida, então a tela não deve decidir "tem mais"
  /// pelo tamanho da lista filtrada.
  bool feedTemMaisPaginas = true;

  Future<List<FeedPostModel>> buscarFeed({int pagina = 0}) async {
    final colab = colaboradorAtual;
    if (colab == null) return [];

    // Traz posts aprovados visíveis + os próprios posts (qualquer status).
    // Páginas sem sobreposição (passo = tamanho da página).
    final inicio = pagina * _tamanhoPaginaFeed;
    final data = await _client
        .from('feed_posts')
        .select('*, autor:colaboradores!autor_id(nome, foto_url, cargo)')
        .or('status.eq.aprovado,autor_id.eq.${colab.id}')
        .order('criado_em', ascending: false)
        .range(inicio, inicio + _tamanhoPaginaFeed - 1);
    final linhas = data as List;
    feedTemMaisPaginas = linhas.length >= _tamanhoPaginaFeed;

    final posts = linhas
        .map((e) => FeedPostModel.fromJson(e as Map<String, dynamic>))
        .where((p) {
          // Comunicados vêm da tabela dedicada — exclui os que podem estar em feed_posts
          if (p.tipo == 'comunicado') return false;
          // Post de humor vale só no seu dia — feito a partir das 18h, conta
          // como do dia seguinte (o autor vê o próprio post já no mesmo dia).
          if (p.tipo == 'humor') {
            final c = p.criadoEm.toLocal();
            final hoje = DateTime.now();
            final mesmoDiaCivil = c.year == hoje.year &&
                c.month == hoje.month &&
                c.day == hoje.day;
            final valeHoje = diaDoHumor(c) == _dataHumorStr(hoje);
            if (!valeHoje && !(mesmoDiaCivil && p.autorId == colab.id)) {
              return false;
            }
          }
          // O próprio autor sempre vê seus posts (com qualquer status)
          if (p.autorId == colab.id) return true;
          // Posts de terceiros só aparecem se aprovados
          if (!p.isAprovado) return false;
          if (p.destinatario == 'todos') return true;
          // '@setor:A' ou vários setores ('@setor:A,B') — o composer grava os
          // dois formatos (app e web).
          if (p.destinatario.startsWith('@setor:')) {
            final setores = p.destinatario
                .substring('@setor:'.length)
                .split(',')
                .map((e) => e.trim());
            if (colab.setor != null && setores.contains(colab.setor)) {
              return true;
            }
          }
          // Suporta '@colaborador:42', '@colaborador:42|NOME' e vários
          // destinatários ('@colaborador:42,57|NOME1, NOME2')
          if (p.destinatario.startsWith('@colaborador:')) {
            final ids = p.destinatario
                .substring('@colaborador:'.length)
                .split('|')
                .first
                .split(',')
                .map((e) => e.trim());
            if (ids.contains(colab.id.toString())) return true;
          }
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
          conteudo: descricao != null && descricao.isNotEmpty
              ? descricao
              : null,
          imagemUrl: c['foto_url'] as String?,
          destinatario: 'todos',
          criadoEm: _parseComunicadoTs(c['criado_em'] as String),
          enqueteId: (c['enquete_id'] as num?)?.toInt(),
        );
      }).toList();

      final tudo = [...posts, ...comunicados];
      tudo.sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
      // Comunicados das últimas 24h ficam fixados no topo
      final agoraUtc = DateTime.now().toUtc();
      bool fixado(FeedPostModel p) =>
          p.tipo == 'comunicado' &&
          agoraUtc.difference(p.criadoEm.subtract(const Duration(hours: 3))) <
              const Duration(hours: 24);
      final fixados = tudo.where(fixado).toList();
      final demais = tudo.where((p) => !fixado(p)).toList();
      return [...fixados, ...demais].take(40).toList();
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
        final caminho =
            'posts/$meuId/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await _client.storage
            .from('feed-imagens')
            .uploadBinary(
              caminho,
              Uint8List.fromList(imagemBytes),
              fileOptions: FileOptions(
                contentType: 'image/$ext',
                upsert: false,
              ),
            );
        imagemUrl = _client.storage.from('feed-imagens').getPublicUrl(caminho);
      }

      // Posts para 'todos' precisam de aprovação do RH; demais vão direto.
      // Posts de humor sem motivo são só o nível selecionado (sem texto
      // livre do usuário) e saem aprovados direto; com motivo preenchido,
      // vira texto livre e precisa da mesma aprovação de qualquer post.
      final precisaAprovacao =
          destinatario == 'todos' && (tipo != 'humor' || temTextoLivre);
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

  /// Reações possíveis a um post do feed, na ordem em que aparecem na barra.
  static const tiposReacaoPost = {
    'gostei': Icons.thumb_up_rounded,
    'parabens': Icons.celebration_rounded,
    'amei': Icons.favorite_rounded,
    'estrela': Icons.star_rounded,
  };

  /// Todas as reações de um post, com dados de quem reagiu — usado tanto
  /// para contar por tipo quanto para o modal "quem reagiu".
  ///
  /// [postId] negativo identifica um comunicado (id sintético = -id real na
  /// tabela `comunicados`), que guarda reações em `comunicado_reacoes`.
  Future<List<Map<String, dynamic>>> buscarReacoesPost(int postId) async {
    final ehComunicado = postId < 0;
    final res = await _client
        .from(ehComunicado ? 'comunicado_reacoes' : 'feed_post_reacoes')
        .select('colaborador_id, tipo, colaboradores(nome, foto_url)')
        .eq(ehComunicado ? 'comunicado_id' : 'post_id', ehComunicado ? -postId : postId);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Reage a um post (ou comunicado, se [postId] for negativo) com [tipo].
  /// Repetir o mesmo tipo remove a reação (toggle); reagir com um tipo
  /// diferente troca a reação anterior — só uma reação por colaborador por
  /// post, como no LinkedIn.
  Future<void> reagirPost({required int postId, required String tipo}) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return;
    final ehComunicado = postId < 0;
    final tabela = ehComunicado ? 'comunicado_reacoes' : 'feed_post_reacoes';
    final colunaId = ehComunicado ? 'comunicado_id' : 'post_id';
    final idReal = ehComunicado ? -postId : postId;
    final existente = await _client
        .from(tabela)
        .select('id, tipo')
        .eq(colunaId, idReal)
        .eq('colaborador_id', meuId)
        .maybeSingle();
    if (existente == null) {
      await _client.from(tabela).insert({
        colunaId: idReal,
        'colaborador_id': meuId,
        'tipo': tipo,
      });
    } else if (existente['tipo'] == tipo) {
      await _client.from(tabela).delete().eq('id', existente['id'] as int);
    } else {
      await _client
          .from(tabela)
          .update({'tipo': tipo})
          .eq('id', existente['id'] as int);
    }
  }

  /// Lista os setores distintos cadastrados, para o seletor de "Para: Por setor".
  Future<List<String>> listarSetoresDistintos() async {
    // Sem paginar, o Supabase corta em 1000 linhas por padrão — com mais de
    // 2000 colaboradores cadastrados, setores só usados por gente cujo nome
    // (ordem física da tabela) cai depois do corte podiam nunca aparecer.
    final setores = <String>{};
    int from = 0;
    const pageSize = 1000;
    while (true) {
      final res = await _client
          .from('colaboradores')
          .select('setor')
          .eq('demitido', false)
          .not('setor', 'is', null)
          .range(from, from + pageSize - 1);
      final page = res as List;
      for (final e in page) {
        final s = e['setor'] as String?;
        if (s != null) setores.add(s);
      }
      if (page.length < pageSize) break;
      from += pageSize;
    }
    return setores.toList();
  }

  /// Busca colaboradores pelo nome, para o seletor de "Para: Individual".
  Future<List<Map<String, dynamic>>> buscarColaboradoresParaDestinatario(
    String query,
  ) async {
    if (query.isEmpty) return [];
    final res = await _client
        .from('colaboradores')
        .select('id, nome, setor')
        .eq('demitido', false)
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

    // Busca setores distintos (já paginado — ver listarSetoresDistintos).
    final todosSetores = await listarSetoresDistintos();

    // Query vazia: mostra "Todos" + todos os setores (sem busca de colaborador)
    if (q.isEmpty) {
      return [
        {
          'tipo': 'todos',
          'label': 'Todos',
          'sublabel': 'Todos os colaboradores',
          'valor': 'todos',
        },
        ...todosSetores
            .take(6)
            .map(
              (s) => {
                'tipo': 'setor',
                'label': '@$s',
                'sublabel': 'Setor',
                'valor': '@setor:$s',
              },
            ),
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
        .eq('demitido', false)
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
        .select(
          'id, vaga_id, candidato_id, status, status_indicacao, matricula_indicador, candidatos(nome, cpf), vagas(titulo)',
        )
        .eq('status_indicacao', 'pendente');

    final List resultados = [];

    final byMatricula = await query.eq('matricula_indicador', matricula);
    resultados.addAll(byMatricula as List);

    if (cpf.isNotEmpty && cpf != matricula) {
      final byCpf = await _client
          .from('candidaturas')
          .select(
            'id, vaga_id, candidato_id, status, status_indicacao, matricula_indicador, candidatos(nome, cpf), vagas(titulo)',
          )
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
      await _client
          .from('candidaturas')
          .update({
            'status_indicacao': 'confirmado',
            'indicado_por_id': col.id,
            'tipo_origem': 'INDICACAO',
          })
          .eq('id', candidaturaId);
    } else {
      await _client
          .from('candidaturas')
          .update({'status_indicacao': 'rejeitado'})
          .eq('id', candidaturaId);
    }
  }

  /// Portado do gentepole_admin: não depende só de `hierarquia_nomes` (que
  /// pode vir vazia por RLS/falta de apelido cadastrado nesse contexto) —
  /// deriva os códigos de filial de `colaboradores.branch` (sempre
  /// sincronizado do TOTVS) e usa `hierarquia_nomes` só pra dar nome
  /// bonito, com fallback pro código cru.
  Future<List<Map<String, dynamic>>> listarFiliais() async {
    final nomesRes = await _client
        .from('hierarquia_nomes')
        .select('chave, nome')
        .eq('tipo', 'filial');
    final nomesPorChave = {
      for (final n in nomesRes as List)
        n['chave'] as String: n['nome'] as String
    };

    // Paginado — o Supabase limita a 1000 linhas por padrão.
    final codigos = <String>{};
    int from = 0;
    const pageSize = 1000;
    while (true) {
      final page = await _client
          .from('colaboradores')
          .select('branch')
          .eq('demitido', false)
          .range(from, from + pageSize - 1);
      final linhas = page as List;
      for (final c in linhas) {
        final branch = c['branch'] as String?;
        if (branch != null && branch.isNotEmpty) codigos.add(branch);
      }
      if (linhas.length < pageSize) break;
      from += pageSize;
    }

    final lista = codigos
        .map<Map<String, dynamic>>((cod) =>
            {'chave': cod, 'nome': nomesPorChave[cod] ?? 'Filial $cod'})
        .toList();
    lista.sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));
    return lista;
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
    int colaboradorId,
  ) async {
    final data = await _client
        .from('avaliacao_feedbacks')
        .select('*, autor:autor_id(nome)')
        .eq('colaborador_id', colaboradorId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Feedbacks marcados como "presencial" pelo gestor que o colaborador
  /// ainda não confirmou nem negou — usado pro card de aviso no Feed.
  Future<List<Map<String, dynamic>>> listarFeedbacksPresenciaisPendentes(
    int colaboradorId,
  ) async {
    final data = await _client
        .from('avaliacao_feedbacks')
        .select('id, texto, autor:autor_id(nome)')
        .eq('colaborador_id', colaboradorId)
        .eq('presencial', true)
        .filter('presencial_confirmado', 'is', null)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Colaborador confirma ([confirmado] = true) ou nega ([confirmado] =
  /// false) que o feedback marcado como "presencial" pelo gestor
  /// realmente aconteceu pessoalmente.
  Future<void> confirmarFeedbackPresencial(int feedbackId, bool confirmado) async {
    await _client
        .from('avaliacao_feedbacks')
        .update({'presencial_confirmado': confirmado})
        .eq('id', feedbackId);
  }

  /// Solicitações de feedback que o colaborador enviou pra outras pessoas.
  Future<List<Map<String, dynamic>>> listarSolicitacoesFeedbackEnviadas(
    int colaboradorId,
  ) async {
    // solicitante_id é text no banco (guarda o id como string) — comparar
    // direto com int dá "operator does not exist: text = integer".
    final data = await _client
        .from('feedback_solicitacoes')
        .select()
        .eq('solicitante_id', colaboradorId.toString())
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
    PontosBus.notificarGanho();
  }

  Future<List<Map<String, dynamic>>> listarElogiosRecebidos(
    int colaboradorId,
  ) async {
    final data = await _client
        .from('elogios')
        .select()
        .eq('colaborador_id', colaboradorId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// O destinatário responde a um elogio recebido. A resposta fica na própria
  /// linha de `elogios`; quem responde nunca recebe o remetente de um elogio
  /// anônimo (a tela só mostra "Anônimo").
  Future<bool> responderElogio({
    required int elogioId,
    required String resposta,
  }) async {
    try {
      await _client
          .from('elogios')
          .update({
            'resposta': resposta.trim(),
            'respondido_em': DateTime.now().toIso8601String(),
          })
          .eq('id', elogioId);
      return true;
    } catch (e, st) {
      ErrorReporter.report(e, st, contexto: 'Responder elogio');
      return false;
    }
  }

  /// Elogios enviados pelo colaborador que já foram respondidos.
  /// Silencioso se a coluna `resposta` ainda não existir.
  Future<List<Map<String, dynamic>>> listarRespostasAosMeusElogios(
    int autorId,
  ) async {
    try {
      final data = await _client
          .from('elogios')
          .select('id, texto, resposta, respondido_em, colaborador_id')
          .eq('autor_id', autorId)
          .not('resposta', 'is', null)
          .order('respondido_em', ascending: false);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }

  /// Gestor de um colaborador — usado pra "Pedir feedback ao meu gestor" e
  /// nas Solicitações. Prioriza a hierarquia resolvida pela Administração de
  /// Setor do painel web (`colaborador_hierarquia`, quando [colaboradorId] é
  /// passado): gestor > coordenador > supervisor > gerente geral, na ordem de
  /// quem está mais perto da pessoa. Sem hierarquia configurada pra ela, cai
  /// pro sinal antigo (`colaboradores.eh_gestor` do primeiro gestor achado no
  /// setor).
  Future<ColaboradorModel?> buscarGestorDoSetor(
      String setor, String empresa, {int? colaboradorId}) async {
    if (colaboradorId != null) {
      final hierarquia = await _client
          .from('colaborador_hierarquia')
          .select('nivel, responsavel_id')
          .eq('colaborador_id', colaboradorId);
      // Vários responsáveis no mesmo nível ("Geral" em dupla): fica o de menor
      // id, pra a escolha ser sempre a mesma.
      final porNivel = <String, int>{};
      for (final h in (hierarquia as List)) {
        final nivel = h['nivel'] as String;
        final resp = h['responsavel_id'] as int;
        final atual = porNivel[nivel];
        if (atual == null || resp < atual) porNivel[nivel] = resp;
      }
      for (final nivel in _niveisComAcessoDeGestor) {
        final responsavelId = porNivel[nivel];
        if (responsavelId == null) continue;
        final data = await _client
            .from('colaboradores')
            .select()
            .eq('id', responsavelId)
            .eq('demitido', false)
            .maybeSingle();
        if (data != null) return ColaboradorModel.fromJson(data);
      }
    }

    // Fallback igual ao do web: quem tem o perfil 'gestor' em usuarios_admin
    // (ativo, mesma empresa) e está lotado no mesmo setor.
    final gestores = await _client
        .from('usuarios_admin')
        .select('matricula, roles')
        .eq('ativo', true)
        .eq('empresa', empresa);
    final matriculasGestores = List<Map<String, dynamic>>.from(gestores)
        .where((g) =>
            (g['roles']?.toString() ?? '').toLowerCase().contains('gestor'))
        .map((g) => g['matricula'] as String)
        .toList();
    if (matriculasGestores.isEmpty) return null;
    final colabs = await _client
        .from('colaboradores')
        .select()
        .inFilter('matricula', matriculasGestores)
        .eq('empresa', empresa)
        .eq('setor', setor)
        .eq('demitido', false)
        .limit(1);
    final lista = List<Map<String, dynamic>>.from(colabs);
    if (lista.isEmpty) return null;
    return ColaboradorModel.fromJson(lista.first);
  }

  /// Os itens fixos (por slot) de avaliação por estrelas, configurados pelo RH.
  /// Todos os itens (linhas) de todas as matrizes de feedback, cada um com
  /// seu `grupo_id` — o RH pode cadastrar várias matrizes independentes
  /// (ver [listarGruposItensEmpresaFeedback]). 'slot' é do modelo antigo (2
  /// itens fixos) e pode vir nulo hoje, por isso a ordenação é por 'ordem'.
  Future<List<Map<String, dynamic>>> listarItensEmpresaFeedback() async {
    final data = await _client
        .from('feedback_itens_empresa')
        .select()
        .order('ordem');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// As matrizes de itens de feedback cadastradas pelo RH (ex:
  /// "Competências organizacionais", "Valores organizacionais"), na ordem
  /// de exibição — cada uma agrupa suas linhas via `feedback_itens_empresa.grupo_id`.
  Future<List<Map<String, dynamic>>> listarGruposItensEmpresaFeedback() async {
    final data = await _client
        .from('feedback_itens_grupos')
        .select()
        .order('ordem');
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
        'criado_em': DateTime.now().toUtc().toIso8601String(),
      });
      return true;
    } catch (e, st) {
      ErrorReporter.report(e, st, contexto: 'Enviar ouvidoria');
      return false;
    }
  }

  /// Relatos de ouvidoria do próprio colaborador (inclui anônimos). Nunca
  /// traz `anotacao_encerramento` (nota interna do RH). Se a coluna
  /// `resposta_colaborador` ainda não existir, repete a consulta sem ela.
  Future<List<Map<String, dynamic>>> listarMeusRelatosOuvidoria() async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return [];
    const base =
        'id, assunto, tipo, ocorrido, anonimo, status, criado_em, anexo_nome';
    for (final cols in [
      // Conjunto completo (igual ao web): anexo e data de encerramento.
      '$base, anexo_url, encerrado_em, resposta_colaborador, resposta_colaborador_em',
      '$base, resposta_colaborador, resposta_colaborador_em',
      base,
    ]) {
      try {
        final data = await _client
            .from('ouvidoria')
            .select(cols)
            .eq('colaborador_id', meuId)
            .order('criado_em', ascending: false);
        return List<Map<String, dynamic>>.from(data as List);
      } catch (_) {/* tenta o próximo conjunto de colunas */}
    }
    return [];
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
    // Ciclos por participante ficam de fora: valem só pros colaboradores
    // listados (ver [buscarCicloAbertoParaColaborador]).
    final abertos = await _carregarCiclosAbertosComEscopo();
    return _escolherCicloAberto(abertos, null, setor);
  }

  /// Ciclos abertos com o escopo já resolvido: participantes (se houver),
  /// setores (coluna `setores` + `setor` do gestor) ou geral.
  Future<List<({Map<String, dynamic> ciclo, Set<int> participantes, Set<String> setores})>>
      _carregarCiclosAbertosComEscopo() async {
    final ciclos = List<Map<String, dynamic>>.from(await _client
        .from('avaliacao_ciclos')
        .select()
        .eq('status', 'aberto')
        .order('criado_em', ascending: false) as List);
    if (ciclos.isEmpty) return [];
    final parts = await _client
        .from('avaliacao_ciclo_participantes')
        .select('ciclo_id, colaborador_id')
        .inFilter('ciclo_id', ciclos.map((c) => c['id']).toList());
    final porCiclo = <int, Set<int>>{};
    for (final p in parts as List) {
      porCiclo
          .putIfAbsent((p['ciclo_id'] as num).toInt(), () => {})
          .add((p['colaborador_id'] as num).toInt());
    }
    return [
      for (final c in ciclos)
        (
          ciclo: c,
          participantes: porCiclo[(c['id'] as num).toInt()] ?? <int>{},
          setores: {
            if ((c['setor'] as String?)?.isNotEmpty ?? false)
              c['setor'] as String,
            ...((c['setores'] as List?)?.cast<String>() ?? const <String>[]),
          },
        )
    ];
  }

  /// Escolhe o ciclo que vale para um colaborador. Prioridade: ciclo só dele
  /// (participantes) > ciclo do setor dele > ciclo geral. [colaboradorId]
  /// nulo ignora os ciclos por participante.
  Map<String, dynamic>? _escolherCicloAberto(
    List<({Map<String, dynamic> ciclo, Set<int> participantes, Set<String> setores})>
        abertos,
    int? colaboradorId,
    String? setor,
  ) {
    // `abertos` já vem do mais recente pro mais antigo.
    if (colaboradorId != null) {
      for (final a in abertos) {
        if (a.participantes.contains(colaboradorId)) return a.ciclo;
      }
    }
    for (final a in abertos) {
      if (a.participantes.isEmpty && setor != null && a.setores.contains(setor)) {
        return a.ciclo;
      }
    }
    for (final a in abertos) {
      if (a.participantes.isEmpty && a.setores.isEmpty) return a.ciclo;
    }
    return null;
  }

  /// Ciclo aberto que vale para um colaborador (ver [_escolherCicloAberto]).
  Future<Map<String, dynamic>?> buscarCicloAbertoParaColaborador({
    required int colaboradorId,
    required String? setor,
  }) async {
    final abertos = await _carregarCiclosAbertosComEscopo();
    return _escolherCicloAberto(abertos, colaboradorId, setor);
  }

  /// Ciclos abertos restritos a colaboradores específicos.
  Future<List<Map<String, dynamic>>> listarCiclosAbertosPorParticipantes() async {
    final abertos = await _carregarCiclosAbertosComEscopo();
    return [
      for (final a in abertos)
        if (a.participantes.isNotEmpty) a.ciclo
    ];
  }

  /// Cria um ciclo (o gestor abre só para o próprio setor; pesos devem somar
  /// 100). Porta de `criarCicloAvaliacao` do gentepole_admin.
  Future<int> criarCicloAvaliacao({
    required String nome,
    DateTime? dataInicio,
    DateTime? dataFim,
    String? setor,
    String? criadoPor,
    String tipoAvaliacao = 'gestor', // 'gestor' | '180' | '360'
    List<String> setores = const [],
    List<int> participantesIds = const [],
    int pesoGestor = 100,
    int pesoColaborador = 0,
    int pesoEquipe = 0,
  }) async {
    if (pesoGestor + pesoColaborador + pesoEquipe != 100) {
      throw ArgumentError('Os pesos precisam somar 100%.');
    }
    if (setor == null && (dataInicio == null || dataFim == null)) {
      throw ArgumentError('Informe a data de início e a data de fim do ciclo.');
    }
    if (dataInicio != null && dataFim != null && dataFim.isBefore(dataInicio)) {
      throw ArgumentError(
          'A data de fim não pode ser anterior à data de início.');
    }
    final res = await _client
        .from('avaliacao_ciclos')
        .insert({
          'nome': nome,
          'data_inicio': dataInicio?.toIso8601String().substring(0, 10),
          'data_fim': dataFim?.toIso8601String().substring(0, 10),
          'setor': setor,
          'criado_por': criadoPor,
          'tipo_avaliacao': tipoAvaliacao,
          'setores': setores.isEmpty ? null : setores,
          'peso_gestor': pesoGestor,
          'peso_colaborador': pesoColaborador,
          'peso_equipe': pesoEquipe,
        })
        .select('id')
        .single();
    final cicloId = res['id'] as int;
    if (participantesIds.isNotEmpty) {
      try {
        await _client.from('avaliacao_ciclo_participantes').insert([
          for (final id in participantesIds.toSet())
            {'ciclo_id': cicloId, 'colaborador_id': id}
        ]);
      } catch (e) {
        // Sem participantes o ciclo viraria geral: desfaz pra não vazar.
        await _client.from('avaliacao_ciclos').delete().eq('id', cicloId);
        rethrow;
      }
    }
    // Avisa os gestores para escolherem as perguntas. Falha no aviso não
    // pode desfazer o ciclo já criado.
    try {
      await _client.rpc('notificar_ciclo_avaliacao_aberto',
          params: {'p_ciclo_id': cicloId});
    } catch (_) {}
    return cicloId;
  }

  Future<void> alterarStatusCiclo(int cicloId, String status) async {
    await _client
        .from('avaliacao_ciclos')
        .update({'status': status}).eq('id', cicloId);
  }

  /// Templates de avaliação (`avaliacao_templates`). [setorColaborador] /
  /// [funcaoColaborador] mantêm só templates daquele setor/função ou
  /// genéricos (nulo). Porta de `listarAvaliacaoTemplates` do admin.
  Future<List<Map<String, dynamic>>> listarAvaliacaoTemplates({
    bool apenasAtivos = false,
    String tipo = 'desempenho',
    String? setorColaborador,
    String? funcaoColaborador,
  }) async {
    var query = _client.from('avaliacao_templates').select().eq('tipo', tipo);
    if (apenasAtivos) query = query.eq('ativo', true);
    final data = await query.order('nome');
    var lista = List<Map<String, dynamic>>.from(data as List);
    if (setorColaborador != null) {
      lista = lista.where((t) {
        final s = t['setor'] as String?;
        return s == null || s == setorColaborador;
      }).toList();
    }
    if (funcaoColaborador != null) {
      lista = lista.where((t) {
        final f = t['funcao'] as String?;
        return f == null || f == funcaoColaborador;
      }).toList();
    }
    return lista;
  }

  Future<List<Map<String, dynamic>>> listarPerguntasDoTemplate(
      int templateId) async {
    final data = await _client
        .from('avaliacao_perguntas')
        .select()
        .eq('template_id', templateId)
        .eq('ativo', true)
        .order('ordem');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Registra a escolha do gestor pra essa avaliação — [templateId] nulo
  /// significa "usar as perguntas padrão da função/setor". Libera as
  /// perguntas (`perguntas_liberadas = true`) pro colaborador e colegas.
  Future<void> definirTemplateDaAvaliacao(int avaliacaoId, int? templateId) async {
    await _client.from('avaliacoes').update({
      'template_id': templateId,
      'perguntas_liberadas': true,
    }).eq('id', avaliacaoId);
  }

  /// Pesos definidos no ciclo (ciclos novos). Chaves via [chavePesoCiclo]
  /// pra conviver no mesmo mapa dos pesos de template; ciclos antigos (pesos
  /// nulos) ficam de fora e caem no peso do template.
  Future<Map<int, Map<String, int>>> buscarPesosCiclos(
      List<int> cicloIds) async {
    if (cicloIds.isEmpty) return {};
    final data = await _client
        .from('avaliacao_ciclos')
        .select('id, peso_gestor, peso_colaborador, peso_equipe')
        .inFilter('id', cicloIds)
        .not('peso_gestor', 'is', null);
    return {
      for (final c in data as List)
        chavePesoCiclo(c['id'] as int): {
          'gestor': c['peso_gestor'] as int,
          'colaborador': c['peso_colaborador'] as int,
          'equipe': c['peso_equipe'] as int,
        }
    };
  }

  /// Convida automaticamente os colegas de setor (exceto o próprio
  /// colaborador) a avaliar como "equipe" num ciclo 360. Idempotente.
  Future<void> gerarAvaliadoresEquipeAutomatico({
    required int avaliacaoId,
    required int colaboradorId,
    required String setor,
  }) async {
    final data = await _client
        .from('colaboradores')
        .select('id')
        .eq('setor', setor)
        .eq('demitido', false);
    final colegas = List<Map<String, dynamic>>.from(data as List)
        .where((c) => c['id'] != colaboradorId)
        .toList();
    if (colegas.isEmpty) return;
    final linhas = colegas
        .map((c) => {
              'avaliacao_id': avaliacaoId,
              'avaliador_id': c['id'].toString(),
            })
        .toList();
    await _client.from('avaliacao_equipe_avaliadores').upsert(linhas,
        onConflict: 'avaliacao_id,avaliador_id', ignoreDuplicates: true);
  }

  /// Busca a avaliação do colaborador nesse ciclo (criando se ainda não
  /// existir) — usado tanto pela autoavaliação quanto pela avaliação do
  /// gestor.
  Future<Map<String, dynamic>?> buscarOuCriarAvaliacao({
    required int cicloId,
    required int colaboradorId,
  }) async {
    await _client
        .from('avaliacoes')
        .upsert(
          {'ciclo_id': cicloId, 'colaborador_id': colaboradorId},
          onConflict: 'ciclo_id,colaborador_id',
          ignoreDuplicates: true,
        );
    return await _client
        .from('avaliacoes')
        .select(
          '*, colaboradores!avaliacoes_colaborador_id_fkey(nome, apelido, cargo, setor, foto_url)',
        )
        .eq('ciclo_id', cicloId)
        .eq('colaborador_id', colaboradorId)
        .maybeSingle();
  }

  /// Libera as perguntas de uma avaliação pra o colaborador (autoavaliação)
  /// e os colegas (equipe/360) responderem. No web isso acontece quando o
  /// gestor escolhe um template (ou "usar perguntas padrão") em
  /// `definirTemplateDaAvaliacao`; este app não tem tela de templates, então
  /// o gestor libera implicitamente ao abrir a avaliação em
  /// [AvaliarEquipeScreen] (equivalente a "usar perguntas padrão").
  Future<void> liberarPerguntasAvaliacao(int avaliacaoId) async {
    await _client
        .from('avaliacoes')
        .update({'perguntas_liberadas': true}).eq('id', avaliacaoId);
  }

  /// Perguntas ativas cadastradas para a função (cargo) informada.
  Future<List<Map<String, dynamic>>> listarPerguntasFuncao(
    String funcao, {
    String? setor,
  }) async {
    // Se há perguntas da função NAQUELE setor, usa só elas (grupo
    // específico); senão cai nas genéricas da função (setor nulo).
    if (setor != null && setor.trim().isNotEmpty) {
      final doSetor = await _client
          .from('avaliacao_perguntas')
          .select()
          .eq('funcao', funcao)
          .eq('setor', setor)
          .eq('ativo', true)
          .order('ordem');
      final lista = List<Map<String, dynamic>>.from(doSetor as List);
      if (lista.isNotEmpty) return lista;
    }
    final data = await _client
        .from('avaliacao_perguntas')
        .select()
        .eq('funcao', funcao)
        .isFilter('setor', null)
        .eq('ativo', true)
        .order('ordem');
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> listarRespostasAvaliacao(
    int avaliacaoId,
  ) async {
    final data = await _client
        .from('avaliacao_respostas')
        .select()
        .eq('avaliacao_id', avaliacaoId);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Avaliações de período de experiência do colaborador informado — porta
  /// de `listarPeriodoExperienciaColaborador` do gentepole_admin. Diferente
  /// do ciclo de Desempenho (por setor, em lote), é criada individualmente
  /// pelo RH e não tem `ciclo_id`.
  Future<List<Map<String, dynamic>>> listarPeriodoExperienciaColaborador(
    int colaboradorId,
  ) async {
    final data = await _client
        .from('avaliacoes')
        .select(
          '*, colaboradores!avaliacoes_colaborador_id_fkey(nome, apelido, cargo, setor, foto_url)',
        )
        .eq('tipo', 'periodo_experiencia')
        .eq('colaborador_id', colaboradorId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Perguntas aplicáveis a uma avaliação — porta de `perguntasDaAvaliacao`
  /// do gentepole_admin. NOTA/SUPOSIÇÃO: o schema deste app não tem tabela de
  /// templates de avaliação (`template_id` em `avaliacoes`), então aqui
  /// sempre cai para as perguntas por função (`listarPerguntasFuncao`),
  /// ignorando `setor` (que também não é usado na consulta atual deste app).
  /// Validar com o time se templates de avaliação também devem existir aqui.
  Future<List<Map<String, dynamic>>> perguntasDaAvaliacao(
    Map<String, dynamic> avaliacao, {
    required String funcao,
    String? setor,
  }) async {
    final templateId = avaliacao['template_id'] as int?;
    if (templateId != null) return listarPerguntasDoTemplate(templateId);
    return listarPerguntasFuncao(funcao, setor: setor);
  }

  /// Todas as avaliações de período de experiência dos colaboradores dos
  /// setores informados — usado pelo gestor pra ver quem tem avaliação
  /// pendente na sua equipe. Porta de `listarPeriodoExperienciaGestor`.
  Future<List<Map<String, dynamic>>> listarPeriodoExperienciaGestor(
    List<String> setores, {
    int? responsavelId,
  }) async {
    if (setores.isEmpty) return [];
    final idsEquipe = await _idsEquipeDoResponsavel(
        setores, responsavelId, 'avaliar_periodo_experiencia_gestor');
    final data = await _client
        .from('avaliacoes')
        .select(
          '*, colaboradores!avaliacoes_colaborador_id_fkey(nome, apelido, cargo, setor, foto_url)',
        )
        .eq('tipo', 'periodo_experiencia')
        .order('criado_em', ascending: false);
    final lista = List<Map<String, dynamic>>.from(data as List);
    return lista.where((a) {
      final setorColab = (a['colaboradores'] as Map?)?['setor'] as String?;
      return setorColab != null &&
          setores.contains(setorColab) &&
          (idsEquipe == null ||
              idsEquipe.contains((a['colaborador_id'] as num?)?.toInt()));
    }).toList();
  }

  /// Mesmas respostas de [listarRespostasAvaliacao], mas já com o texto e a
  /// dimensão da pergunta embutidos — usado para calcular a nota final
  /// ponderada de Período de Experiência.
  Future<List<Map<String, dynamic>>> listarRespostasAvaliacaoComPergunta(
    int avaliacaoId,
  ) async {
    final data = await _client
        .from('avaliacao_respostas')
        .select(
          '*, avaliacao_perguntas!avaliacao_respostas_pergunta_id_fkey(pergunta, dimensao, ordem)',
        )
        .eq('avaliacao_id', avaliacaoId);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Nota final ponderada da avaliação do GESTOR de uma avaliação de
  /// Período de Experiência: sum(nota_i * peso_i) / sum(peso_i), arredondada
  /// pra 1 casa decimal. Cada pergunta tem um peso (`avaliacao_perguntas.peso`,
  /// padrão 1 = peso igual entre todas). Retorna null se o gestor ainda não
  /// respondeu nenhuma pergunta.
  Future<double?> calcularNotaFinalPeriodoExperiencia(int avaliacaoId) async {
    final respostas = await listarRespostasAvaliacaoComPergunta(avaliacaoId);
    final doGestor = respostas.where((r) => r['origem'] == 'gestor');
    var somaPesos = 0;
    var somaValores = 0;
    for (final r in doGestor) {
      final nota = r['nota'] as int?;
      if (nota == null) continue;
      final peso = (r['avaliacao_perguntas'] as Map?)?['peso'] as int? ?? 1;
      somaValores += nota * peso;
      somaPesos += peso;
    }
    if (somaPesos == 0) return null;
    return double.parse((somaValores / somaPesos).toStringAsFixed(1));
  }

  // ─── Banco de Talentos — indicação sem cadastro ─────────────────────────
  // Porta de `eu_crio_oportunidades_colab_screen.dart` (Indicar um currículo)
  // do gentepole_admin. Mesmo bucket `curriculos-indicacoes` e mesma tabela
  // `banco_talentos`; `indicadoPorId` aqui é `int` (id de `colaboradores`
  // neste app), diferente do web que usa `String`.

  /// Upload do currículo anexado numa indicação sem cadastro (fluxo
  /// "Indicar um currículo" dentro de "Eu Crio Oportunidades"). Mesmo padrão
  /// de [uploadAnexoSolicitacao], bucket próprio `curriculos-indicacoes`.
  Future<String> uploadCurriculoIndicacao(
      Uint8List bytes, String nomeArquivo) async {
    final path = '${DateTime.now().millisecondsSinceEpoch}_$nomeArquivo';
    await _client.storage
        .from('curriculos-indicacoes')
        .uploadBinary(path, bytes);
    return _client.storage.from('curriculos-indicacoes').getPublicUrl(path);
  }

  /// Indica alguém para o Banco de Talentos sem que essa pessoa tenha se
  /// cadastrado no portal e sem precisar de vaga aberta — cai direto no
  /// Banco de Talentos (sem `candidato_id`), com nome, tag e currículo
  /// anexado.
  Future<void> indicarSemCadastro({
    required String nomeIndicado,
    required List<String> tags,
    String? filial,
    required String curriculoUrl,
    required String curriculoNome,
    required int indicadoPorId,
    required String indicadoPorNome,
    String? vagaOrigemTitulo,
  }) async {
    final registro = <String, dynamic>{
      'candidato_id': null,
      'nome_indicado': nomeIndicado,
      'tag': tags.isNotEmpty ? tags.first : null, // compat: coluna antiga única
      'tags': tags,
      if (filial != null && filial.isNotEmpty) 'filial': filial,
      'curriculo_url': curriculoUrl,
      'curriculo_nome': curriculoNome,
      // Coluna `indicado_por_id` é `text` no Supabase (mesma tabela do web,
      // que usa String/uuid para colaborador.id) — este app usa `int`, então
      // convertemos explicitamente pra não depender de cast implícito.
      'indicado_por_id': indicadoPorId.toString(),
      'indicado_por_nome': indicadoPorNome,
      'vaga_origem': vagaOrigemTitulo,
      'area': '',
      'areas': <String>[],
      'motivo': 'Indicação via Eu Crio Oportunidades (sem cadastro no portal)',
      'observacoes': '',
    };
    try {
      await _client.from('banco_talentos').insert(registro);
    } catch (_) {
      // Colunas novas (tags/filial) ainda ausentes: grava só o formato antigo.
      registro.remove('tags');
      registro.remove('filial');
      await _client.from('banco_talentos').insert(registro);
    }
  }

  // ─── Solicitações ───────────────────────────────────────────────────────
  // Porta de `solicitacoes_colab_screen.dart` / `solicitacoes_colab_formularios.dart`
  // / `solicitacoes_gestor_screen.dart` do gentepole_admin. Mesma tabela
  // `solicitacoes` do Supabase, mesmo fluxo de status; adaptado apenas para
  // ids `int` (colaboradores/gestor), já que este app usa `int` em vez de
  // `String` para `colaboradores.id`.

  /// Setor que trata cada tipo depois de aberta — usado pra cada fila (DP,
  /// Endomarketing, Performance, RH) só ver o que é da conta dela.
  static const Map<String, String> areaResponsavelPorTipoSolicitacao = {
    'adesao_beneficio': 'dp',
    'incentivo_educacional': 'dp',
    'cracha': 'dp',
    'adiantamento_13': 'dp',
    'swile': 'dp',
    'comunicado_interno': 'endomkt',
    'treinamento': 'performance',
    'moveis_administrativos': 'facilites',
    'rota': 'facilites',
    'uber': 'facilites',
    'uber_fixo': 'facilites',
    'reembolso_sesmt': 'dp',
  };

  Future<String> uploadAnexoSolicitacao(
      Uint8List bytes, String nomeArquivo) async {
    final path = '${DateTime.now().millisecondsSinceEpoch}_$nomeArquivo';
    await _client.storage.from('solicitacoes-anexos').uploadBinary(path, bytes);
    return _client.storage.from('solicitacoes-anexos').getPublicUrl(path);
  }

  Future<void> criarSolicitacao({
    required String tipo,
    required Map<String, dynamic> payload,
    required int abertoPorId,
    required String abertoPorNome,
    required String abertoPorPapel,
    String? setor,
    bool requerAprovacaoGestor = false,
    int? gestorId,
    String? gestorNome,
    Map<String, dynamic>? colunasExtras, // ex.: prazo_fim (Uber comum)
  }) async {
    await _client.from('solicitacoes').insert({
      ...?colunasExtras,
      'tipo': tipo,
      'payload': payload,
      'aberto_por_id': abertoPorId,
      'aberto_por_nome': abertoPorNome,
      'aberto_por_papel': abertoPorPapel,
      'setor': setor,
      'area_responsavel': areaResponsavelPorTipoSolicitacao[tipo] ?? 'rh',
      'requer_aprovacao_gestor': requerAprovacaoGestor,
      'gestor_id': gestorId,
      'gestor_nome': gestorNome,
      'status': requerAprovacaoGestor ? 'pendente_gestor' : 'pendente',
    });
  }

  /// Lista solicitações. Sem filtros, traz tudo. Use [status], [tipo],
  /// [abertoPorId], [gestorId] ou [areaResponsavel] para restringir (fila
  /// do gestor, "minhas solicitações" do colaborador, fila de um setor
  /// específico do RH etc.).
  Future<List<Map<String, dynamic>>> listarSolicitacoes({
    String? status,
    String? tipo,
    int? abertoPorId,
    int? gestorId,
    String? areaResponsavel,
  }) async {
    var query = _client.from('solicitacoes').select();
    if (status != null) query = query.eq('status', status);
    if (tipo != null) query = query.eq('tipo', tipo);
    if (abertoPorId != null) query = query.eq('aberto_por_id', abertoPorId);
    if (gestorId != null) query = query.eq('gestor_id', gestorId);
    if (areaResponsavel != null) {
      query = query.eq('area_responsavel', areaResponsavel);
    }
    final res = await query.order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> atualizarSolicitacao({
    required int id,
    String? status,
    int? responsavelId,
    String? responsavelNome,
  }) async {
    await _client.from('solicitacoes').update({
      if (status != null) 'status': status,
      if (responsavelId != null) 'responsavel_id': responsavelId,
      if (responsavelNome != null) 'responsavel_nome': responsavelNome,
      'atualizado_em': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  /// Gestor aprova: solicitação sai de 'pendente_gestor' e entra na fila
  /// do RH como 'pendente'.
  Future<void> aprovarSolicitacaoGestor(int id) async {
    await _client.from('solicitacoes').update({
      'status': 'pendente',
      'atualizado_em': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  /// Gestor recusa: encerra sem passar pelo RH, registrando o motivo.
  Future<void> recusarSolicitacaoGestor(int id, {String? motivo}) async {
    await _client.from('solicitacoes').update({
      'status': 'recusado_gestor',
      'motivo_recusa_gestor': motivo,
      'atualizado_em': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<Map<int, List<Map<String, dynamic>>>> listarNotasSolicitacoes(
      List<int> solicitacaoIds) async {
    if (solicitacaoIds.isEmpty) return {};
    final res = await _client
        .from('solicitacoes_notas')
        .select()
        .inFilter('solicitacao_id', solicitacaoIds)
        .order('criado_em');
    final porSolicitacao = <int, List<Map<String, dynamic>>>{};
    for (final n in res as List) {
      final map = n as Map<String, dynamic>;
      porSolicitacao
          .putIfAbsent(map['solicitacao_id'] as int, () => [])
          .add(map);
    }
    return porSolicitacao;
  }

  Future<void> adicionarNotaSolicitacao({
    required int solicitacaoId,
    required String texto,
    String? autorNome,
  }) async {
    await _client.from('solicitacoes_notas').insert({
      'solicitacao_id': solicitacaoId,
      'texto': texto,
      if (autorNome != null) 'autor_nome': autorNome,
    });
  }

  /// O solicitante escolhe Frete ou Uber Flash (cotação informada pelo
  /// Facilites). Escolher o mais caro exige justificativa (validado na tela).
  Future<void> escolherCotacaoRota({
    required int id,
    required String escolha, // 'frete' | 'uber_flash'
    String? justificativa,
  }) async {
    await _client.from('solicitacoes').update({
      'escolha_cotacao': escolha,
      'escolha_justificativa': justificativa?.trim(),
      'status': 'em_andamento',
      'atualizado_em': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  /// Gestor pede o cancelamento de um Uber fixo ativo.
  Future<void> solicitarCancelamentoUberFixo(int id) async {
    await _client.from('solicitacoes').update({
      'cancelamento_solicitado_em': DateTime.now().toUtc().toIso8601String(),
      'atualizado_em': DateTime.now().toIso8601String(),
    }).eq('id', id);
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
      // Avaliação é respondida uma vez só: se já existe resposta desse avaliador
      // nesta avaliação, não regrava (o banco também recusa a alteração).
      final jaEnviadas = await _client
          .from('avaliacao_respostas')
          .select('id')
          .eq('avaliacao_id', avaliacaoId)
          .eq('origem', origem)
          .eq('avaliador_id', avaliadorId)
          .limit(1);
      if ((jaEnviadas as List).isNotEmpty) {
        throw Exception('Esta avaliação já foi enviada e não pode ser alterada.');
      }
      final linhas = respostas
          .map(
            (r) => {
              'avaliacao_id': avaliacaoId,
              'pergunta_id': r['perguntaId'],
              'origem': origem,
              'avaliador_id': avaliadorId,
              'nota': r['nota'],
              'comentario': r['comentario'],
            },
          )
          .toList();
      await _client
          .from('avaliacao_respostas')
          .upsert(
            linhas,
            onConflict: 'avaliacao_id,pergunta_id,origem,avaliador_id',
          );
    }

    int media(Iterable<int> notas) {
      if (notas.isEmpty) return 3;
      return (notas.reduce((a, b) => a + b) / notas.length).round().clamp(1, 5);
    }

    if (origem == 'colaborador') {
      final desempenho = media(
        respostas
            .where((r) => r['dimensao'] == 'desempenho')
            .map((r) => r['nota'] as int),
      );
      final potencial = media(
        respostas
            .where((r) => r['dimensao'] == 'potencial')
            .map((r) => r['nota'] as int),
      );
      await _client
          .from('avaliacoes')
          .update({
            'autoavaliacao_desempenho': desempenho,
            'autoavaliacao_potencial': potencial,
            'autoavaliacao_em': DateTime.now().toIso8601String(),
          })
          .eq('id', avaliacaoId);
      // só avança a fila; nunca regride uma avaliação já em andamento/concluída
      await _client
          .from('avaliacoes')
          .update({'status': 'pendente_gestor'})
          .eq('id', avaliacaoId)
          .eq('status', 'pendente_auto');
    } else if (origem == 'gestor') {
      final desempenho = media(
        respostas
            .where((r) => r['dimensao'] == 'desempenho')
            .map((r) => r['nota'] as int),
      );
      final potencial = media(
        respostas
            .where((r) => r['dimensao'] == 'potencial')
            .map((r) => r['nota'] as int),
      );
      await _client
          .from('avaliacoes')
          .update({
            'gestor_id': gestorId ?? avaliadorId,
            'gestor_desempenho': desempenho,
            'gestor_potencial': potencial,
            'gestor_em': DateTime.now().toIso8601String(),
            'status': 'concluida',
          })
          .eq('id', avaliacaoId);
    } else {
      // 'equipe' — recalcula a média com as respostas de TODOS os colegas
      // que já avaliaram essa pessoa nesse ciclo, não só a desse avaliador.
      final comPergunta = await _client
          .from('avaliacao_respostas')
          .select(
            '*, avaliacao_perguntas!avaliacao_respostas_pergunta_id_fkey(dimensao)',
          )
          .eq('avaliacao_id', avaliacaoId);
      final equipeComPergunta = List<Map<String, dynamic>>.from(
        comPergunta as List,
      ).where((r) => r['origem'] == 'equipe');
      final desempenhoEquipe = media(
        equipeComPergunta
            .where(
              (r) => (r['avaliacao_perguntas']?['dimensao']) == 'desempenho',
            )
            .map((r) => r['nota'] as int),
      );
      final potencialEquipe = media(
        equipeComPergunta
            .where(
              (r) => (r['avaliacao_perguntas']?['dimensao']) == 'potencial',
            )
            .map((r) => r['nota'] as int),
      );
      await _client
          .from('avaliacoes')
          .update({
            'equipe_desempenho': desempenhoEquipe,
            'equipe_potencial': potencialEquipe,
            'equipe_em': DateTime.now().toIso8601String(),
          })
          .eq('id', avaliacaoId);
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
    int avaliadorId,
  ) async {
    final data = await _client
        .from('avaliacao_equipe_avaliadores')
        .select(
          '*, avaliacoes(*, colaboradores!avaliacoes_colaborador_id_fkey(nome, apelido, cargo, setor, foto_url))',
        )
        .eq('avaliador_id', avaliadorId)
        .eq('respondido', false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Avaliações da equipe (mesmo setor) de um gestor, num ciclo — cria as
  /// que ainda não existem, para a lista já vir completa. Reusa
  /// [buscarMinhaEquipe] pra obter os colaboradores do setor do gestor.
  Future<List<Map<String, dynamic>>> listarAvaliacoesEquipeGestor({
    required int cicloId,
    required String setor,
    String? tipoAvaliacao,
  }) async {
    // Líder direto: só quem tem o gestor logado como responsável do nível
    // mais próximo (e com a funcionalidade liberada pra ele).
    final equipeCompleta = await buscarEquipeGestorMultiSetor([setor],
        responsavelId: colaboradorAtual?.id,
        apenasLiderDireto: true,
        funcionalidade: 'avaliar_equipe_gestor');
    // Só entra quem tem ESTE como ciclo efetivo (ciclo por participante >
    // ciclo do setor > geral).
    final abertos = await _carregarCiclosAbertosComEscopo();
    final equipe = equipeCompleta.where((c) {
      final efetivo = _escolherCicloAberto(abertos, c['id'] as int?, setor);
      return efetivo != null && efetivo['id'] == cicloId;
    }).toList();
    final resultado = <Map<String, dynamic>>[];
    for (final colab in equipe) {
      final avaliacao = await buscarOuCriarAvaliacao(
        cicloId: cicloId,
        colaboradorId: colab['id'] as int,
      );
      if (avaliacao != null) {
        resultado.add(avaliacao);
        // Ciclo 360: convida automaticamente os colegas de setor.
        if (tipoAvaliacao == '360') {
          await gerarAvaliadoresEquipeAutomatico(
            avaliacaoId: avaliacao['id'] as int,
            colaboradorId: colab['id'] as int,
            setor: setor,
          );
        }
      }
    }
    return resultado;
  }

  /// Verificação leve pra tela de Serviços: true se existe autoavaliação de
  /// Desempenho pendente pro colaborador responder — mesma condição usada em
  /// [AvaliacaoScreen] (ciclo aberto pro setor, tipo de avaliação diferente
  /// de 'gestor', perguntas já liberadas pelo gestor e com pelo menos uma
  /// pergunta cadastrada para a função).
  Future<bool> existeAutoavaliacaoDesempenhoPendente({
    required int colaboradorId,
    required String setor,
    required String funcao,
  }) async {
    final ciclo = await buscarCicloAbertoParaColaborador(
        colaboradorId: colaboradorId, setor: setor);
    if (ciclo == null) return false;
    if ((ciclo['tipo_avaliacao'] as String? ?? 'gestor') == 'gestor') {
      return false;
    }
    final avaliacao = await buscarOuCriarAvaliacao(
      cicloId: ciclo['id'] as int,
      colaboradorId: colaboradorId,
    );
    final liberadas = avaliacao?['perguntas_liberadas'] as bool? ?? false;
    if (avaliacao == null || !liberadas) return false;
    final perguntas =
        await perguntasDaAvaliacao(avaliacao, funcao: funcao, setor: setor);
    return perguntas.isNotEmpty;
  }

  /// Verificação leve pra tela de Serviços: true se existe ao menos uma
  /// avaliação de colega (360) pendente pro colaborador avaliar, já com as
  /// perguntas liberadas pelo gestor — mesma condição usada em
  /// [AvaliarColegasScreen].
  Future<bool> existeAvaliacaoColegaPendente(int avaliadorId) async {
    final todas = await listarAvaliacoesEquipeParaAvaliar(avaliadorId);
    return todas.any((item) =>
        (item['avaliacoes'] as Map?)?['perguntas_liberadas'] as bool? ??
        false);
  }

  /// Cria a avaliação de Período de Experiência de um colaborador usando o
  /// conjunto canônico de perguntas (template ativo do tipo). Devolve false se
  /// ainda não há template cadastrado.
  Future<bool> criarAvaliacaoPeriodoExperiencia(int colaboradorId) async {
    final templates = await _client
        .from('avaliacao_templates')
        .select('id')
        .eq('tipo', 'periodo_experiencia')
        .eq('ativo', true)
        .order('nome')
        .limit(1);
    final lista = List<Map<String, dynamic>>.from(templates as List);
    if (lista.isEmpty) return false;
    await _client.from('avaliacoes').insert({
      'colaborador_id': colaboradorId,
      'tipo': 'periodo_experiencia',
      'template_id': lista.first['id'],
      'perguntas_liberadas': true,
    });
    return true;
  }

  /// Verificação leve pra tela de Serviços: true se existe ao menos uma
  /// avaliação de período de experiência criada pro colaborador — mesma
  /// condição usada em [PeriodoExperienciaScreen].
  Future<bool> existePeriodoExperienciaPendente(int colaboradorId) async {
    final colab = colaboradorAtual;
    if (colab == null) return false;
    return await buscarPesquisaPeriodoExperienciaPendente(colab) != null;
  }

  /// Último dia (de casa) em que ainda vale avaliar o período de experiência:
  /// depois dos 91 dias a folha já efetiva o colaborador e a avaliação se perde.
  /// (Mesmo valor do web: diasLimitePeriodoExperiencia.)
  static const diasLimitePeriodoExperiencia = 91;

  /// Janela em que o marco de [checkpoint] (45 ou 90 dias) está disponível:
  /// de 10 dias antes até 30 dias depois do marco de 45; no de 90, só até o
  /// limite de [diasLimitePeriodoExperiencia] dias de casa. Igual ao web.
  static bool dentroDaJanelaExperiencia(int checkpoint, int diasDesdeAdmissao) {
    final restantes = checkpoint - diasDesdeAdmissao;
    final minimo =
        checkpoint == 90 ? 90 - diasLimitePeriodoExperiencia : -30;
    return restantes >= minimo && restantes <= 10;
  }

  /// Pesquisa "Período de Experiência" pendente pro colaborador: dispara pela
  /// data de admissão (10 dias antes até 30 dias depois do marco de 45; no de 90, até 91 dias de casa
  /// dias) e vale como resposta única pras duas. Não depende de `ativa`, que
  /// só vira true via "Encaminhar" — e esse tipo não tem envio.
  Future<Map<String, dynamic>?> buscarPesquisaPeriodoExperienciaPendente(
      ColaboradorModel colab) async {
    final admissao = DateTime.tryParse(colab.dataAdmissao ?? '');
    if (admissao == null) return null;
    final dias = DateTime.now().difference(admissao).inDays;
    final dentro = [45, 90].any((c) => dentroDaJanelaExperiencia(c, dias));
    if (!dentro) return null;

    final pesquisa = await _client
        .from('pesquisas')
        .select()
        .eq('tipo', 'periodo_experiencia')
        .order('criado_em', ascending: false)
        .limit(1)
        .maybeSingle();
    if (pesquisa == null) return null;

    final jaRespondeu = await _client
        .from('pesquisa_participacoes')
        .select('id')
        .eq('pesquisa_id', pesquisa['id'] as int)
        .eq('colaborador_id', colab.id)
        .eq('colaborador_alvo_id', colab.id)
        .maybeSingle();
    if (jaRespondeu != null) return null;
    return Map<String, dynamic>.from(pesquisa);
  }

  /// Por que [buscarPesquisaPeriodoExperienciaPendente] devolveu nada.
  Future<String> motivoSemPesquisaPeriodoExperiencia(
      ColaboradorModel colab) async {
    final admissao = DateTime.tryParse(colab.dataAdmissao ?? '');
    if (admissao == null) return 'Sua data de admissão não está cadastrada.';
    final dias = DateTime.now().difference(admissao).inDays;
    final dentro = [45, 90].any((c) => dentroDaJanelaExperiencia(c, dias));
    if (!dentro) {
      return 'Você está com $dias dias de admissão. A pesquisa abre 10 dias antes dos marcos de 45 e 90 dias e fica disponível até 30 dias depois do marco de 45 e até 91 dias de casa no de 90.';
    }
    final pesquisa = await _client
        .from('pesquisas')
        .select('id')
        .eq('tipo', 'periodo_experiencia')
        .limit(1)
        .maybeSingle();
    if (pesquisa == null) {
      return 'Nenhuma pesquisa de período de experiência está cadastrada.';
    }
    return 'Você já respondeu a pesquisa de período de experiência. Obrigado!';
  }

  // ─── Performance: PDI (Plano de Desenvolvimento Individual) ─────────────

  /// Verificação leve pra tela de Serviços: true se existe ao menos um plano
  /// de PDI criado pro colaborador — mesma condição usada em [PdiScreen].
  Future<bool> existePdiAtivoPara(int colaboradorId) async {
    final data = await _client
        .from('pdi_grupos')
        .select('id')
        .eq('colaborador_id', colaboradorId)
        .limit(1);
    return (data as List).isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> listarPdiPlanos(int colaboradorId) async {
    final data = await _client
        .from('pdi_planos')
        .select('*, pdi_acoes(*), pdi_termos_compromisso(*)')
        .eq('colaborador_id', colaboradorId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Lista os PDIs (grupos nomeados) do colaborador, com os planos já
  /// aninhados — cada PDI agrupa seus próprios planos de desenvolvimento.
  Future<List<Map<String, dynamic>>> listarPdiGrupos(int colaboradorId) async {
    final data = await _client
        .from('pdi_grupos')
        .select('*, pdi_termos_compromisso(*), pdi_planos(*, pdi_acoes(*))')
        .eq('colaborador_id', colaboradorId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Link único da trilha do PDI na Unipole (cadastrado pelo admin no painel).
  // ── PDI do gestor (compartilhado com o RH, mesmas tabelas do painel web) ──

  /// PDIs (com planos e ações) dos colaboradores informados.
  Future<List<Map<String, dynamic>>> listarPdisDaEquipe(
      List<int> colaboradorIds) async {
    if (colaboradorIds.isEmpty) return [];
    final data = await _client
        .from('pdi_grupos')
        .select('*, pdi_planos(id, tipo, titulo, pdi_acoes(id, status))')
        .inFilter('colaborador_id', colaboradorIds)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Cria um PDI (agrupamento nomeado) pro colaborador.
  Future<int> criarPdiGrupo({
    required int colaboradorId,
    required String titulo,
    String? objetivo,
    String? criadoPor,
  }) async {
    final res = await _client
        .from('pdi_grupos')
        .insert({
          'colaborador_id': colaboradorId,
          'titulo': titulo,
          'objetivo': objetivo,
          'criado_por': criadoPor,
        })
        .select('id')
        .single();
    return res['id'] as int;
  }

  /// Cria um plano dentro de um PDI (modelo novo: título + tipo).
  Future<int> criarPdiPlanoEmGrupo({
    required int colaboradorId,
    required int pdiGrupoId,
    required String titulo,
    required String tipo, // 'tecnico' | 'comportamental'
    String? criadoPor,
  }) async {
    final res = await _client
        .from('pdi_planos')
        .insert({
          'colaborador_id': colaboradorId,
          'pdi_grupo_id': pdiGrupoId,
          'titulo': titulo,
          'tipo': tipo,
          'criado_por': criadoPor,
        })
        .select('id')
        .single();
    return res['id'] as int;
  }

  /// Status da ação marcado pelo gestor. Diferente de
  /// [atualizarStatusAcaoPdi], não dá pontos de gamificação a quem marca — os
  /// pontos são do colaborador dono do PDI.
  Future<void> atualizarStatusAcaoPdiGestor(int acaoId, String status) async {
    await _client.from('pdi_acoes').update({'status': status}).eq('id', acaoId);
  }

  Future<void> excluirPdiPlano(int planoId) async {
    await _client.from('pdi_acoes').delete().eq('plano_id', planoId);
    await _client
        .from('pdi_termos_compromisso')
        .delete()
        .eq('plano_id', planoId);
    await _client.from('pdi_planos').delete().eq('id', planoId);
  }

  /// Exclui um PDI inteiro: planos (e o que depende deles), termos e o grupo.
  Future<void> excluirPdiGrupo(int grupoId) async {
    final planos = await _client
        .from('pdi_planos')
        .select('id')
        .eq('pdi_grupo_id', grupoId);
    for (final p in List<Map<String, dynamic>>.from(planos as List)) {
      await excluirPdiPlano(p['id'] as int);
    }
    await _client
        .from('pdi_termos_compromisso')
        .delete()
        .eq('pdi_grupo_id', grupoId);
    await _client.from('pdi_grupos').delete().eq('id', grupoId);
  }

  /// Upload do termo de compromisso de um PDI (PDF) — o colaborador acessa e
  /// baixa esse arquivo para assinar. Mesmo bucket/tabela do painel web.
  Future<void> criarTermoCompromissoPdi({
    required int pdiGrupoId,
    required Uint8List bytes,
    required String nomeArquivo,
    String? criadoPor,
  }) async {
    final path =
        'pdi_$pdiGrupoId/${DateTime.now().millisecondsSinceEpoch}_$nomeArquivo';
    await _client.storage.from('pdi-termos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final url = _client.storage.from('pdi-termos').getPublicUrl(path);
    await _client.from('pdi_termos_compromisso').insert({
      'pdi_grupo_id': pdiGrupoId,
      'arquivo_url': url,
      'nome_arquivo': nomeArquivo,
      'criado_por': criadoPor,
    });
  }

  Future<void> excluirTermoCompromissoPdi(int termoId) async {
    await _client.from('pdi_termos_compromisso').delete().eq('id', termoId);
  }

  Future<String?> buscarLinkUnipolePdi() async {
    final r = await _client
        .from('pdi_config')
        .select('link_unipole')
        .eq('id', 1)
        .maybeSingle();
    final l = (r?['link_unipole'] as String?)?.trim();
    return (l == null || l.isEmpty) ? null : l;
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
        .update({'status': status})
        .eq('id', planoId);
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
    if (status == 'concluido') PontosBus.notificarGanho();
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
    await _client.storage
        .from('pdi-anexos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final url = _client.storage.from('pdi-anexos').getPublicUrl(path);
    await _client
        .from('pdi_acoes')
        .update({'anexo_url': url, 'anexo_nome': nomeArquivo})
        .eq('id', acaoId);
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
    final ciclo = await buscarCicloAbertoParaColaborador(
        colaboradorId: col.id, setor: col.setor);
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
      'autoavaliacaoPendente':
          (ciclo['tipo_avaliacao'] != 'gestor') &&
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
  /// [itensNotas] mapeia item id -> nota (1-5), um por linha de matriz
  /// (ver [listarItensEmpresaFeedback]) — substitui o antigo item1Nota/
  /// item2Nota fixo, que não suporta mais que 2 itens.
  Future<int> criarFeedbackAvaliacao({
    required int colaboradorId,
    required int autorId,
    required String texto,
    bool anonimo = false,
    bool? presencial,
    String? anotacoesInternas,
    int? modeloId,
    Map<int, int>? itensNotas,
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
          'itens_notas': {
            for (final e in (itensNotas ?? {}).entries) e.key.toString(): e.value
          },
        })
        .select('id')
        .single();
    return res['id'] as int;
  }

  /// Modelos de texto pré-prontos pra facilitar a escrita do feedback.
  Future<List<Map<String, dynamic>>> listarModelosFeedback({
    bool apenasAtivos = false,
  }) async {
    var query = _client.from('feedback_modelos').select();
    if (apenasAtivos) query = query.eq('ativo', true);
    final data = await query.order('ordem');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Solicitações de feedback recebidas pelo colaborador (pendentes ou
  /// todas, conforme [apenasPendentes]) — usado na tela "Feedback" do
  /// módulo Gestão de Equipe pra mostrar os pedidos da equipe.
  Future<List<Map<String, dynamic>>> listarSolicitacoesFeedbackRecebidas(
    int colaboradorId, {
    bool apenasPendentes = false,
  }) async {
    // destinatario_id é text no banco — mesmo motivo do solicitante_id acima.
    var query = _client
        .from('feedback_solicitacoes')
        .select()
        .eq('destinatario_id', colaboradorId.toString());
    if (apenasPendentes) query = query.eq('status', 'pendente');
    final data = await query.order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Feedbacks de avaliação dados por um autor (gestor) à equipe.
  Future<List<Map<String, dynamic>>> listarFeedbacksDadosPor(
    int autorId,
  ) async {
    final data = await _client
        .from('avaliacao_feedbacks')
        .select()
        .eq('autor_id', autorId)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<void> recusarSolicitacaoFeedback(int id) async {
    await _client
        .from('feedback_solicitacoes')
        .update({
          'status': 'recusada',
          'respondido_em': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  Future<void> marcarSolicitacaoFeedbackAtendida(int id, int feedbackId) async {
    await _client
        .from('feedback_solicitacoes')
        .update({
          'status': 'atendida',
          'feedback_id': feedbackId,
          'respondido_em': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
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
    return _comApelidos(List<Map<String, dynamic>>.from(res as List));
  }

  /// Colaboradores admitidos na semana corrente (segunda a domingo) — vira
  /// automaticamente para a próxima semana assim que ela começa.
  Future<List<Map<String, dynamic>>> buscarNovosColaboradoresSemana() async {
    final hoje = DateTime.now();
    final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);
    final inicioSemana = hojeSemHora.subtract(Duration(days: hoje.weekday - 1));
    final fimSemana = inicioSemana.add(const Duration(days: 6));
    // Nunca inclui admissões com data futura (às vezes cadastram a data em
    // que o colaborador vai entrar, que pode ser um dia à frente).
    final limiteSuperior = fimSemana.isBefore(hojeSemHora)
        ? fimSemana
        : hojeSemHora;
    final fmt = (DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final res = await _client
        .from('colaboradores')
        .select('id, nome, apelido, setor, foto_url, data_admissao')
        .eq('demitido', false)
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
    await _client.from('notificacoes_dispensadas').upsert({
      'colaborador_id': meuId,
      'chave': chave,
    }, onConflict: 'colaborador_id,chave');
  }

  /// Colaboradores perto de um marco do período de experiência — porta de
  /// `listarColaboradoresFimExperiencia` do gentepole_admin.
  /// [checkpointDias]: 45 (1ª etapa) ou 90 (etapa final). Entra na lista a
  /// partir de 10 dias antes do marco e continua como atrasado
  /// (`dias_restantes` negativo) por até 30 dias.
  /// [colaboradorId] = aviso do próprio colaborador; [setores] = aviso do
  /// gestor sobre a equipe. [paraGestor] muda o que conta como resolvido:
  /// pro colaborador é ter respondido a pesquisa "Período de Experiência";
  /// pro gestor é ter concluído a avaliação formal (`avaliacoes.gestor_em`).
  Future<List<Map<String, dynamic>>> listarColaboradoresFimExperiencia({
    int? colaboradorId,
    List<String>? setores,
    int checkpointDias = 90,
    bool paraGestor = false,
  }) async {
    var query = _client
        .from('colaboradores')
        .select('id, nome, setor, data_admissao')
        .eq('demitido', false);
    if (colaboradorId != null) {
      query = query.eq('id', colaboradorId);
    } else if (setores != null && setores.isNotEmpty) {
      query = query.inFilter('setor', setores);
    } else {
      return [];
    }
    final data = await query;
    final hoje = DateTime.now();
    final resultado = <Map<String, dynamic>>[];
    // Aviso pro gestor: só a equipe sob ele (líder direto).
    final idsEquipe = (paraGestor && setores != null)
        ? await _idsEquipeDoResponsavel(setores, colaboradorAtual?.id,
            'avaliar_periodo_experiencia_gestor')
        : null;
    for (final c in List<Map<String, dynamic>>.from(data as List)) {
      if (idsEquipe != null && !idsEquipe.contains(c['id'])) continue;
      final admissaoStr = c['data_admissao'] as String?;
      if (admissaoStr == null) continue;
      final admissao = DateTime.tryParse(admissaoStr);
      if (admissao == null) continue;
      final diasDesdeAdmissao = hoje.difference(admissao).inDays;
      final diasRestantes = checkpointDias - diasDesdeAdmissao;
      if (dentroDaJanelaExperiencia(checkpointDias, diasDesdeAdmissao)) {
        resultado.add({
          ...c,
          'dias_restantes': diasRestantes,
          'checkpoint_dias': checkpointDias,
        });
      }
    }
    if (resultado.isEmpty) return resultado;

    final alvoIds = resultado.map((c) => c['id']).toList();
    if (paraGestor) {
      final avaliados = await _client
          .from('avaliacoes')
          .select('colaborador_id')
          .eq('tipo', 'periodo_experiencia')
          .not('gestor_em', 'is', null)
          .inFilter('colaborador_id', alvoIds);
      final jaAvaliados = List<Map<String, dynamic>>.from(avaliados)
          .map((a) => a['colaborador_id'].toString())
          .toSet();
      resultado.removeWhere((c) => jaAvaliados.contains(c['id'].toString()));
    } else {
      final respondenteId = colaboradorAtual?.id;
      final pesquisa = await _client
          .from('pesquisas')
          .select('id')
          .eq('tipo', 'periodo_experiencia')
          .order('criado_em', ascending: false)
          .limit(1)
          .maybeSingle();
      if (pesquisa != null && respondenteId != null) {
        final respondidas = await _client
            .from('pesquisa_participacoes')
            .select('colaborador_alvo_id')
            .eq('pesquisa_id', pesquisa['id'] as int)
            .eq('colaborador_id', respondenteId)
            .inFilter('colaborador_alvo_id', alvoIds);
        final jaRespondidos = List<Map<String, dynamic>>.from(respondidas)
            .map((r) => r['colaborador_alvo_id'].toString())
            .toSet();
        resultado
            .removeWhere((c) => jaRespondidos.contains(c['id'].toString()));
      }
    }

    resultado.sort(
      (a, b) =>
          (a['dias_restantes'] as int).compareTo(b['dias_restantes'] as int),
    );
    return resultado;
  }

  /// Mensagens diretas (`feed_posts` com `destinatario` = `@colaborador:<id>`
  /// ou `@colaborador:<id>|...`) recebidas pelo colaborador logado, de
  /// outra pessoa (exclui o que ele mesmo postou).
  Future<List<Map<String, dynamic>>> listarMensagensDiretasRecebidas({
    int limite = 20,
  }) async {
    final meuId = colaboradorAtual?.id;
    if (meuId == null) return [];
    // O destinatário pode listar várias pessoas ('@colaborador:1,2|NOMES'),
    // então o filtro por id é feito aqui e não no SQL.
    final res = await _client
        .from('feed_posts')
        .select('*, autor:colaboradores!autor_id(nome, foto_url, cargo)')
        .like('destinatario', '@colaborador:%')
        .order('criado_em', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(res as List)
        .where((p) => p['autor_id'] != meuId)
        .where((p) {
          final dest = p['destinatario'] as String? ?? '';
          final ids = dest
              .substring('@colaborador:'.length)
              .split('|')
              .first
              .split(',')
              .map((e) => e.trim());
          return ids.contains(meuId.toString());
        })
        .take(limite)
        .toList();
  }

  /// Posts aprovados dos últimos 30 dias em que o colaborador logado foi
  /// marcado (`@[Nome Completo]`) por outra pessoa e que ele pode ver (para
  /// todos ou o setor dele). Posts endereçados a pessoas já aparecem como
  /// mensagem direta.
  Future<List<Map<String, dynamic>>> listarMencoesRecebidas() async {
    final colab = colaboradorAtual;
    if (colab == null) return [];
    final desde = DateTime.now()
        .subtract(const Duration(days: 30))
        .toUtc()
        .toIso8601String();
    final res = await _client
        .from('feed_posts')
        .select('id, autor_id, conteudo, criado_em, destinatario, '
            'autor:colaboradores!autor_id(nome)')
        .eq('status', 'aprovado')
        .gte('criado_em', desde)
        .ilike('conteudo', '%@[${colab.nome}]%')
        .order('criado_em', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(res as List)
        .where((p) => p['autor_id'].toString() != colab.id.toString())
        .where((p) {
      final dest = p['destinatario'] as String? ?? 'todos';
      if (dest == 'todos' || dest.isEmpty) return true;
      if (dest.startsWith('@setor:')) {
        return dest
            .substring(7)
            .split(',')
            .map((s) => s.trim())
            .contains(colab.setor);
      }
      return false;
    }).toList();
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
            DateTime.tryParse(p['criado_em'] as String? ?? '') ??
            DateTime.now();
        itens.add(
          NotificacaoItem(
            chave: chave,
            tipo: 'pesquisa',
            titulo: 'Pesquisa pendente',
            subtitulo:
                (p['titulo'] as String?) ??
                'Você tem uma pesquisa para responder',
            criadoEm: criadoEm,
          ),
        );
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
        itens.add(
          NotificacaoItem(
            chave: chave,
            tipo: 'mensagem',
            titulo: 'Mensagem de $autorNome',
            subtitulo:
                (m['titulo'] as String?) ??
                (m['conteudo'] as String?) ??
                'Você recebeu uma nova mensagem',
            criadoEm:
                DateTime.tryParse(m['criado_em'] as String? ?? '') ??
                DateTime.now(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao carregar mensagens diretas no sino: $e');
    }

    try {
      final mencoes = await listarMencoesRecebidas();
      for (final m in mencoes) {
        final chave = 'mencao:${m['id']}';
        if (dispensadas.contains(chave)) continue;
        final autor = m['autor'] as Map?;
        final autorNome = autor?['nome'] as String? ?? 'Alguém';
        itens.add(
          NotificacaoItem(
            chave: chave,
            tipo: 'mencao',
            titulo: '$autorNome marcou você em um post',
            subtitulo: (m['conteudo'] as String?) ?? 'Toque para ver o post',
            criadoEm:
                DateTime.tryParse(m['criado_em'] as String? ?? '') ??
                DateTime.now(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao carregar marcações no sino: $e');
    }

    try {
      final parabens = await listarParabensSemResposta();
      for (final p in parabens) {
        final chave = 'parabens:${p['id']}';
        if (dispensadas.contains(chave)) continue;
        final remetente = p['remetente'] as Map?;
        final remetenteNome = remetente?['nome'] as String? ?? 'Alguém';
        itens.add(
          NotificacaoItem(
            chave: chave,
            tipo: 'parabens',
            titulo: 'Parabéns de $remetenteNome',
            subtitulo: (p['mensagem'] as String?) ?? 'Você recebeu um parabéns',
            criadoEm:
                DateTime.tryParse(p['criado_em'] as String? ?? '') ??
                DateTime.now(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao carregar parabéns no sino: $e');
    }

    try {
      final feedbacks = await listarFeedbacksNaoLidos();
      for (final f in feedbacks) {
        final chave = 'fb_recebido:${f['id']}';
        if (dispensadas.contains(chave)) continue;
        itens.add(
          NotificacaoItem(
            chave: chave,
            tipo: 'feedback',
            titulo: 'Novo feedback recebido',
            subtitulo: (f['mensagem'] as String?) ?? 'Você recebeu um feedback',
            criadoEm:
                DateTime.tryParse(f['criado_em'] as String? ?? '') ??
                DateTime.now(),
          ),
        );
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
        itens.add(
          NotificacaoItem(
            chave: chave,
            refId: int.tryParse(s['id'].toString()),
            tipo: 'feedback_solicitacao',
            titulo: 'Solicitação de feedback',
            subtitulo:
                (s['mensagem'] as String?) ?? 'Alguém pediu um feedback seu',
            criadoEm:
                DateTime.tryParse(s['criado_em'] as String? ?? '') ??
                DateTime.now(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao carregar solicitações de feedback no sino: $e');
    }

    try {
      final ehGestor = await verificarSeEhGestor();
      final setoresEquipe =
          ehGestor ? await buscarSetoresEfetivosDoGestor() : <String>[];
      final vistos = <String>{};
      for (final checkpoint in [45, 90]) {
        final listas = await Future.wait([
          listarColaboradoresFimExperiencia(
            colaboradorId: meuId,
            checkpointDias: checkpoint,
          ),
          if (ehGestor && setoresEquipe.isNotEmpty)
            listarColaboradoresFimExperiencia(
              setores: setoresEquipe,
              checkpointDias: checkpoint,
              paraGestor: true,
            ),
        ]);
        for (final lista in listas) {
          for (final c in lista) {
            // Mesma chave do painel web: dispensar num lugar vale no outro.
            final chave = 'periodo_experiencia_$checkpoint:${c['id']}';
            if (!vistos.add(chave) || dispensadas.contains(chave)) continue;
            final dias = c['dias_restantes'] as int;
            final voce = c['id'].toString() == meuId.toString();
            final marco = checkpoint == 45
                ? 'checkpoint dos 45 dias'
                : 'checkpoint dos 90 dias';
            final quem = voce ? 'da sua experiência' : 'da experiência de ${c['nome']}';
            final texto = dias < 0
                ? 'ATRASADO: o $marco $quem passou há ${-dias} ${-dias == 1 ? 'dia' : 'dias'}.'
                : dias == 0
                ? 'Hoje é o $marco $quem.'
                : 'Faltam $dias ${dias == 1 ? 'dia' : 'dias'} para o $marco $quem.';
            itens.add(
              NotificacaoItem(
                chave: chave,
                tipo: voce ? 'experiencia' : 'experiencia_equipe',
                titulo: 'Período de experiência',
                subtitulo: texto,
                criadoEm: DateTime.now(),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar aviso de experiência no sino: $e');
    }

    // Avisos extras (porte de `listarAvisosExtrasColab` do gentepole_admin):
    // elogios, solicitações, candidaturas e atualização cadastral — janela de
    // 30 dias; dispensa pela mesma `chave` do painel web.
    try {
      final extras = await listarAvisosExtrasColab();
      for (final a in extras) {
        final chave = a['chave'] as String;
        if (dispensadas.contains(chave)) continue;
        itens.add(
          NotificacaoItem(
            chave: chave,
            tipo: a['tipo'] as String,
            titulo: a['titulo'] as String,
            subtitulo: a['texto'] as String,
            criadoEm: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao carregar avisos extras no sino: $e');
    }

    itens.sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
    return itens;
  }

  /// Avisos extras do sino (últimos 30 dias): elogio recebido, resposta ao
  /// elogio enviado, andamento/decisão de solicitação, candidaturas e pedido
  /// de atualização cadastral. Cada item: {chave, texto, tipo, titulo}.
  Future<List<Map<String, dynamic>>> listarAvisosExtrasColab() async {
    final colab = colaboradorAtual;
    if (colab == null) return [];
    final meuId = colab.id;
    final avisos = <Map<String, dynamic>>[];
    final desde = DateTime.now()
        .subtract(const Duration(days: 30))
        .toUtc()
        .toIso8601String();
    try {
      final recebidos = await _client
          .from('elogios')
          .select('id, respondido_em, criado_em')
          .eq('colaborador_id', meuId)
          .gte('criado_em', desde);
      for (final e in recebidos as List) {
        if (e['respondido_em'] != null) continue;
        avisos.add({
          'chave': 'elogio:${e['id']}',
          'texto': 'Você recebeu um elogio — vale responder!',
          'tipo': 'elogio',
          'titulo': 'Elogiar',
        });
      }
    } catch (_) {}
    try {
      final enviados = await _client
          .from('elogios')
          .select('id, respondido_em')
          .eq('autor_id', meuId)
          .not('respondido_em', 'is', null)
          .gte('respondido_em', desde);
      for (final e in enviados as List) {
        avisos.add({
          'chave': 'elogio_resp:${e['id']}',
          'texto': 'Alguém respondeu ao elogio que você enviou.',
          'tipo': 'elogio',
          'titulo': 'Elogiar',
        });
      }
    } catch (_) {}
    try {
      final solic = await _client
          .from('solicitacoes')
          .select('id, tipo, status, atualizado_em')
          .eq('aberto_por_id', meuId)
          .not('status', 'in', '(pendente,pendente_gestor)')
          .gte('atualizado_em', desde);
      for (final s in solic as List) {
        avisos.add({
          'chave': 'solic:${s['id']}:${s['status']}',
          'texto': s['status'] == 'aguardando_escolha'
              ? 'O Facilites informou os valores da sua rota — escolha Frete ou Uber Flash.'
              : 'Sua solicitação teve atualização: ${s['status']}.',
          'tipo': 'solicitacao',
          'titulo': 'Solicitações',
        });
      }
    } catch (_) {}
    try {
      final pendentesGestor = await listarCandidaturasPendentesGestor(meuId);
      for (final p in pendentesGestor) {
        avisos.add({
          'chave': 'cand_gestor:${p['id']}',
          'texto':
              '${p['colaborador_nome']} se candidatou à vaga ${p['vaga_titulo'] ?? ''} — aguarda sua aprovação.',
          'tipo': 'candidatura_gestor',
          'titulo': 'Candidaturas',
        });
      }
      final meus = await listarPedidosCandidaturaColab(meuId);
      for (final p in meus) {
        if (p['status'] == 'pendente') continue;
        avisos.add({
          'chave': 'cand_colab:${p['id']}:${p['status']}',
          'texto':
              'Sua candidatura à vaga ${p['vaga_titulo'] ?? ''} foi ${p['status']} pelo gestor.',
          'tipo': 'candidatura_colab',
          'titulo': 'Eu Crio Oportunidades',
        });
      }
    } catch (_) {}
    try {
      final svc = DocumentosCadastraisService.instance;
      final pedidos = await svc.listarPedidosPendentes(meuId.toString());
      for (final p in pedidos) {
        avisos.add({
          'chave': 'cad_pedido:${p['id']}',
          'texto': 'O DP solicitou a atualização do seu cadastro.',
          'tipo': 'cadastro',
          'titulo': 'Atualização cadastral',
        });
      }
      final chave = await svc.lembreteAnualPendente(
        colaboradorId: meuId.toString(),
        dataAdmissao: colab.dataAdmissao,
      );
      if (chave != null) {
        avisos.add({
          'chave': chave,
          'texto':
              'É hora de atualizar seu cadastro (aniversário de empresa): documentos e dependentes.',
          'tipo': 'cadastro',
          'titulo': 'Atualização cadastral',
        });
      }
    } catch (_) {}
    return avisos;
  }

  // ─── Chamados de TI (Azure DevOps) ───────────────────────────────────────
  // Mesmo backend do app admin (gentepole_admin) — tabelas e edge functions
  // compartilham o mesmo projeto Supabase.

  Future<List<Map<String, dynamic>>> listarTiMembros({bool apenasAtivos = true}) async {
    var query = _client.from('ti_membros').select();
    if (apenasAtivos) query = query.eq('ativo', true);
    final res = await query.order('nome');
    return List<Map<String, dynamic>>.from(res);
  }

  /// Opções dos dropdowns do formulário — configuráveis pela tela TI >
  /// Configurações no app admin. [campo] é 'tipo_solicitacao' |
  /// 'departamento' | 'nivel_urgencia'.
  Future<List<Map<String, dynamic>>> listarTiChamadoOpcoes(String campo) async {
    final res = await _client
        .from('ti_chamado_opcoes')
        .select()
        .eq('campo', campo)
        .eq('ativo', true)
        .order('ordem');
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> abrirChamadoAzureTI({
    required String titulo,
    required String descricao,
    required String tipoSolicitacao,
    required String departamento,
    required String nivelUrgencia,
    required String atribuidoPara, // e-mail/login do Azure DevOps
    int? tiMembroId,
    required String solicitanteEmail,
    // Vários anexos, como no web (a edge function aceita `anexos`).
    List<({Uint8List bytes, String nome})> anexos = const [],
  }) async {
    final colab = colaboradorAtual;
    if (colab == null) throw Exception('Colaborador não identificado.');

    final anexosUp = <Map<String, String>>[];
    for (final a in anexos) {
      final path =
          '${DateTime.now().millisecondsSinceEpoch}_${anexosUp.length}_${a.nome}';
      await _client.storage.from('ti-chamados-anexos').uploadBinary(path, a.bytes);
      anexosUp.add({
        'url': _client.storage.from('ti-chamados-anexos').getPublicUrl(path),
        'nome': a.nome,
      });
    }

    final res = await _client.functions.invoke(
      'criar-chamado-azure',
      body: {
        'titulo': titulo.trim(),
        'descricao': descricao.trim(),
        'tipoSolicitacao': tipoSolicitacao,
        'departamento': departamento,
        'nivelUrgencia': nivelUrgencia,
        'atribuidoPara': atribuidoPara,
        'solicitanteNome': colab.nome,
        'solicitanteMatricula': colab.matricula,
        'solicitanteEmail': solicitanteEmail,
        if (anexosUp.isNotEmpty) 'anexos': anexosUp,
        if (tiMembroId != null) 'tiMembroId': tiMembroId,
      },
    );
    final data = res.data as Map<String, dynamic>?;
    if (data == null || data['ok'] != true) {
      throw Exception(data?['error'] ?? 'Erro ao abrir chamado no Azure DevOps');
    }

    final workItemId = data['id'] as int?;
    if (workItemId != null) {
      await _client.from('ti_chamados_colab').insert({
        'colaborador_id': colab.id,
        'matricula': colab.matricula,
        'titulo': titulo.trim(),
        'descricao': descricao.trim(),
        'tipo_solicitacao': tipoSolicitacao,
        'departamento': departamento,
        'nivel_urgencia': nivelUrgencia,
        'azure_work_item_id': workItemId,
        'azure_url': data['url'],
        'atribuido_para': atribuidoPara,
        'solicitante_email': solicitanteEmail,
        if (tiMembroId != null) 'ti_membro_id': tiMembroId,
      });
    }
  }

  Future<List<Map<String, dynamic>>> listarMeusChamadosTI() async {
    final colab = colaboradorAtual;
    if (colab == null) return [];
    final res = await _client
        .from('ti_chamados_colab')
        .select()
        .eq('colaborador_id', colab.id)
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Último e-mail usado pelo colaborador num chamado de TI — guardado no
  /// servidor (não só no aparelho) pra pré-preencher o formulário mesmo
  /// depois de limpar o cache do app ou trocar de aparelho.
  Future<String?> buscarUltimoEmailChamadoTI() async {
    final colab = colaboradorAtual;
    if (colab == null) return null;
    final res = await _client
        .from('ti_chamados_colab')
        .select('solicitante_email')
        .eq('colaborador_id', colab.id)
        .order('criado_em', ascending: false)
        .limit(1)
        .maybeSingle();
    return res?['solicitante_email'] as String?;
  }

  /// Marca o chamado como visto — some a bolinha de "tem novidade" no
  /// card. Chamado quando o colaborador abre o detalhe do chamado.
  Future<void> marcarChamadoTIVisto(int workItemId) async {
    await _client
        .from('ti_chamados_colab')
        .update({'notificacao_pendente': false})
        .eq('azure_work_item_id', workItemId);
  }

  Future<Map<String, dynamic>> buscarStatusChamadosAzure(List<int> workItemIds) async {
    if (workItemIds.isEmpty) return {};
    final res = await _client.functions.invoke('status-chamados-azure', body: {'ids': workItemIds});
    final data = res.data as Map<String, dynamic>?;
    if (data == null || data['ok'] != true) return {};
    return Map<String, dynamic>.from(data['status'] as Map);
  }

  /// Comenta no card do Azure, com vários anexos (como no web; a edge function
  /// aceita `anexos`). Retorna os anexos enviados ({url, nome}).
  Future<List<Map<String, String>>> comentarChamadoAzureTI({
    required int workItemId,
    required String texto,
    List<({Uint8List bytes, String nome})> anexos = const [],
  }) async {
    final colab = colaboradorAtual;
    final autorNome = colab?.nome ?? 'Colaborador';

    final anexosUp = <Map<String, String>>[];
    for (final a in anexos) {
      final path =
          '${DateTime.now().millisecondsSinceEpoch}_${anexosUp.length}_${a.nome}';
      await _client.storage.from('ti-chamados-anexos').uploadBinary(path, a.bytes);
      anexosUp.add({
        'url': _client.storage.from('ti-chamados-anexos').getPublicUrl(path),
        'nome': a.nome,
      });
    }

    final res = await _client.functions.invoke(
      'comentar-chamado-azure',
      body: {
        'workItemId': workItemId,
        'texto': texto.trim(),
        'autorNome': autorNome,
        if (anexosUp.isNotEmpty) 'anexos': anexosUp,
      },
    );
    final data = res.data as Map<String, dynamic>?;
    if (data == null || data['ok'] != true) {
      throw Exception(data?['error'] ?? 'Erro ao comentar no chamado');
    }
    return anexosUp;
  }

  /// Reabre o próprio chamado que está em "Sem Retorno do Usuário": o card
  /// vai para "Validação do Usuário" com a tag "Reaberto" (edge function
  /// 'reabrir-chamado-azure'). Retorna o novo estado e as tags do card.
  Future<({String estado, String tags})> reabrirChamadoAzureTI({
    required int workItemId,
  }) async {
    final res = await _client.functions.invoke(
      'reabrir-chamado-azure',
      body: {
        'workItemId': workItemId,
        'autorNome': colaboradorAtual?.nome ?? 'Colaborador',
      },
    );
    final data = res.data as Map<String, dynamic>?;
    if (data == null || data['ok'] != true) {
      throw Exception(data?['error'] ?? 'Erro ao reabrir o chamado');
    }
    return (
      estado: data['estado'] as String? ?? 'Validação do Usuário',
      tags: data['tags'] as String? ?? 'Reaberto',
    );
  }

  /// Ids (Azure work item) dos chamados já avaliados — usado pra saber
  /// quais chamados concluídos ainda faltam pedir avaliação.
  Future<Set<int>> listarChamadosTIAvaliados(List<int> workItemIds) async {
    if (workItemIds.isEmpty) return {};
    final res = await _client
        .from('ti_chamados_avaliacoes')
        .select('azure_work_item_id')
        .inFilter('azure_work_item_id', workItemIds);
    return List<Map<String, dynamic>>.from(res).map((r) => r['azure_work_item_id'] as int).toSet();
  }

  /// Colaborador avalia o atendimento de um chamado já concluído.
  Future<void> avaliarChamadoTI({
    required int workItemId,
    required int nota,
    String? comentario,
  }) async {
    final colab = colaboradorAtual;
    if (colab == null) throw Exception('Colaborador não identificado.');
    final res = await _client.functions.invoke(
      'avaliar-chamado-azure',
      body: {
        'workItemId': workItemId,
        'colaboradorId': colab.id,
        'nota': nota,
        if (comentario != null && comentario.trim().isNotEmpty) 'comentario': comentario.trim(),
      },
    );
    final data = res.data as Map<String, dynamic>?;
    if (data == null || data['ok'] != true) {
      throw Exception(data?['error'] ?? 'Erro ao enviar avaliação');
    }
  }

  // ─── Meus Veículos ──────────────────────────────────────────────────────
  // Mesma tabela `veiculos` da Portaria no painel web — aqui o colaborador
  // só vê e mexe nos próprios.

  Future<List<VeiculoModel>> listarMeusVeiculos(int colaboradorId) async {
    final res = await _client
        .from('veiculos')
        .select()
        .eq('colaborador_id', colaboradorId)
        .order('placa');
    return (res as List).map((e) => VeiculoModel.fromJson(e)).toList();
  }

  Future<void> criarVeiculo({
    required String placa,
    String tipo = 'carro',
    String? tipoOutro,
    String? modelo,
    String? cor,
    required int colaboradorId,
  }) async {
    await _client.from('veiculos').insert({
      'placa': placa.trim().toUpperCase(),
      'tipo': tipo,
      'tipo_outro': tipo == 'outro' ? tipoOutro : null,
      'modelo': modelo,
      'cor': cor,
      'colaborador_id': colaboradorId,
    });
  }

  Future<void> excluirVeiculo(int id) async {
    await _client.from('veiculos').delete().eq('id', id);
  }

  /// Matriz 9Box fixa: avaliações CONCLUÍDAS do ciclo mais recente de cada
  /// setor (aberto ou fechado), só dos colaboradores dos setores informados.
  Future<List<Map<String, dynamic>>> listarAvaliacoesMatrizEquipe(
      List<String> setores, {int? responsavelId}) async {
    if (setores.isEmpty) return [];
    final idsEquipe = await _idsEquipeDoResponsavel(
        setores, responsavelId, 'avaliar_equipe_gestor');
    final ciclosVistos = <int>{};
    final resultado = <Map<String, dynamic>>[];
    for (final setor in setores) {
      final data = await _client
          .from('avaliacao_ciclos')
          .select('id, setor')
          .or('setor.eq.$setor,setor.is.null')
          .order('criado_em', ascending: false)
          .limit(1);
      final lista = List<Map<String, dynamic>>.from(data as List);
      if (lista.isEmpty) continue;
      final cicloId = lista.first['id'] as int;
      if (!ciclosVistos.add(cicloId)) continue;
      final avs = await _client
          .from('avaliacoes')
          .select(
              '*, colaboradores!avaliacoes_colaborador_id_fkey(nome, apelido, cargo, setor, foto_url)')
          .eq('ciclo_id', cicloId)
          .eq('status', 'concluida');
      resultado.addAll(List<Map<String, dynamic>>.from(avs as List).where((a) =>
          setores.contains((a['colaboradores'] as Map?)?['setor']) &&
          (idsEquipe == null ||
              idsEquipe.contains((a['colaborador_id'] as num?)?.toInt()))));
    }
    return resultado;
  }

  /// Foto do usuário "Gente Pole" (matrícula GENTEPOLE) — avatar dos
  /// comunicados oficiais no feed.
  Future<String?> buscarFotoGentePole() async {
    final r = await _client
        .from('colaboradores')
        .select('foto_url')
        .eq('matricula', 'GENTEPOLE')
        .maybeSingle();
    return r?['foto_url'] as String?;
  }

  Future<Map<int, Map<String, int>>> buscarPesosTemplates(
      List<int> templateIds) async {
    if (templateIds.isEmpty) return {};
    final data = await _client
        .from('avaliacao_templates')
        .select('id, peso_gestor, peso_colaborador, peso_equipe')
        .inFilter('id', templateIds);
    return {
      for (final t in data as List)
        t['id'] as int: {
          'gestor': t['peso_gestor'] as int,
          'colaborador': t['peso_colaborador'] as int,
          'equipe': t['peso_equipe'] as int,
        }
    };
  }

  Future<Map<String, String>> listarNineBoxLegendas() async {
    final data = await _client.from('nine_box_legendas').select();
    return {
      for (final row in List<Map<String, dynamic>>.from(data as List))
        row['chave'] as String: row['texto'] as String? ?? '',
    };
  }
}

/// Um item do sino de notificações — junta categorias bem diferentes
/// (pesquisa, mensagem, parabéns, feedback, experiência) num formato só,
/// suficiente pra desenhar o card e decidir a navegação ao tocar.
class NotificacaoItem {
  final String chave;
  final String
  tipo; // 'pesquisa' | 'mensagem' | 'parabens' | 'feedback' | 'experiencia' |
  // 'feedback_solicitacao' | 'elogio' | 'solicitacao' | 'candidatura_gestor' |
  // 'candidatura_colab' | 'cadastro'
  final String titulo;
  final String subtitulo;
  final DateTime criadoEm;

  /// Id do registro de origem (ex: solicitação de feedback) — usado pelas
  /// ações inline do sino (Atender/Recusar).
  final int? refId;

  NotificacaoItem({
    this.refId,
    required this.chave,
    required this.tipo,
    required this.titulo,
    required this.subtitulo,
    required this.criadoEm,
  });

}
