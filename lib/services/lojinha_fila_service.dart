import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Acompanha os pedidos da Lojinha que estão na fila de integração com o SAP.
/// Consulta de poucos em poucos segundos SÓ enquanto há algo em andamento.
class LojinhaFilaService extends ChangeNotifier {
  LojinhaFilaService._();
  static final LojinhaFilaService instance = LojinhaFilaService._();

  /// Soma 1 cada vez que um pedido da fila é confirmado (as telas recarregam).
  final ValueNotifier<int> confirmacoes = ValueNotifier(0);

  List<Map<String, dynamic>> itens = [];
  final Map<String, String> _ultimoStatus = {};
  final Set<String> _erroDispensado = {};
  Timer? _timer;
  DateTime? _mostrarConfirmadoAte;
  String? _numerosConfirmados;
  String? _cortesConfirmados;
  bool _consultando = false;

  static const _ativos = {'na_fila', 'processando'};

  bool get ativo => itens.any((i) => _ativos.contains(i['status']));
  /// Pedido em erro que o DP ainda não resolveu (reenviar/cancelar). Enquanto
  /// houver, a pessoa não faz novo pedido (independe de dispensar o aviso).
  bool get temErroPendente => itens.any((i) => i['status'] == 'erro');
  bool get temErro => itens.any(
      (i) => i['status'] == 'erro' && !_erroDispensado.contains('${i['id']}'));
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

  void dispensarErro() {
    for (final i in itens) {
      if (i['status'] == 'erro') _erroDispensado.add('${i['id']}');
    }
    notifyListeners();
  }

  String? _colabId;

  /// Chame ao entrar no sistema e logo depois de enviar um pedido.
  void iniciar([String? colaboradorId]) {
    if (colaboradorId != null && colaboradorId.isNotEmpty) _colabId = colaboradorId;
    _consultar();
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
      final confirmadosAgora = <String>[];
      final cortesAgora = <String>[];
      for (final r in rows) {
        final id = '${r['id']}';
        final antes = _ultimoStatus[id];
        final agora = '${r['status']}';
        if (antes != null && _ativos.contains(antes) && agora == 'confirmado') {
          confirmadosAgora.add(
              '${r['numero_pedido'] ?? ''}'.replaceFirst(RegExp(r'^0+'), ''));
          final cs = r['cortes'];
          if (cs is List) {
            for (final c in cs) {
              if (c is! Map) continue;
              final nome = '${c['descricao'] ?? c['produto'] ?? ''}'.trim();
              final saiu = num.tryParse('${c['atendido']}') ?? 0;
              cortesAgora.add(saiu > 0
                  ? '$nome (pediu ${c['solicitado']}, saiu $saiu)'
                  : '$nome (sem estoque, tirado do pedido)');
            }
          }
        }
        _ultimoStatus[id] = agora;
      }
      itens = rows;
      if (confirmadosAgora.isNotEmpty) {
        _numerosConfirmados =
            confirmadosAgora.where((n) => n.isNotEmpty).join(' / ');
        _cortesConfirmados = cortesAgora.isEmpty ? null : cortesAgora.join('; ');
        // Com itens cortados o aviso fica mais tempo na tela.
        _mostrarConfirmadoAte =
            DateTime.now().add(Duration(seconds: cortesAgora.isEmpty ? 14 : 60));
        ApiService().invalidarCacheLojinha();
        confirmacoes.value++;
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

  void parar() {
    _timer?.cancel();
    _timer = null;
    itens = [];
    _ultimoStatus.clear();
    notifyListeners();
  }
}
