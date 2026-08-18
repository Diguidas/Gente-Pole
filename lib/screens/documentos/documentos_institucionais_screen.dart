import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

class DocumentosInstitucionaisScreen extends StatefulWidget {
  const DocumentosInstitucionaisScreen({super.key});

  @override
  State<DocumentosInstitucionaisScreen> createState() => _DocumentosInstitucionaisScreenState();
}

class _DocumentosInstitucionaisScreenState extends State<DocumentosInstitucionaisScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _documentos = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final lista = await _api.listarDocumentosInstitucionais();
      if (!mounted) return;
      setState(() {
        _documentos = lista;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  Future<void> _abrir(Map<String, dynamic> doc) async {
    final url = doc['arquivo_url'] as String?;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Documentos Institucionais', style: AppTextStyles.tituloGrande),
        centerTitle: false,
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _documentos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.folder_outlined, size: 56, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 12),
                      Text('Nenhum documento disponível ainda.',
                          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.cinzaTexto)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: _documentos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final doc = _documentos[i];
                      return GestureDetector(
                        onTap: () => _abrir(doc),
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
                                child: const Icon(Icons.description_outlined, color: AppColors.laranja),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(doc['nome'] as String? ?? '',
                                    style: GoogleFonts.poppins(
                                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.dark)),
                              ),
                              const Icon(Icons.download_outlined, color: AppColors.cinzaTexto, size: 20),
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
