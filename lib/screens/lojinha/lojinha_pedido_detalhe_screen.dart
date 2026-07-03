import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import '../../models/lojinha_model.dart';
import '../../services/api_service.dart';

class LojinhaPedidoDetalheScreen extends StatefulWidget {
  final String ordem;
  /// Data de criação do pedido (yyyyMMdd). Quando fornecida, exibe a tag de entrega.
  final String? criacao;
  /// Número do documento (DOCNUM) para download da nota fiscal, se disponível.
  final String? docnum;
  /// Quando preenchidos, indica que é uma compra de produto exclusivo (fora
  /// do SAP) — não há itens/API para consultar, os dados já vêm prontos.
  final String? descricaoExclusivo;
  final int? quantidadeExclusivo;
  final double? valorExclusivo;

  const LojinhaPedidoDetalheScreen({
    super.key,
    required this.ordem,
    this.criacao,
    this.docnum,
    this.descricaoExclusivo,
    this.quantidadeExclusivo,
    this.valorExclusivo,
  });

  bool get isExclusivo => descricaoExclusivo != null;

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
  bool _baixandoNota = false;

  @override
  void initState() {
    super.initState();
    if (widget.isExclusivo) {
      _carregando = false;
    } else {
      _carregar();
    }
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

  Future<void> _baixarNotaFiscal() async {
    if (widget.docnum == null || widget.docnum!.isEmpty) return;
    setState(() => _baixandoNota = true);
    final url = await _api.buscarDanfeUrlPorDocnum(widget.docnum!);
    if (!mounted) return;
    setState(() => _baixandoNota = false);
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nota fiscal ainda não disponível.',
            style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Não foi possível abrir a nota fiscal.',
            style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

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
                            Text(
                                widget.isExclusivo
                                    ? widget.descricaoExclusivo!
                                    : 'Pedido nº ${widget.ordem}',
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
                      if (!widget.isExclusivo)
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
                    child: widget.isExclusivo
                        ? _conteudoExclusivo()
                        : _carregando
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

  Widget _conteudoExclusivo() {
    final valor = widget.valorExclusivo ?? 0;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.teal.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.storefront_outlined,
                  color: Colors.teal, size: 18),
              const SizedBox(width: 8),
              Text('Produto exclusivo',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal.shade700)),
            ],
          ),
        ),
        const SizedBox(height: 14),
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.storefront_outlined,
                    color: Colors.teal, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.descricaoExclusivo ?? '',
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Quantidade: ${widget.quantidadeExclusivo}',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.cinzaTexto)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(_moeda(valor),
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.laranja)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
              gradient: AppColors.gradientePrincipal,
              borderRadius: BorderRadius.circular(16)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total da compra',
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 14)),
              Text(_moeda(valor),
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

  Widget _conteudo() {
    final d = _detalhe!;
    final totalPedido = d.itens.fold(0.0, (s, i) => s + i.valorTotal);

    // Tag de entrega (calculada a partir da criação, se disponível)
    String? labelEntrega;
    if (widget.criacao != null) {
      // Reutiliza a lógica do model criando um resumo temporário
      final resumo = LojinhaPedidoResumoModel(
        ordem: d.ordem,
        criacao: widget.criacao!,
        valorTotal: totalPedido,
        situacao: 'VIGENTE',
        status: '',
      );
      labelEntrega = resumo.labelEntrega;
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Tag de entrega ───────────────────────────────────────────
        if (labelEntrega != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.laranja.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.laranja.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.local_shipping_outlined,
                    color: AppColors.laranja, size: 18),
                const SizedBox(width: 8),
                Text(labelEntrega,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.laranja)),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

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

        if (widget.docnum != null && widget.docnum!.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _baixandoNota ? null : _baixarNotaFiscal,
              icon: _baixandoNota
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.laranja),
                    )
                  : const Icon(Icons.file_download_outlined,
                      color: AppColors.laranja, size: 20),
              label: Text('Baixar nota fiscal',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.laranja)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.laranja),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],

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