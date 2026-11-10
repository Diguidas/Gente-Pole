import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../avaliacao/avaliacao_screen.dart';
import '../feedback/feedback_screen.dart';
import '../avaliacao/avaliar_colegas_screen.dart';
import '../avaliacao/periodo_experiencia_screen.dart';
import '../pdi/pdi_screen.dart';
import 'performance_widgets.dart';

class PerformanceColabScreen extends StatefulWidget {
  const PerformanceColabScreen({super.key});

  @override
  State<PerformanceColabScreen> createState() => _PerformanceColabScreenState();
}

class _PerformanceColabScreenState extends State<PerformanceColabScreen> {
  final _api = ApiService();
  Map<String, String> _visual = {};
  List<Map<String, dynamic>> _materiais = [];
  int _feedbackNaoLidos = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    Map<String, String> visual = {};
    List<Map<String, dynamic>> materiais = [];
    try {
      visual = await _api.listarPerformanceVisual();
    } catch (_) {}
    try {
      materiais = await _api.listarMateriaisPerformance(gestor: false);
    } catch (_) {}
    int naoLidos = 0;
    try {
      naoLidos = await _api.contarFeedbacksNaoLidos() +
          await _api.contarFeedbacksGestorNaoLidos();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _feedbackNaoLidos = naoLidos;
      _visual = visual;
      _materiais = materiais;
    });
  }

  Future<void> _abrir(Widget tela) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
    if (mounted) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return PerformanceScaffold(
      titulo: 'Performance',
      children: [
        PerformanceBanner(url: _visual['banner']),
        PerformanceMateriais(materiais: _materiais),
        PerformanceCard(
          icone: Icons.explore_outlined,
          imagemUrl: _visual['periodo_experiencia'],
          titulo: 'Período de Experiência',
          descricao: 'Responda a pesquisa do seu período de experiência',
          onTap: () => _abrir(const PeriodoExperienciaScreen()),
        ),
        PerformanceCard(
          icone: Icons.assessment_outlined,
          imagemUrl: _visual['avaliacao'],
          titulo: 'Minha Avaliação',
          descricao: 'Responda sua autoavaliação de desempenho',
          onTap: () => _abrir(const AvaliacaoScreen()),
        ),
        PerformanceCard(
          icone: Icons.groups_outlined,
          imagemUrl: _visual['avaliar_colegas'],
          titulo: 'Avaliar Colegas',
          descricao: 'Avaliações de ciclo 360 pendentes',
          onTap: () => _abrir(const AvaliarColegasScreen()),
        ),
        PerformanceCard(
          icone: Icons.flag_outlined,
          imagemUrl: _visual['pdi'],
          titulo: 'Meu PDI',
          descricao: 'Acompanhe seu plano de desenvolvimento',
          onTap: () => _abrir(const PdiScreen()),
        ),
        PerformanceCard(
          icone: Icons.forum_outlined,
          imagemUrl: _visual['feedback'],
          titulo: 'Feedback',
          descricao: 'Envie, receba e peça feedback ao seu gestor',
          badge: _feedbackNaoLidos,
          onTap: () => _abrir(const FeedbackScreen()),
        ),
      ],
    );
  }
}
