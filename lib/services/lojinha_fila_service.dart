import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Acompanha os pedidos da Lojinha que estão na fila de integração com o SAP.
/// Consulta de poucos em poucos segundos SÓ enquanto há algo em andamento.
///
/// Um envio vira uma linha por organização de vendas (as "partes"), todas com a mesma `chave`. O aviso é por ENVIO:
/// - todas as partes deram certo  -> um único "Pedido realizado com sucesso";
/// - só parte deu certo           -> "parte do pedido foi realizada" (o resto fica com o DP);
/// - nenhuma deu certo            -> a mensagem padrão configurada no painel.
class LojinhaFilaService extends ChangeNotifier {
  LojinhaFilaService._();
  static final LojinhaFilaService instance = LojinhaFilaService._();

  static const _mensagemPadraoFalha =
      'Não conseguimos realizar o seu pedido agora. O DP já foi avisado: entre em contato com o DP. '
      'Novos pedidos ficam bloqueados até o DP resolver.';

  /// Soma 1 cada vez que um envio da fila é confirmado por inteiro (as telas recarregam).
  final ValueNotifier<int> confirmacoes = ValueNotifier(0);

  List<Map<String, dynamic>> itens = [];
  final Map<String, String> _ultimoStatus = {};
  final Set<String> _erroDispensado = {};
  /// Envios (chaves) que vi em andamento e ainda não fechei o resultado.
  final Set<String> _acompanhando = {};
  Timer? _timer;
  DateTime? _mostrarConfirmadoAte;
  DateTime? _aposEnvioAte;
  String? _numerosConfirmados;
  String? _cortesConfirmados;
  String _mensagemFalha = _mensagemPadraoFalha;
  String _tituloFalha = 'Pedido NÃO realizado';
  bool _mensagemCarregada = false;
  bool _consultando = false;

  static const _ativos = {'na_fila', 'processando'};

  bool get ativo => itens.any((i) => _ativos.contains(i['status']));
  /// Pedido em erro que o DP ainda não resolveu (reenviar/cancelar). Enquanto
  /// houver, a pessoa não faz novo pedido (independe de dispensar o aviso).
  bool get temErroPendente => itens.any((i) => i['status'] == 'erro');
  bool get temErro => itens.any(
      (i) => i['status'] == 'erro' && !_erroDispensado.contains('${i['id']}'));

  /// Mensagem padrão (configurada no painel) para quando nenhuma parte do pedido foi realizada.
  String get mensagemFalha => _mensagemFalha;
  String get tituloFalha => _tituloFalha;

  static String _numero(Map<String, dynamic> r) =>
      '${r['numero_pedido'] ?? ''}'.replaceFirst(RegExp(r'^0+'), '');

  /// Números dos pedidos que JÁ deram certo nos envios que também têm parte em erro (null = não houve envio parcial).
  /// Quando não é null, o aviso de erro vira "parte do pedido foi realizada".
  String? get numerosParciais {
    final chavesComErro = <String>{
      for (final i in itens)
        if (i['status'] == 'erro' && !_erroDispensado.contains('${i['id']}')) '${i['chave']}'
    };
    if (chavesComErro.isEmpty) return null;
    final ok = <String>[
      for (final i in itens)
        if (i['status'] == 'confirmado' && chavesComErro.contains('${i['chave']}')) _numero(i)
    ].where((n) => n.isNotEmpty).toSet();
    return ok.isEmpty ? null : ok.join(' / ');
  }

  /// Pedidos que o DP reenviou e já foram integrados, e que a pessoa ainda não
  /// marcou "Entendi" (ficam no cartão mesmo que o app estivesse fechado).
  final Set<String> _vistosLocal = {};
  List<Map<String, dynamic>> get paraEntender => itens
      .where((i) =>
          i['status'] == 'confirmado' &&
          i['reenviado_em'] != null &&
          i['aviso_visto_em'] == null &&
          !_vistosLocal.contains('${i['id']}'))
      .toList();
  bool get temAvisoReenvio => paraEntender.isNotEmpty;

  /// "Entendi": marca os pedidos como vistos (servidor + local) e tira o aviso.
  Future<void> entendi() async {
    final ids = [for (final i in paraEntender) '${i['id']}'];
    _vistosLocal.addAll(ids);
    notifyListeners();
    await ApiService().marcarFilaLojinhaVista(_colabId, ids);
  }

  bool get mostrarConfirmado =>
      _mostrarConfirmadoAte != null &&
      DateTime.now().isBefore(_mostrarConfirmadoAte!);
  String? get numerosConfirmados => _numerosConfirmados;

  /// Itens que o SAP tirou ou reduziu por falta de estoque no último pedido confirmado (null = nenhum).
  String? get cortesConfirmados => _cortesConfirmados;
  /// Em integração E visível: um pedido que o DP reenviou não mostra nada
  /// enquanto não for integrado (a pessoa já foi avisada do erro e não precisa
  /// de outro aviso até haver resultado). Se falhar de novo, volta o aviso de erro.
  bool get ativoVisivel => itens.any(
      (i) => _ativos.contains(i['status']) && i['reenviado_em'] == null);
  bool get visivel =>
      ativoVisivel || temErro || mostrarConfirmado || temAvisoReenvio;

