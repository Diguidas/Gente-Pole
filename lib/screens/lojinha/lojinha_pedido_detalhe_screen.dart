import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/lojinha_model.dart';
import '../../services/api_service.dart';

class LojinhaPedidoDetalheScreen extends StatefulWidget {
  final String ordem;

  const LojinhaPedidoDetalheScreen({super.key, required this.ordem});

  @override
  State<LojinhaPedidoDetalheScreen> createState() =>
      _LojinhaPedidoDetalheScreenState();
}

class _LojinhaPedidoDetalheScreenState
    extends State<LojinhaPedidoDetalheScreen> {
  final _api = ApiService();
  LojinhaPedidoDetalheModel? _detalhe;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() { _carregando = true; _erro = null; });
    final result = await _api.buscarItensPedido(widget.ordem);
    setState(() {
      _detalhe = result;
      _erro = result == null ? 'Não foi possível carregar o pedido.' : null;
      _carregando = false;
    });
  }

  String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

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
                // ── Header ──────────────────────────────────────────────
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pedido nº ${widget.ordem}',
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            if (_detalhe != null)
                              Text(
                                'Faturado em ${_detalhe!.dtFaturamentoFormatada}',
                                style: GoogleFonts.poppins(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _carregar,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.refresh_rounded,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Corpo ────────────────────────────────────────────────
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                        color: Color(0xFFF8F9FC),
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(28))),
                    child: _carregando
                        ? const Center(child: CircularProgressIndicator())
                        : _erro != null
                            ? _erroWidget()
                            : _conteudo(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _erroWidget() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded,
              size: 52, color: AppColors.cinzaTexto.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(_erro!,
              style: GoogleFonts.poppins(
                  color: AppColors.cinzaTexto, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _carregar,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.laranja,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child:
                Text('Tentar novamente', style: GoogleFonts.poppins()),
          ),
        ]),
      );

  Widget _conteudo() {
    final d = _detalhe!;
    final totalPedido =
        d.itens.fold(0.0, (s, i) => s + i.valorTotal);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Info do pedido ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ]),
          child: Column(children: [
            _infoRow('Plataforma', d.plataforma),
            if (d.pedidoExterno.isNotEmpty)
              _infoRow('Pedido externo', d.pedidoExterno),
            _infoRow('Faturamento', d.dtFaturamentoFormatada),
            _infoRow('Total de itens', '${d.itens.length}'),
          ]),
        ),

        const SizedBox(height: 20),

        Text('Itens do pedido',
            style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.cinzaTexto,
                letterSpacing: 0.3)),

        const SizedBox(height: 10),

        // ── Itens ────────────────────────────────────────────────────
        ...d.itens.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3))
                  ]),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                        color: AppColors.laranja.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.inventory_2_outlined,
                        color: AppColors.laranja, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.denominacao,
                            style: GoogleFonts.poppins(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          '${item.quantidade.toStringAsFixed(0)} ${item.unidadeVenda} × ${_moeda(item.valorUnitario)}',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: AppColors.cinzaTexto),
                        ),
                        if (item.recusa.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text('Recusa: ${item.recusa}',
                                style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: Colors.red.shade600)),
                          ),
                        ],
                        if (item.notificacoes.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(item.notificacoes,
                              style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: AppColors.cinzaTexto)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_moeda(item.valorTotal),
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.laranja)),
                ],
              ),
            )),

        const SizedBox(height: 8),

        // ── Total ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
              gradient: AppColors.gradientePrincipal,
              borderRadius: BorderRadius.circular(16)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total do pedido',
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 14)),
              Text(_moeda(totalPedido),
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _infoRow(String label, String valor) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Text('$label: ',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.cinzaTexto)),
            Expanded(
              child: Text(valor,
                  style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}