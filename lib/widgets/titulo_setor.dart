import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';

/// Marcador de início de um setor numa lista de liderados (veja
/// [intercalarSetores]).
class CabecalhoSetorItem {
  final String setor;
  final int qtd;
  final bool primeiro;
  const CabecalhoSetorItem(this.setor, this.qtd, {this.primeiro = false});
}

/// Título de setor mostrado antes dos liderados daquele setor.
class TituloSetor extends StatelessWidget {
  final CabecalhoSetorItem item;
  const TituloSetor(this.item, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: item.primeiro ? 0 : 10),
      child: Row(children: [
        const Icon(Icons.business_outlined, size: 15, color: AppColors.cinzaTexto),
        const SizedBox(width: 6),
        Expanded(
          child: Text(item.setor,
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dark)),
        ),
        Text('${item.qtd}',
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
      ]),
    );
  }
}

/// Quem lidera mais de um setor vê os liderados separados por setor: devolve
/// os itens agrupados (setores em ordem alfabética, mantendo a ordem original
/// dentro de cada um) com um [CabecalhoSetorItem] antes de cada grupo. Com um
/// setor só (ou nenhum), devolve a lista como veio, sem títulos.
List<Object> intercalarSetores<T extends Object>(
    List<T> itens, String? Function(T) setorDe) {
  String chave(T i) {
    final s = (setorDe(i) ?? '').trim();
    return s.isEmpty ? 'Sem setor' : s;
  }

  final grupos = <String, List<T>>{};
  for (final i in itens) {
    grupos.putIfAbsent(chave(i), () => []).add(i);
  }
  if (grupos.length <= 1) return List<Object>.from(itens);
  final nomes = grupos.keys.toList()..sort();
  return [
    for (var n = 0; n < nomes.length; n++) ...[
      CabecalhoSetorItem(nomes[n], grupos[nomes[n]]!.length, primeiro: n == 0),
      ...grupos[nomes[n]]!,
    ],
  ];
}
