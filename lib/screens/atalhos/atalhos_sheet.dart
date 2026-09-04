import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../core/atalhos_favoritos_service.dart';
import '../../core/atalhos_registry.dart';

/// Abre o menu de atalhos rápidos (até 3 serviços favoritos).
Future<void> abrirMenuAtalhos(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _AtalhosSheet(),
  );
}

class _AtalhosSheet extends StatefulWidget {
  const _AtalhosSheet();

  @override
  State<_AtalhosSheet> createState() => _AtalhosSheetState();
}

class _AtalhosSheetState extends State<_AtalhosSheet> {
  bool _loading = true;
  List<String> _favoritosIds = [];
  List<AtalhoDef> _visiveis = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final resultados = await Future.wait([
      AtalhosFavoritosService.obterFavoritos(),
      atalhosVisiveis(),
    ]);
    if (!mounted) return;
    setState(() {
      _favoritosIds = resultados[0] as List<String>;
      _visiveis = resultados[1] as List<AtalhoDef>;
      _loading = false;
    });
  }

  Future<void> _editar() async {
    final salvou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditorAtalhosSheet(
        favoritosAtuais: _favoritosIds,
        visiveis: _visiveis,
      ),
    );
    if (salvou == true) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final visiveisIds = _visiveis.map((a) => a.id).toSet();
    final favoritos = _favoritosIds
        .map(buscarAtalho)
        .whereType<AtalhoDef>()
        .where((a) => visiveisIds.contains(a.id))
        .toList();

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.star_rounded, color: AppColors.magenta),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Meus Atalhos', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark)),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _editar,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar'),
                style: TextButton.styleFrom(foregroundColor: AppColors.magenta),
              ),
            ]),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator(color: AppColors.magenta)),
              )
            else if (favoritos.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(children: [
                  Text('Você ainda não escolheu seus atalhos.',
                      textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _editar,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Escolher atalhos'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.magenta, foregroundColor: Colors.white),
                  ),
                ]),
              )
            else
              ...favoritos.map((a) => _itemAtalho(context, a)),
          ],
        ),
      ),
    );
  }

  Widget _itemAtalho(BuildContext context, AtalhoDef a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: a.builder));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: a.cor.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: a.cor.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(a.icon, color: a.cor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(a.label, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.dark)),
              ),
              Icon(Icons.chevron_right_rounded, color: a.cor),
            ]),
          ),
        ),
      ),
    );
  }
}

class _EditorAtalhosSheet extends StatefulWidget {
  final List<String> favoritosAtuais;
  final List<AtalhoDef> visiveis;
  const _EditorAtalhosSheet({required this.favoritosAtuais, required this.visiveis});

  @override
  State<_EditorAtalhosSheet> createState() => _EditorAtalhosSheetState();
}

class _EditorAtalhosSheetState extends State<_EditorAtalhosSheet> {
  late List<String> _selecionados;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _selecionados = [...widget.favoritosAtuais];
  }

  void _toggle(String id) {
    setState(() {
      if (_selecionados.contains(id)) {
        _selecionados.remove(id);
      } else if (_selecionados.length < AtalhosFavoritosService.maxAtalhos) {
        _selecionados.add(id);
      }
    });
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    await AtalhosFavoritosService.salvarFavoritos(_selecionados);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollController) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Escolha até ${AtalhosFavoritosService.maxAtalhos} atalhos',
                    style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark)),
                const SizedBox(height: 4),
                Text('${_selecionados.length}/${AtalhosFavoritosService.maxAtalhos} selecionados',
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: widget.visiveis.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final a = widget.visiveis[i];
                      final sel = _selecionados.contains(a.id);
                      final desabilitado = !sel && _selecionados.length >= AtalhosFavoritosService.maxAtalhos;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: desabilitado ? null : () => _toggle(a.id),
                          child: Opacity(
                            opacity: desabilitado ? 0.4 : 1,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: sel ? a.cor.withOpacity(0.1) : const Color(0xFFF8F9FC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: sel ? a.cor : Colors.transparent),
                              ),
                              child: Row(children: [
                                Icon(a.icon, color: a.cor, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(a.label, style: GoogleFonts.poppins(fontSize: 14, color: AppColors.dark)),
                                ),
                                Icon(sel ? Icons.check_circle_rounded : Icons.circle_outlined, color: sel ? a.cor : AppColors.cinzaTexto, size: 20),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _salvando ? null : _salvar,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.magenta, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _salvando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Salvar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
