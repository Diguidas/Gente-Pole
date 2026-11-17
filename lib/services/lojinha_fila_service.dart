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
  bool _consultando = false;

  static const _ativos = {'na_fila', 'processando'};

  bool get ativo => itens.any((i) => _ativos.contains(i['status']));
  bool get temErro => itens.any(
      (i) => i['status'] == 'erro' && !_erroDispensado.contains('${i['id']}'));
  bool get mostrarConfirmado =>
      _mostrarConfirmadoAte != null &&
      DateTime.now().isBefore(_mostrarConfirmadoAte!);
  String? get numerosConfirmados => _numerosConfirmados;
  bool get visivel => ativo || temErro || mostrarConfirmado;

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
      for (final r in rows) {
        final id = '${r['id']}';
        final antes = _ultimoStatus[id];
        final agora = '${r['status']}';
        if (antes != null && _ativos.contains(antes) && agora == 'confirmado') {
          confirmadosAgora.add(
              '${r['numero_pedido'] ?? ''}'.replaceFirst(RegExp(r'^0+'), ''));
        }
        _ultimoStatus[id] = agora;
      }
      itens = rows;
      if (confirmadosAgora.isNotEmpty) {
        _numerosConfirmados =
            confirmadosAgora.where((n) => n.isNotEmpty).join(' / ');
        _mostrarConfirmadoAte = DateTime.now().add(const Duration(seconds: 14));
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
