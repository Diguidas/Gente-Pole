import 'package:flutter/material.dart';

/// Aparência (cor, ícone, rótulo) de cada categoria de tempo de casa —
/// bronze (5+), prata (10+), ouro (15+), diamante (20+) — usada no card de
/// "Aniversário de empresa hoje" do Feed. Espelha
/// gentepole_admin/lib/core/theme/nivel_tempo_casa.dart.
class NivelTempoCasa {
  final String label;
  final Color cor;
  final IconData icone;

  const NivelTempoCasa(this.label, this.cor, this.icone);

  static const _porCategoria = <String, NivelTempoCasa>{
    'bronze': NivelTempoCasa('Bronze', Color(0xFFB08D57), Icons.military_tech_rounded),
    'prata': NivelTempoCasa('Prata', Color(0xFF9AA5B1), Icons.military_tech_rounded),
    'ouro': NivelTempoCasa('Ouro', Color(0xFFD4AF37), Icons.military_tech_rounded),
    'diamante': NivelTempoCasa('Diamante', Color(0xFF63C7F2), Icons.diamond_rounded),
  };

  static NivelTempoCasa? deCategoria(String? categoria) =>
      categoria == null ? null : _porCategoria[categoria];

  static String? categoriaDeAnos(int anos) {
    if (anos >= 20) return 'diamante';
    if (anos >= 15) return 'ouro';
    if (anos >= 10) return 'prata';
    if (anos >= 5) return 'bronze';
    return null;
  }
}
