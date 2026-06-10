import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';
import '../models/comunicado_model.dart';
import '../services/api_service.dart';

class ComunicadosScreen extends StatefulWidget {
  const ComunicadosScreen({super.key});

  @override
  State<ComunicadosScreen> createState() => _ComunicadosScreenState();
}

class _ComunicadosScreenState extends State<ComunicadosScreen> {
  final _api = ApiService();
  late Future<List<ComunicadoModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.buscarTodosComunicados();
  }

  void _recarregar() => setState(() {
        _future = _api.buscarTodosComunicados();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 200,
            decoration: const BoxDecoration(
              color: AppColors.laranja,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Header ────────────────────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '📢 Comunicados',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Novidades da empresa',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _recarregar,
                        icon: const Icon(Icons.refresh_rounded,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),

                // ── Lista ─────────────────────────────────────────────────
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: FutureBuilder<List<ComunicadoModel>>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.magenta),
                          );
                        }
                        if (snap.hasError) {
                          return _erroWidget();
                        }

                        final lista = snap.data ?? [];
                        if (lista.isEmpty) return _vazioWidget();

                        return RefreshIndicator(
                          color: AppColors.magenta,
                          onRefresh: () async => _recarregar(),
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 20, 16, 32),
                            itemCount: lista.length,
                            itemBuilder: (ctx, i) => _card(lista[i], i == 0),
                          ),
                        );
                      },
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

  // ── Card ─────────────────────────────────────────────────────────────────────

  Widget _card(ComunicadoModel c, bool destaque) {
    return GestureDetector(
      onTap: () => _abrirDetalhe(c),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: destaque
                  ? AppColors.magenta.withOpacity(0.15)
                  : const Color(0x08000000),
              blurRadius: destaque ? 14 : 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: destaque
              ? Border.all(
                  color: AppColors.magenta.withOpacity(0.25), width: 1.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Foto
            if (c.fotoUrl != null && c.fotoUrl!.isNotEmpty)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                child: Image.network(
                  c.fotoUrl!,
                  height: destaque ? 180 : 130,
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (_, __, ___) => _bannerVazio(destaque),
                ),
              )
            else
              _bannerVazio(destaque),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (destaque)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [AppColors.laranja, AppColors.magenta]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'DESTAQUE',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  Text(
                    c.titulo,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: destaque ? 15 : 14,
                      color: AppColors.dark,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (c.descricao != null && c.descricao!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      c.descricao!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.cinzaTexto,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    c.dataFormatada,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.cinzaTexto,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bannerVazio(bool grande) => Container(
        height: grande ? 120 : 80,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.laranja, AppColors.magenta]),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: const Center(
          child:
              Icon(Icons.campaign_rounded, color: Colors.white, size: 40),
        ),
      );

  // ── Modal de detalhe ─────────────────────────────────────────────────────────

  void _abrirDetalhe(ComunicadoModel c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.cinzaTexto.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: ctrl,
                  padding: EdgeInsets.zero,
                  children: [
                    if (c.fotoUrl != null && c.fotoUrl!.isNotEmpty)
                      Image.network(
                        c.fotoUrl!,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.titulo,
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            c.dataFormatada,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.cinzaTexto,
                            ),
                          ),
                          if (c.descricao != null &&
                              c.descricao!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              c.descricao!,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: AppColors.dark,
                                height: 1.6,
                              ),
                            ),
                          ],
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Estados ──────────────────────────────────────────────────────────────────

  Widget _erroWidget() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 56, color: AppColors.cinzaTexto),
              const SizedBox(height: 16),
              Text('Não foi possível carregar',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dark)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _recarregar,
                child: Text('Tentar novamente',
                    style: GoogleFonts.poppins(color: AppColors.magenta)),
              ),
            ],
          ),
        ),
      );

  Widget _vazioWidget() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.campaign_outlined,
                  size: 56, color: AppColors.cinzaTexto),
              const SizedBox(height: 16),
              Text('Nenhum comunicado ainda',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dark)),
            ],
          ),
        ),
      );
}