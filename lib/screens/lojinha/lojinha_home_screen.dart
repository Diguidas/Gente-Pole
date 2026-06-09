import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/lojinha_model.dart';
import '../../services/api_service.dart';
import 'lojinha_produtos_screen.dart';
import 'lojinha_pedidos_screen.dart';
import 'lojinha_pedido_detalhe_screen.dart';

class LojinhaHomeScreen extends StatefulWidget {
  const LojinhaHomeScreen({super.key});

  @override
  State<LojinhaHomeScreen> createState() => _LojinhaHomeScreenState();
}

class _LojinhaHomeScreenState extends State<LojinhaHomeScreen> {
  final _api = ApiService();
  LojinhaFuncionarioModel? _dados;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    _dados = await _api.buscarDadosFuncionarioLojinha();
    setState(() => _carregando = false);
  }

  String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    final colaborador = _api.colaboradorAtual;
    final dados = _dados;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 260,
            decoration: const BoxDecoration(
                gradient: AppColors.gradientePrincipal),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ───────────────────────────────────────────────
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
                          Text('🛒 Lojinha',
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700)),
                          Text('Olá, ${colaborador?.primeiroNome ?? ''}!',
                              style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Card de Limite ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _carregando
                      ? _shimmerCard()
                      : dados == null
                          ? _erroCard()
                          : _limiteCard(dados),
                ),

                const SizedBox(height: 8),

                // ── Corpo ────────────────────────────────────────────────
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Alerta de bloqueio ───────────────────────
                          if (dados != null && dados.bloqueado)
                            _alertaBloqueio(dados.bloqueio),

                          // ── Botões principais ────────────────────────
                          _botaoMenu(
                            context,
                            icone: Icons.add_shopping_cart_rounded,
                            titulo: 'Novo Pedido',
                            subtitulo: 'Explorar produtos disponíveis',
                            cor: AppColors.laranja,
                            bloqueado: dados?.bloqueado ?? false,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LojinhaProdutosScreen(
                                    dadosFuncionario: dados,
                                    onPedidoCriado: _carregar,
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 14),

                          _botaoMenu(
                            context,
                            icone: Icons.receipt_long_rounded,
                            titulo: 'Meus Pedidos',
                            subtitulo:
                                '${dados?.pedidos.length ?? 0} pedido${(dados?.pedidos.length ?? 0) != 1 ? 's' : ''} realizados',
                            cor: AppColors.magenta,
                            bloqueado: false,
                            onTap: dados == null
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => LojinhaPedidosScreen(
                                          pedidos: dados.pedidos,
                                        ),
                                      ),
                                    ),
                          ),

                          const SizedBox(height: 28),

                          // ── Último pedido ────────────────────────────
                          if (dados != null && dados.pedidos.isNotEmpty) ...[
                            Text('Último pedido',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.cinzaTexto,
                                    letterSpacing: 0.4)),
                            const SizedBox(height: 10),
                            _ultimoPedidoCard(dados.pedidos.first),
                          ],
                        ],
                      ),
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

  // ── Widgets internos ──────────────────────────────────────────────────────

  Widget _limiteCard(LojinhaFuncionarioModel d) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Limite disponível',
                  style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.8), fontSize: 12)),
              Text('Total: ${_moeda(d.limiteTotal)}',
                  style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.7), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          Text(_moeda(d.limiteDisp),
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: 1 - d.percentualUsado,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Utilizado: ${_moeda(d.limiteUsado)} de ${_moeda(d.limiteTotal)}',
            style: GoogleFonts.poppins(
                color: Colors.white.withOpacity(0.7), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _shimmerCard() => Container(
        height: 110,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
            child: CircularProgressIndicator(color: Colors.white)),
      );

  Widget _erroCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Não foi possível carregar seus dados.',
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 13)),
            ),
            GestureDetector(
              onTap: _carregar,
              child: const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
          ],
        ),
      );

  Widget _alertaBloqueio(String motivo) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.block_rounded, color: Colors.red.shade600, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                motivo.isNotEmpty
                    ? motivo
                    : 'Sua conta está bloqueada. Entre em contato com o RH.',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.red.shade700),
              ),
            ),
          ],
        ),
      );

  Widget _botaoMenu(
    BuildContext context, {
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required Color cor,
    required bool bloqueado,
    required VoidCallback? onTap,
  }) {
    final desabilitado = bloqueado && titulo == 'Novo Pedido';
    return GestureDetector(
      onTap: desabilitado ? null : onTap,
      child: Opacity(
        opacity: desabilitado ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: cor.withOpacity(0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: cor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16)),
                child: Icon(icone, color: cor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark)),
                    Text(subtitulo,
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.cinzaTexto)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.cinzaTexto, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ultimoPedidoCard(LojinhaPedidoResumoModel p) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => LojinhaPedidoDetalheScreen(ordem: p.ordem)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: AppColors.laranja.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.receipt_rounded,
                  color: AppColors.laranja, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pedido nº ${p.ordem}',
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(p.criacaoFormatada,
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: AppColors.cinzaTexto)),
                ],
              ),
            ),
            Text(
              'R\$ ${p.valorTotal.toStringAsFixed(2).replaceAll('.', ',')}',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.laranja),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.cinzaTexto, size: 18),
          ],
        ),
      ),
    );
  }
}