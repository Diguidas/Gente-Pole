import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import '../../models/lojinha_model.dart';
import '../../services/api_service.dart';
import 'lojinha_pedido_detalhe_screen.dart';

enum _Filtro { cobradoAgora, aCobrar, historico }

class LojinhaPedidosScreen extends StatefulWidget {
  final List<LojinhaPedidoResumoModel> pedidos;

  const LojinhaPedidosScreen({super.key, required this.pedidos});

  @override
  State<LojinhaPedidosScreen> createState() => _LojinhaPedidosScreenState();
}

class _LojinhaPedidosScreenState extends State<LojinhaPedidosScreen> {
  final _ativos = <_Filtro>{_Filtro.cobradoAgora, _Filtro.aCobrar, _Filtro.historico};

  int _desc(LojinhaPedidoResumoModel a, LojinhaPedidoResumoModel b) =>
      b.dataOrdenacao.compareTo(a.dataOrdenacao);

  List<LojinhaPedidoResumoModel> get _vigentes =>
      widget.pedidos.where((p) => p.isVigente).toList()..sort(_desc);
  List<LojinhaPedidoResumoModel> get _futuros =>
      widget.pedidos.where((p) => p.isFuturo).toList()..sort(_desc);
  List<LojinhaPedidoResumoModel> get _historico =>
      widget.pedidos.where((p) => !p.isVigente && !p.isFuturo).toList()..sort(_desc);

  void _toggle(_Filtro f) => setState(() {
        if (_ativos.contains(f)) {
          if (_ativos.length > 1) _ativos.remove(f);
        } else {
          _ativos.add(f);
        }
      });

  @override
  Widget build(BuildContext context) {
    final mostrarVigentes  = _ativos.contains(_Filtro.cobradoAgora);
    final mostrarFuturos   = _ativos.contains(_Filtro.aCobrar);
    final mostrarHistorico = _ativos.contains(_Filtro.historico);

    final visiveis = [
      if (mostrarVigentes)  ..._vigentes,
      if (mostrarFuturos)   ..._futuros,
      if (mostrarHistorico) ..._historico,
    ];

    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 200,
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
                              '${widget.pedidos.length} pedido${widget.pedidos.length != 1 ? 's' : ''} no total',
                              style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ── Filtros ────────────────────────────────────────────
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _Chip(
                        label: 'Sendo cobrado',
                        icone: Icons.radio_button_checked_rounded,
                        cor: Colors.green.shade600,
                        ativo: _ativos.contains(_Filtro.cobradoAgora),
                        onTap: () => _toggle(_Filtro.cobradoAgora),
                        count: _vigentes.length,
                      ),
                      const SizedBox(width: 8),
                      _Chip(
                        label: 'A cobrar',
                        icone: Icons.schedule_rounded,
                        cor: Colors.blue.shade600,
                        ativo: _ativos.contains(_Filtro.aCobrar),
                        onTap: () => _toggle(_Filtro.aCobrar),
                        count: _futuros.length,
                      ),
                      const SizedBox(width: 8),
                      _Chip(
                        label: 'Histórico',
                        icone: Icons.history_rounded,
                        cor: Colors.grey.shade500,
                        ativo: _ativos.contains(_Filtro.historico),
                        onTap: () => _toggle(_Filtro.historico),
                        count: _historico.length,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── Lista ──────────────────────────────────────────────
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                        color: Color(0xFFF8F9FC),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
                    child: visiveis.isEmpty
                        ? _vazio()
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                            children: [
                              if (mostrarVigentes && _vigentes.isNotEmpty) ...[
                                _GrupoHeader(
                                  icone: Icons.radio_button_checked_rounded,
                                  label: 'Sendo descontado',
                                  cor: Colors.green.shade600,
                                  descricao: 'Pedidos que estão sendo cobrados no seu salário agora.',
                                ),
                                const SizedBox(height: 10),
                                ..._vigentes.map((p) => _CardPedido(pedido: p)),
                                const SizedBox(height: 24),
                              ],
                              if (mostrarFuturos && _futuros.isNotEmpty) ...[
                                _GrupoHeader(
                                  icone: Icons.schedule_rounded,
                                  label: 'Próximos descontos',
                                  cor: Colors.blue.shade600,
                                  descricao: 'Pedidos que serão descontados nos próximos meses.',
                                ),
                                const SizedBox(height: 10),
                                ..._futuros.map((p) => _CardPedido(pedido: p)),
                                const SizedBox(height: 24),
                              ],
                              if (mostrarHistorico && _historico.isNotEmpty) ...[
                                _GrupoHeader(
                                  icone: Icons.history_rounded,
                                  label: 'Histórico',
                                  cor: Colors.grey.shade500,
                                  descricao: 'Pedidos já encerrados ou finalizados.',
                                ),
                                const SizedBox(height: 10),
                                ..._historico.map((p) => _CardPedido(pedido: p)),
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
          Text('Nenhum pedido encontrado',
              style: GoogleFonts.poppins(color: AppColors.cinzaTexto, fontSize: 14)),
        ]),
      );
}

// ── Chip de filtro ─────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final IconData icone;
  final Color cor;
  final bool ativo;
  final VoidCallback onTap;
  final int count;

