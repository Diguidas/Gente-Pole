import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const _corCardapio = Color(0xFFF59E0B);

class CardapioScreen extends StatefulWidget {
  const CardapioScreen({super.key});

  @override
  State<CardapioScreen> createState() => _CardapioScreenState();
}

class _CardapioScreenState extends State<CardapioScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _imagemUrl;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final url = await _api.buscarCardapioImagem();
    if (!mounted) return;
    setState(() {
      _imagemUrl = url;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Container(
                height: 180,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_corCardapio, Color(0xFFE86A00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.restaurant_menu_outlined, color: Colors.white, size: 32),
                    const SizedBox(height: 8),
                    Text('Cardápio do Refeitório',
                        style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text('Confira o cardápio do refeitório',
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.white.withOpacity(0.85))),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _corCardapio))
                  : RefreshIndicator(
                      color: _corCardapio,
                      onRefresh: _carregar,
                      child: _imagemUrl == null
                          ? ListView(children: [_vazio()])
                          : ListView(
                              padding: const EdgeInsets.all(20),
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Image.network(_imagemUrl!, fit: BoxFit.contain),
                                ),
                              ],
                            ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vazio() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.restaurant_menu_outlined, size: 48, color: AppColors.cinzaTexto),
              const SizedBox(height: 12),
              Text('Nenhum cardápio cadastrado ainda.',
                  textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 14, color: AppColors.cinzaTexto)),
            ],
          ),
        ),
      );
}
