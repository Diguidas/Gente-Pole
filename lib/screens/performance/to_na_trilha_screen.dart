import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import 'performance_widgets.dart';

class ToNaTrilhaScreen extends StatefulWidget {
  const ToNaTrilhaScreen({super.key});

  @override
  State<ToNaTrilhaScreen> createState() => _ToNaTrilhaScreenState();
}

class _ToNaTrilhaScreenState extends State<ToNaTrilhaScreen> {
  final _api = ApiService();
  String? _banner;
  String _descricao = '';
  List<Map<String, dynamic>> _itens = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    String? banner;
    String descricao = '';
    List<Map<String, dynamic>> itens = [];
    try {
      banner = (await _api.listarPerformanceVisual())['to_na_trilha_banner'];
    } catch (_) {}
    try {
      descricao = await _api.obterToNaTrilhaDescricao();
    } catch (_) {}
    try {
      itens = await _api.listarToNaTrilhaItens();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _banner = banner;
      _descricao = descricao;
      _itens = itens;
    });
  }

  void _abrirSecao(String secao, String titulo) {
    final links = _itens.where((i) => i['secao'] == secao).toList();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(titulo,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: roxoPerformance)),
        content: SizedBox(
          width: double.maxFinite,
          child: links.isEmpty
              ? Text('Nenhum conteúdo disponível ainda.',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppColors.cinzaTexto))
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: links.map((l) {
                      final desc = l['descricao'] as String?;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: roxoPerformance.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () =>
                                abrirLinkPerformance(ctx, l['link'] as String?),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(l['titulo'] as String? ?? '',
                                            style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.dark)),
                                        if (desc != null && desc.isNotEmpty)
                                          Text(desc,
                                              style: GoogleFonts.poppins(
                                                  fontSize: 12,
                                                  color:
                                                      AppColors.cinzaTexto)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.open_in_new_rounded,
                                      size: 18, color: roxoPerformance),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Fechar',
                style: GoogleFonts.poppins(color: roxoPerformance)),
          ),
        ],
      ),
    );
  }

  Widget _botao(String titulo, String secao) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _abrirSecao(secao, titulo),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: roxoPerformance.withOpacity(0.25)),
                boxShadow: [
                  BoxShadow(
                    color: roxoPerformance.withOpacity(0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(titulo,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: roxoPerformance)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PerformanceScaffold(
      titulo: 'Tô na Trilha',
      children: [
        PerformanceBanner(url: _banner),
        if (_descricao.isNotEmpty) ...[
          SizedBox(
            width: double.infinity,
            child: Text(_descricao,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.cinzaTexto, height: 1.5)),
          ),
          const SizedBox(height: 20),
        ],
        _botao('Fluxograma', 'fluxograma'),
        _botao('Critérios de avaliação', 'criterios'),
        _botao('Formulários de promoção', 'formularios'),
      ],
    );
  }
}
