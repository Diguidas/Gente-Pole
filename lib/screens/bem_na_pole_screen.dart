import 'package:flutter/material.dart';
import 'package:gentepole/screens/massoterapia/massoterapia_screen.dart';
import 'package:gentepole/screens/nutricionista/nutricionista_screen.dart';
import 'package:gentepole/screens/conexoes/conexoes_do_bem_screen.dart';
import 'package:gentepole/screens/fisioterapia/fisioterapia_screen.dart';
import 'package:gentepole/screens/consulta_medica/consulta_medica_screen.dart';
import 'plantao_psicologico_screen.dart';
import 'performance/performance_widgets.dart';

class BemNaPoleScreen extends StatelessWidget {
  final bool massoterapiaDisponivel;
  final bool nutricaoDisponivel;

  const BemNaPoleScreen({
    super.key,
    required this.massoterapiaDisponivel,
    required this.nutricaoDisponivel,
  });

  void _abrir(BuildContext context, Widget tela) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => tela));

  @override
  Widget build(BuildContext context) {
    return PerformanceScaffold(
      titulo: 'Bem na Pole',
      children: [
        if (massoterapiaDisponivel)
          PerformanceCard(
            icone: Icons.self_improvement_rounded,
            titulo: 'Massoterapia',
            descricao: 'Agende sua sessão de bem-estar',
            onTap: () => _abrir(context, const MassoterapiaScreen()),
          ),
        if (nutricaoDisponivel)
          PerformanceCard(
            icone: Icons.local_dining_outlined,
            titulo: 'Nutricionista',
            descricao: 'Agende uma consulta nutricional',
            onTap: () => _abrir(context, const NutricionistaScreen()),
          ),
        PerformanceCard(
          icone: Icons.accessibility_new_rounded,
          titulo: 'Fisioterapia',
          descricao: 'Acompanhe suas sessões e exercícios',
          onTap: () => _abrir(context, const FisioterapiaScreen()),
        ),
        PerformanceCard(
          icone: Icons.medical_information_outlined,
          titulo: 'Consulta médica',
          descricao: 'Solicite e acompanhe sua consulta',
          onTap: () => _abrir(context, const ConsultaMedicaScreen()),
        ),
        PerformanceCard(
          icone: Icons.psychology_outlined,
          titulo: 'Plantão Psicológico',
          descricao: 'Apoio emocional e saúde mental',
          onTap: () => _abrir(context, const PlantaoPsicologicoScreen()),
        ),
        PerformanceCard(
          icone: Icons.favorite_outline_rounded,
          titulo: 'Conexões do Bem',
          descricao: 'Voluntariado e indicação de instituições',
          onTap: () => _abrir(context, const ConexoesDoiemScreen()),
        ),
      ],
    );
  }
}
