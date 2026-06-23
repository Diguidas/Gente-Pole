import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/lojinha_model.dart';
import 'lojinha_pedido_detalhe_screen.dart';

class LojinhaPedidosScreen extends StatelessWidget {
  final List<LojinhaPedidoResumoModel> pedidos;

  const LojinhaPedidosScreen({super.key, required this.pedidos});

  @override
  Widget build(BuildContext context) {
    int _desc(LojinhaPedidoResumoModel a, LojinhaPedidoResumoModel b) =>
        b.criacao.compareTo(a.criacao);

    final vigentes  = pedidos.where((p) => p.isVigente).toList()..sort(_desc);
    final futuros   = pedidos.where((p) => p.isFuturo).toList()..sort(_desc);
    final historico = pedidos.where((p) => !p.isVigente && !p.isFuturo).toList()..sort(_desc);

    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 180,
            decoration: const BoxDecoration(gradient: AppColors.gradientePrincipal),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Header ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Meus Pedidos',
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700)),
                          Text(
                              '${pedidos.length} pedido${pedidos.length != 1 ? 's' : ''} no total',
                              style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Lista agrupada ─────────────────────────────────────
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                        color: Color(0xFFF8F9FC),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
                    child: pedidos.isEmpty
                        ? _vazio()
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                            children: [
                              if (vigentes.isNotEmpty) ...[
                                _GrupoHeader(
                                  icone: Icons.radio_button_checked_rounded,
                                  label: 'Sendo descontado',
                                  cor: Colors.green.shade600,
                                  descricao: 'Pedidos que estão sendo cobrados no seu salário agora.',
                                ),
                                const SizedBox(height: 10),
                                ...vigentes.map((p) => _CardPedido(pedido: p)),
                                const SizedBox(height: 24),
                              ],
                              if (futuros.isNotEmpty) ...[
                                _GrupoHeader(
                                  icone: Icons.schedule_rounded,
                                  label: 'Próximos descontos',
                                  cor: Colors.blue.shade600,
                                  descricao: 'Pedidos que serão descontados nos próximos meses.',
                                ),
                                const SizedBox(height: 10),
                                ...futuros.map((p) => _CardPedido(pedido: p)),
                                const SizedBox(height: 24),
                              ],
                              if (historico.isNotEmpty) ...[
                                _GrupoHeader(
                                  icone: Icons.history_rounded,
                                  label: 'Histórico',
                                  cor: Colors.grey.shade500,
                                  descricao: 'Pedidos já encerrados ou finalizados.',
                                ),
                                const SizedBox(height: 10),
                                ...historico.map((p) => _CardPedido(pedido: p)),
                              ],
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vazio() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.receipt_long_rounded,
              size: 60, color: AppColors.cinzaTexto.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text('Nenhum pedido ainda',
              style: GoogleFonts.poppins(color: AppColors.cinzaTexto, fontSize: 14)),
        ]),
      );
}

class _GrupoHeader extends StatelessWidget {
  final IconData icone;
  final String label;
  final Color cor;
  final String descricao;

  const _GrupoHeader({
    required this.icone,
    required this.label,
    required this.cor,
    required this.descricao,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cor)),
                Text(descricao,
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: cor.withOpacity(0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardPedido extends StatelessWidget {
  final LojinhaPedidoResumoModel pedido;
  const _CardPedido({required this.pedido});

  Color get _corSituacao {
    if (pedido.isVigente) return Colors.green.shade600;
    if (pedido.isFuturo)  return Colors.blue.shade600;
    return Colors.grey.shade500;
  }

  Color get _corFundoSituacao {
    if (pedido.isVigente) return Colors.green.shade50;
    if (pedido.isFuturo)  return Colors.blue.shade50;
    return Colors.grey.shade100;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => LojinhaPedidoDetalheScreen(ordem: pedido.ordem)),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                        color: _corSituacao.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.receipt_rounded,
                        color: _corSituacao, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pedido nº ${pedido.ordem}',
                              style: GoogleFonts.poppins(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                          Text(pedido.criacaoFormatada,
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: AppColors.cinzaTexto)),
                        ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(
                      'R\$ ${pedido.valorTotal.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _corSituacao),
                    ),
                    const SizedBox(height: 2),
                    Icon(Icons.chevron_right_rounded,
                        color: AppColors.cinzaTexto, size: 18),
                  ]),
                ],
              ),
              if (pedido.status.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _corFundoSituacao,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _corSituacao.withOpacity(0.25)),
                  ),
                  child: Text(
                    pedido.status,
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _corSituacao),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
