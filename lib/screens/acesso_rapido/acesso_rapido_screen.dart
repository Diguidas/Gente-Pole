import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const _iconesRedeSocial = {
  'instagram': (Icons.camera_alt_outlined, Color(0xFFE1306C)),
  'youtube': (Icons.play_circle_outline, Color(0xFFFF0000)),
  'linkedin': (Icons.business_center_outlined, Color(0xFF0A66C2)),
  'facebook': (Icons.thumb_up_outlined, Color(0xFF1877F2)),
  'tiktok': (Icons.music_note_outlined, Color(0xFF000000)),
};

class AcessoRapidoScreen extends StatefulWidget {
  const AcessoRapidoScreen({super.key});

  @override
  State<AcessoRapidoScreen> createState() => _AcessoRapidoScreenState();
}

class _AcessoRapidoScreenState extends State<AcessoRapidoScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _links = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final lista = await _api.listarAcessoRapidoLinks();
      if (!mounted) return;
      setState(() {
        _links = lista;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  Future<void> _abrir(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  List<Map<String, dynamic>> _porTipo(String tipo) =>
      _links.where((l) => (l['tipo'] as String? ?? 'link') == tipo).toList();

  IconData _iconePara(Map<String, dynamic> link) {
    final tipo = link['tipo'] as String?;
    if (tipo == 'whatsapp') return Icons.chat_outlined;
    if (tipo == 'rede_social') return _iconesRedeSocial[link['icone']]?.$1 ?? Icons.public_outlined;
    return Icons.link_rounded;
  }

  Color _corPara(Map<String, dynamic> link) {
    if (link['tipo'] == 'rede_social') return _iconesRedeSocial[link['icone']]?.$2 ?? AppColors.laranja;
    return AppColors.laranja;
  }

  @override
  Widget build(BuildContext context) {
    final links = _porTipo('link');
    final redes = _porTipo('rede_social');
    final contatos = _porTipo('whatsapp');

    return Scaffold(
      appBar: AppBar(
        title: Text('Acesso Rápido', style: AppTextStyles.tituloGrande),
        centerTitle: false,
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _links.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bolt_outlined, size: 56, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 12),
                      Text('Nenhum item disponível ainda.',
                          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.cinzaTexto)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (links.isNotEmpty) _secao('Links', links),
                      if (redes.isNotEmpty) _secao('Redes Sociais', redes),
                      if (contatos.isNotEmpty) _secao('Contatos', contatos),
                    ],
                  ),
                ),
    );
  }

  Widget _secao(String titulo, List<Map<String, dynamic>> itens) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.cinzaTexto)),
          const SizedBox(height: 10),
          ...itens.map((link) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: () => _abrir(link['url'] as String),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
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
                          child: Icon(_iconePara(link), color: _corPara(link)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(link['titulo'] as String? ?? '',
                              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.dark)),
                        ),
                        const Icon(Icons.open_in_new, color: AppColors.cinzaTexto, size: 20),
                      ],
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
