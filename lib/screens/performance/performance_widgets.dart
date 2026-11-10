import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';

const Color roxoPerformance = Color(0xFF5B2C9F);

Future<void> abrirLinkPerformance(BuildContext context, String? url,
    {String erro = 'Não foi possível abrir o link.'}) async {
  final uri = url != null ? Uri.tryParse(url) : null;
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(erro, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: AppColors.erro,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

class PerformanceBanner extends StatelessWidget {
  final String? url;
  const PerformanceBanner({super.key, this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          url!,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Materiais de apoio: "descricao: nome" com o nome em link.
class PerformanceMateriais extends StatefulWidget {
  final List<Map<String, dynamic>> materiais;
  const PerformanceMateriais({super.key, required this.materiais});

  @override
  State<PerformanceMateriais> createState() => _PerformanceMateriaisState();
}

class _PerformanceMateriaisState extends State<PerformanceMateriais> {
  final List<TapGestureRecognizer> _recs = [];

  @override
  void dispose() {
    for (final r in _recs) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recs) {
      r.dispose();
    }
    _recs.clear();
    if (widget.materiais.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.materiais.map((m) {
          final descricao = m['descricao'] as String?;
          final rec = TapGestureRecognizer()
            ..onTap = () => abrirLinkPerformance(
                context, m['arquivo_url'] as String?,
                erro: 'Não foi possível abrir o material.');
          _recs.add(rec);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.cinzaTexto),
                children: [
                  if (descricao != null && descricao.isNotEmpty)
                    TextSpan(text: '$descricao: '),
                  TextSpan(
                    text: m['nome'] as String? ?? '',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.laranja,
                        fontWeight: FontWeight.w600),
                    recognizer: rec,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class PerformanceCard extends StatelessWidget {
  final IconData icone;
  final String? imagemUrl;
  final String titulo;
  final String descricao;
  final VoidCallback onTap;
  final int badge;

  const PerformanceCard({
    super.key,
    required this.icone,
    this.imagemUrl,
    required this.titulo,
    required this.descricao,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final temImg = imagemUrl != null && imagemUrl!.isNotEmpty;
    final iconePadrao = Icon(icone, color: roxoPerformance, size: 36);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: roxoPerformance.withOpacity(0.18)),
              boxShadow: [
                BoxShadow(
                  color: roxoPerformance.withOpacity(0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: temImg
                              ? Image.network(imagemUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => iconePadrao)
                              : Center(child: iconePadrao),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(titulo,
                                  style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.dark)),
                              const SizedBox(height: 3),
                              Text(descricao,
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: AppColors.cinzaTexto)),
                            ],
                          ),
                        ),
                        if (badge > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: roxoPerformance,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('$badge',
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ),
                          const SizedBox(width: 6),
                        ],
                        const Icon(Icons.chevron_right_rounded,
                            color: roxoPerformance),
                      ],
                    ),
                  ),
                  Container(height: 4, color: roxoPerformance),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PerformanceScaffold extends StatelessWidget {
  final String titulo;
  final List<Widget> children;
  const PerformanceScaffold(
      {super.key, required this.titulo, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        backgroundColor: roxoPerformance,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(titulo,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children),
        ),
      ),
    );
  }
}
