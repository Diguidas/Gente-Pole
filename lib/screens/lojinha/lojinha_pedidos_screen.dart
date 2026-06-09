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
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 180,
            decoration: const BoxDecoration(
                gradient: AppColors.gradientePrincipal),
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
                              '${pedidos.length} pedido${pedidos.length != 1 ? 's' : ''} realizados',
                              style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Lista ───────────────────────────────────────────────
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                        color: Color(0xFFF8F9FC),
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(28))),
                    child: pedidos.isEmpty
                        ? _vazio()
                        : ListView.separated(
                            padding: const EdgeInsets.all(20),
                            itemCount: pedidos.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) =>
                                _CardPedido(pedido: pedidos[i]),
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
              style: GoogleFonts.poppins(
                  color: AppColors.cinzaTexto, fontSize: 14)),
        ]),
      );
}

class _CardPedido extends StatelessWidget {
  final LojinhaPedidoResumoModel pedido;
  const _CardPedido({required this.pedido});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                LojinhaPedidoDetalheScreen(ordem: pedido.ordem)),
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
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                  color: AppColors.laranja.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.receipt_rounded,
                  color: AppColors.laranja, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pedido nº ${pedido.ordem}',
                        style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(pedido.criacaoFormatada,
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.cinzaTexto)),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                'R\$ ${pedido.valorTotal.toStringAsFixed(2).replaceAll('.', ',')}',
                style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.laranja),
              ),
              const SizedBox(height: 2),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.cinzaTexto, size: 18),
            ]),
          ],
        ),
      ),
    );
  }
}