  const _Chip({
    required this.label,
    required this.icone,
    required this.cor,
    required this.ativo,
    required this.onTap,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ativo ? cor : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: ativo ? cor : Colors.white.withOpacity(0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: Colors.white, size: 13),
            const SizedBox(width: 5),
            Text(label,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$count',
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Cabeçalho de grupo ─────────────────────────────────────────────────────────

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

// ── Card de pedido ─────────────────────────────────────────────────────────────

class _CardPedido extends StatefulWidget {
  final LojinhaPedidoResumoModel pedido;
  const _CardPedido({required this.pedido});

  @override
  State<_CardPedido> createState() => _CardPedidoState();
}

class _CardPedidoState extends State<_CardPedido> {
  final _api = ApiService();
  bool _baixandoNota = false;

  LojinhaPedidoResumoModel get pedido => widget.pedido;

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

  Future<void> _baixarNotaFiscal() async {
    setState(() => _baixandoNota = true);
    final url = await _api.buscarDanfeUrlPorDocnum(pedido.docnum);
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
    final labelEntrega = pedido.labelEntrega;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => LojinhaPedidoDetalheScreen(
                    ordem: pedido.ordem,
                    criacao: pedido.criacao,
                    docnum: pedido.docnum,
                    descricaoExclusivo: pedido.descricaoExclusivo,
                    quantidadeExclusivo: pedido.quantidadeExclusivo,
                    valorExclusivo: pedido.isExclusivo ? pedido.valorTotal : null,
                  )),
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
                          Text(
                              pedido.isExclusivo
                                  ? '${pedido.descricaoExclusivo} × ${pedido.quantidadeExclusivo}'
                                  : 'Pedido nº ${pedido.ordem}',
                              overflow: TextOverflow.ellipsis,
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

              // ── Tags ─────────────────────────────────────────────
              if (pedido.status.isNotEmpty ||
                  labelEntrega != null ||
                  pedido.isRefaturado ||
                  pedido.isExclusivo) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (pedido.isExclusivo)
                      _Tag(
                        label: 'Exclusivo',
                        icone: Icons.storefront_outlined,
                        cor: Colors.teal.shade600,
                        fundo: Colors.teal.shade50,
                      ),
                    if (pedido.status.isNotEmpty)
                      _Tag(
                        label: pedido.status,
                        cor: _corSituacao,
                        fundo: _corFundoSituacao,
                      ),
                    if (labelEntrega != null)
                      _Tag(
                        label: labelEntrega,
                        icone: Icons.local_shipping_outlined,
                        cor: AppColors.laranja,
                        fundo: AppColors.laranja.withOpacity(0.08),
                      ),
                    if (pedido.isRefaturado)
                      _Tag(
                        label: 'Refaturado',
                        icone: Icons.sync_alt_rounded,
                        cor: Colors.purple.shade600,
                        fundo: Colors.purple.shade50,
                      ),
                  ],
                ),
              ],

              // ── Baixar nota fiscal ───────────────────────────────
              if (pedido.docnum.isNotEmpty) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _baixandoNota ? null : _baixarNotaFiscal,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.laranja.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.laranja.withOpacity(0.25)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _baixandoNota
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.laranja),
                            )
                          : const Icon(Icons.file_download_outlined,
                              size: 16, color: AppColors.laranja),
                      const SizedBox(width: 6),
                      Text('Baixar nota fiscal',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.laranja)),
                    ]),
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

class _Tag extends StatelessWidget {
  final String label;
  final IconData? icone;
  final Color cor;
  final Color fundo;

  const _Tag({required this.label, this.icone, required this.cor, required this.fundo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, color: cor, size: 12),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w500, color: cor)),
        ],
      ),
    );
  }
}