  /// Fecha o aviso de pedido confirmado (o "X" ou o toque que leva a Meus Pedidos).
  void dispensarConfirmado() {
    _mostrarConfirmadoAte = null;
    _numerosConfirmados = null;
    _cortesConfirmados = null;
    notifyListeners();
  }

  void dispensarErro() {
    for (final i in itens) {
      if (i['status'] == 'erro') _erroDispensado.add('${i['id']}');
    }
    notifyListeners();
  }

  String? _colabId;

  /// Chame ao entrar no sistema e logo depois de enviar um pedido ([aposEnvio] = true neste caso: o envio novo
  /// passa a ser acompanhado desde a primeira consulta, mesmo que já venha concluído).
  void iniciar([String? colaboradorId, bool aposEnvio = false]) {
    if (colaboradorId != null && colaboradorId.isNotEmpty) _colabId = colaboradorId;
    if (aposEnvio) _aposEnvioAte = DateTime.now().add(const Duration(minutes: 3));
    _carregarMensagem();
    _consultar();
  }

  Future<void> _carregarMensagem() async {
    if (_mensagemCarregada) return;
    try {
      final m = await ApiService().mensagemErroPedidoLojinha();
      _mensagemCarregada = true;
      var mudou = false;
      if (m.texto != null && m.texto != _mensagemFalha) { _mensagemFalha = m.texto!; mudou = true; }
      if (m.titulo != null && m.titulo != _tituloFalha) { _tituloFalha = m.titulo!; mudou = true; }
      if (mudou) notifyListeners();
    } catch (_) {
      // usa a mensagem padrão embutida; tenta de novo na próxima vez
    }
  }

  void _agendar() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _consultar());
  }

  Future<void> _consultar() async {
    if (_consultando) return;
    _consultando = true;
    try {
      final rows = await ApiService().minhaFilaLojinha(_colabId);
      final acompanharNovos = _aposEnvioAte != null && DateTime.now().isBefore(_aposEnvioAte!);
      for (final r in rows) {
        final id = '${r['id']}';
        final chave = '${r['chave']}';
        final antes = _ultimoStatus[id];
        final agora = '${r['status']}';
        if (antes != null && _ativos.contains(antes)) _acompanhando.add(chave);
        // Linha nova logo depois de enviar (pode já ter terminado na primeira consulta).
        if (antes == null && acompanharNovos && r['reenviado_em'] == null) _acompanhando.add(chave);
        _ultimoStatus[id] = agora;
      }
      itens = rows;

      // Fecha o resultado de cada envio só quando NENHUMA parte dele está mais em andamento.
      for (final chave in _acompanhando.toList()) {
        final partes = rows.where((r) => '${r['chave']}' == chave).toList();
        if (partes.isEmpty) {
          _acompanhando.remove(chave);
          continue;
        }
        if (partes.any((p) => _ativos.contains(p['status']))) continue;
        _acompanhando.remove(chave);
        if (partes.every((p) => p['status'] == 'confirmado')) {
          _anunciarEnvioConfirmado(partes);
        }
        // Parte (ou tudo) em erro: o aviso de erro já aparece sozinho (temErro / numerosParciais).
      }
      notifyListeners();
      if (ativo) {
        if (_timer == null || !_timer!.isActive) _agendar();
      } else if (!mostrarConfirmado) {
        _timer?.cancel();
        _timer = null;
      } else if (_timer == null || !_timer!.isActive) {
        _agendar();
      }
    } catch (_) {
      // sem rede agora: tenta de novo no próximo ciclo
    } finally {
      _consultando = false;
    }
  }

  /// Todas as partes do envio deram certo: um único aviso.
  void _anunciarEnvioConfirmado(List<Map<String, dynamic>> partes) {
    final numeros = <String>{for (final p in partes) _numero(p)}.where((n) => n.isNotEmpty).toList();
    final cortes = <String>[];
    for (final p in partes) {
      final cs = p['cortes'];
      if (cs is! List) continue;
      for (final c in cs) {
        if (c is! Map) continue;
        final nome = '${c['descricao'] ?? c['produto'] ?? ''}'.trim();
        final saiu = num.tryParse('${c['atendido']}') ?? 0;
        cortes.add(saiu > 0
            ? '$nome (pediu ${c['solicitado']}, saiu $saiu)'
            : '$nome (sem estoque, tirado do pedido)');
      }
    }
    _numerosConfirmados = numeros.join(' / ');
    _cortesConfirmados = cortes.isEmpty ? null : cortes.join('; ');
    // Com itens cortados o aviso fica mais tempo na tela.
    _mostrarConfirmadoAte = DateTime.now().add(Duration(seconds: cortes.isEmpty ? 14 : 60));
    ApiService().invalidarCacheLojinha();
    confirmacoes.value++;
  }

  void parar() {
    _timer?.cancel();
    _timer = null;
    itens = [];
    _ultimoStatus.clear();
    _acompanhando.clear();
    notifyListeners();
  }
}
