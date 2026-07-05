import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/lojinha_model.dart';

typedef ResultadoPedido = ({bool ok, String retorno, List<LojinhaPedidoCentroResult> pedidos});

/// Tela animada de "aguarde" mostrada enquanto o pedido é criado — mesma
/// ideia da versão web (gentepole_admin): uma lista de passos que vai
/// marcando como concluído, terminando em "Quase pronto..." até o pedido
/// (e o valor calculado pelo SAP) estarem realmente prontos.
class LojinhaCriandoPedidoScreen extends StatefulWidget {
  final Future<ResultadoPedido> futuro;
  /// Chamado depois que o pedido é criado com sucesso, antes de fechar essa
  /// tela — espera o SAP terminar de calcular o valor do pedido, pra já
  /// voltar com o valor certo (sem um segundo carregamento visível
  /// mostrando "R$ 0,00" por um instante).
  final Future<void> Function()? aguardarValor;

  const LojinhaCriandoPedidoScreen({
    super.key,
    required this.futuro,
    this.aguardarValor,
  });

  @override
  State<LojinhaCriandoPedidoScreen> createState() => _LojinhaCriandoPedidoScreenState();
}

class _LojinhaCriandoPedidoScreenState extends State<LojinhaCriandoPedidoScreen>
    with TickerProviderStateMixin {
  static const _passos = [
    (Icons.hourglass_top_rounded, 'Aguarde, não feche essa tela'),
    (Icons.verified_user_outlined, 'Validando limite disponível'),
    (Icons.inventory_2_outlined, 'Verificando estoque'),
    (Icons.receipt_long_outlined, 'Criando ordem de venda'),
    (Icons.local_shipping_outlined, 'Dando baixa no estoque'),
    (Icons.celebration_outlined, 'Quase pronto...'),
  ];

  int _passoAtual = 0;
  bool _concluido = false;
  bool _erro = false;
  String? _mensagemErro;
  Timer? _timer;

  late final AnimationController _pulseCtrl;
  late final AnimationController _successCtrl;
  late final Animation<double> _successScale;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = CurvedAnimation(
      parent: _successCtrl,
      curve: Curves.elasticOut,
    );

    _iniciarAnimacao();
    _executar();
  }

  void _iniciarAnimacao() {
    _timer = Timer.periodic(const Duration(milliseconds: 850), (t) {
      if (!mounted || _concluido || _erro) {
        t.cancel();
        return;
      }
      if (_passoAtual < _passos.length - 1) {
        setState(() => _passoAtual++);
      } else {
        t.cancel();
      }
    });
  }

  Future<void> _executar() async {
    try {
      final res = await widget.futuro;
      _timer?.cancel();
      if (!mounted) return;

      if (res.ok) {
        // Fica em "Quase pronto..." (sem passo novo, sem pular pra trás)
        // até o SAP terminar de calcular o valor do pedido — só aí marca
        // como concluído e mostra o check de sucesso.
        setState(() => _passoAtual = _passos.length - 1);
        if (widget.aguardarValor != null) {
          await widget.aguardarValor!();
          if (!mounted) return;
        }
        setState(() => _concluido = true);
        _pulseCtrl.stop();
        _successCtrl.forward();
        await Future.delayed(const Duration(milliseconds: 1800));
        if (mounted) Navigator.pop(context, res);
      } else {
        setState(() {
          _erro = true;
          _mensagemErro = res.retorno;
        });
      }
    } catch (e) {
      _timer?.cancel();
      if (!mounted) return;
      setState(() {
        _erro = true;
        _mensagemErro = 'Erro: $e';
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _concluido || _erro,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: _erro ? _erroView() : _processandoView(),
          ),
        ),
      ),
    );
  }

  Widget _processandoView() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _concluido ? _successScale : _pulseCtrl,
        builder: (_, child) {
          final scale = _concluido ? _successScale.value : 0.92 + 0.08 * _pulseCtrl.value;
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: _concluido
                  ? [AppColors.sucesso.withOpacity(0.3), AppColors.sucesso.withOpacity(0.05)]
                  : [AppColors.laranja.withOpacity(0.25), AppColors.laranja.withOpacity(0.04)],
            ),
            border: Border.all(
              color: _concluido ? AppColors.sucesso : AppColors.laranja,
              width: 2,
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Icon(
              _concluido ? Icons.check_rounded : _passos[_passoAtual].$1,
              key: ValueKey(_concluido ? 'done' : _passoAtual),
              size: 52,
              color: _concluido ? AppColors.sucesso : AppColors.laranja,
            ),
          ),
        ),
      ),
      const SizedBox(height: 48),
      ...List.generate(_passos.length, (i) {
        final done = _concluido || i < _passoAtual;
        final active = !_concluido && i == _passoAtual;

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: i <= _passoAtual || _concluido ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 300),
          builder: (_, opacity, child) => Opacity(opacity: opacity, child: child),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                active
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.laranja,
                        ),
                      )
                    : Icon(
                        done ? Icons.check_circle_rounded : Icons.circle_outlined,
                        size: 16,
                        color: done ? AppColors.sucesso : Colors.white24,
                      ),
                const SizedBox(width: 10),
                Text(
                  _passos[i].$2,
                  style: GoogleFonts.poppins(
                    fontSize: active ? 14 : 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: done
                        ? Colors.white
                        : active
                            ? Colors.white
                            : Colors.white38,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    ]);
  }

  Widget _erroView() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withOpacity(0.12),
              border: Border.all(color: Colors.red, width: 2),
            ),
            child: const Icon(Icons.error_rounded, color: Colors.red, size: 44),
          ),
          const SizedBox(height: 24),
          Text('Erro no pedido',
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 8),
          Text(
            _mensagemErro ?? 'Não foi possível concluir o pedido.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.laranja,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => Navigator.pop(context, (ok: false, retorno: _mensagemErro ?? '', pedidos: <LojinhaPedidoCentroResult>[])),
              child: Text('Fechar', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
