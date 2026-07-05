import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const _corCardapio = Color(0xFFF59E0B);

const _categoriaInfo = {
  'proteina': ('Proteínas', Icons.set_meal_outlined),
  'acompanhamento': ('Acompanhamentos', Icons.rice_bowl_outlined),
  'salada': ('Saladas', Icons.eco_outlined),
  'molho': ('Molhos', Icons.opacity_outlined),
  'sobremesa': ('Sobremesa', Icons.icecream_outlined),
  'outro': ('Outros', Icons.restaurant_outlined),
};

class CardapioScreen extends StatefulWidget {
  const CardapioScreen({super.key});

  @override
  State<CardapioScreen> createState() => _CardapioScreenState();
}

class _CardapioScreenState extends State<CardapioScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _loadingDia = false;
  List<DateTime> _diasDisponiveis = [];
  DateTime? _diaSelecionado;
  Map<String, dynamic>? _cardapioDia;

  static const _diasSemana = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB'];

  String _fmtData(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final hoje = DateTime.now();
    final segunda = hoje.subtract(Duration(days: hoje.weekday - 1));
    final inicio = DateTime(segunda.year, segunda.month, segunda.day);
    final fim = inicio.add(const Duration(days: 13));

    final dias = await _api.listarDiasCardapio(inicio: inicio, fim: fim);
    if (!mounted) return;

    final datas = dias.map((d) => DateTime.parse(d['data'] as String)).toList()..sort();

    setState(() {
      _diasDisponiveis = datas;
      _loading = false;
    });

    if (datas.isNotEmpty) {
      final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);
      final padrao = datas.firstWhere(
        (d) => !d.isBefore(hojeSemHora),
        orElse: () => datas.last,
      );
      await _selecionarDia(padrao);
    }
  }

  Future<void> _selecionarDia(DateTime dia) async {
    setState(() {
      _diaSelecionado = dia;
      _loadingDia = true;
    });
    final cardapio = await _api.buscarCardapioDia(_fmtData(dia));
    if (!mounted) return;
    setState(() {
      _cardapioDia = cardapio;
      _loadingDia = false;
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
                    Text('Veja o cardápio dos próximos dias',
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
                  : _diasDisponiveis.isEmpty
                      ? _vazio()
                      : RefreshIndicator(
                          color: _corCardapio,
                          onRefresh: _carregar,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 20),
                              _seletorDias(),
                              const SizedBox(height: 16),
                              Expanded(
                                child: _loadingDia
                                    ? const Center(child: CircularProgressIndicator(color: _corCardapio))
                                    : _cardapioDia == null
                                        ? _vazio()
                                        : _conteudoDia(),
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

  Widget _seletorDias() {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: _diasDisponiveis.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final dia = _diasDisponiveis[i];
          final sel = _diaSelecionado != null &&
              dia.year == _diaSelecionado!.year &&
              dia.month == _diaSelecionado!.month &&
              dia.day == _diaSelecionado!.day;
          return GestureDetector(
            onTap: () => _selecionarDia(dia),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 64,
              decoration: BoxDecoration(
                color: sel ? _corCardapio : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sel ? _corCardapio : const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                      color: sel ? _corCardapio.withOpacity(0.35) : Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_diasSemana[dia.weekday - 1],
                      style: GoogleFonts.poppins(
                          fontSize: 10, fontWeight: FontWeight.w600, color: sel ? Colors.white70 : AppColors.cinzaTexto)),
                  Text('${dia.day.toString().padLeft(2, '0')}/${dia.month.toString().padLeft(2, '0')}',
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w700, color: sel ? Colors.white : AppColors.dark)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _conteudoDia() {
    final itens = List<Map<String, dynamic>>.from(_cardapioDia!['itens'] as List? ?? []);
    final observacao = _cardapioDia!['observacao'] as String?;
    final porCategoria = <String, List<String>>{};
    for (final item in itens) {
      final categoria = item['categoria'] as String;
      porCategoria.putIfAbsent(categoria, () => []).add(item['texto'] as String);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final categoria in ApiService.cardapioCategorias)
            if (porCategoria[categoria]?.isNotEmpty ?? false) _blocoCategoria(categoria, porCategoria[categoria]!),
          if (observacao != null && observacao.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFB45309)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(observacao, style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFB45309))),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _blocoCategoria(String categoria, List<String> textos) {
    final (label, icone) = _categoriaInfo[categoria]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icone, size: 18, color: _corCardapio),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark)),
          ]),
          const SizedBox(height: 10),
          for (final texto in textos)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                        width: 5, height: 5, decoration: const BoxDecoration(color: _corCardapio, shape: BoxShape.circle)),
                  ),
                  Expanded(
                    child: Text(texto, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.dark, height: 1.4)),
                  ),
                ],
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
