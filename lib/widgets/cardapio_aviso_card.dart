import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';

/// "Prepare-se para o almoço": card do feed com o cardápio do dia da filial do
/// colaborador. Quem decide se aparece, a partir de que hora e até que hora é a
/// Nutrição (config do aviso no painel); o servidor responde se deve mostrar
/// agora. Reconsulta a cada minuto, então aparece e some sozinho nos horários.
class CardapioAvisoCard extends StatefulWidget {
  const CardapioAvisoCard({super.key});

  @override
  State<CardapioAvisoCard> createState() => _CardapioAvisoCardState();
}

class _CardapioAvisoCardState extends State<CardapioAvisoCard> {
  final _api = ApiService();
  Map<String, dynamic>? _dados;
  Timer? _timer;

  static const _cor = Color(0xFFF59E0B);
  static final _padrao = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*', dotAll: true);

  @override
  void initState() {
    super.initState();
    _carregar();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _carregar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _carregar() async {
    final col = _api.colaboradorAtual;
    final filial = ApiService.chaveFilialCardapio(
        empresa: col?.empresa, branch: col?.branch);
    final d = await _api.buscarAvisoCardapioHoje(filial);
    if (!mounted) return;
    setState(() => _dados = d);
  }

  /// Texto do cardápio com **negrito** e *itálico*.
  List<InlineSpan> _spans(String texto, TextStyle base) {
    final out = <InlineSpan>[];
    var pos = 0;
    for (final m in _padrao.allMatches(texto)) {
      if (m.start > pos) {
        out.add(TextSpan(text: texto.substring(pos, m.start), style: base));
      }
      out.add(m.group(1) != null
          ? TextSpan(
              text: m.group(1),
              style: base.copyWith(fontWeight: FontWeight.w700))
          : TextSpan(
              text: m.group(2),
              style: base.copyWith(fontStyle: FontStyle.italic)));
      pos = m.end;
    }
    if (pos < texto.length) {
      out.add(TextSpan(text: texto.substring(pos), style: base));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    if (d == null) return const SizedBox.shrink();
    final base = GoogleFonts.poppins(
        fontSize: 13.5, height: 1.5, color: const Color(0xFF3A3A3A));
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cor.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.restaurant_menu_rounded, color: _cor, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${d['titulo'] ?? 'Prepare-se para o almoço'}',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            Text('até ${d['ate'] ?? ''}',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: const Color(0xFF64748B))),
          ]),
          const SizedBox(height: 8),
          Text.rich(TextSpan(children: _spans('${d['texto'] ?? ''}', base))),
        ],
      ),
    );
  }
}
