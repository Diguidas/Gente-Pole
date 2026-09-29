import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

/// Vídeos e PDFs de "como usar o app", cadastrados pelo Endomkt.
class ManualUsoScreen extends StatefulWidget {
  const ManualUsoScreen({super.key});

  @override
  State<ManualUsoScreen> createState() => _ManualUsoScreenState();
}

class _ManualUsoScreenState extends State<ManualUsoScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _manuais = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final lista = await _api.listarManuaisUso();
      if (!mounted) return;
      setState(() {
        _manuais = lista;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  Future<void> _abrir(Map<String, dynamic> manual) async {
    final url = manual['arquivo_url'] as String?;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool _ehVideo(String nomeArquivo) {
    final ext = nomeArquivo.split('.').last.toLowerCase();
    return ext == 'mp4' || ext == 'mov' || ext == 'webm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.laranja,
        foregroundColor: Colors.white,
        title: Text('Manual de Uso',
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        centerTitle: false,
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _manuais.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.video_library_outlined,
                          size: 56, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 12),
                      Text('Nenhum manual disponível no momento.',
                          style: GoogleFonts.poppins(
                              fontSize: 14, color: AppColors.cinzaTexto)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: _manuais.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final manual = _manuais[i];
                      final nomeArquivo = manual['arquivo_nome'] as String? ?? '';
                      final ehVideo = _ehVideo(nomeArquivo);
                      return GestureDetector(
                        onTap: () => _abrir(manual),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.laranja.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                    ehVideo
                                        ? Icons.play_circle_outline
                                        : Icons.picture_as_pdf_outlined,
                                    color: AppColors.laranja),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(manual['nome'] as String? ?? '',
                                        style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.dark)),
                                    if ((manual['descricao'] as String?)
                                            ?.isNotEmpty ==
                                        true)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                            manual['descricao'] as String,
                                            style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                color: AppColors.cinzaTexto)),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: AppColors.cinzaTexto, size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
