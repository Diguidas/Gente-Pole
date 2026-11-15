import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import '../gestor/avaliar_equipe_screen.dart';
import '../gestor/avaliar_periodo_experiencia_gestor_screen.dart';
import '../gestor/feedback_gestor_screen.dart';
import '../gestor/pdi_gestor_screen.dart';
import 'performance_widgets.dart';
import 'to_na_trilha_screen.dart';

class PerformanceGestorScreen extends StatefulWidget {
  const PerformanceGestorScreen({super.key});

  @override
  State<PerformanceGestorScreen> createState() =>
      _PerformanceGestorScreenState();
}

class _PerformanceGestorScreenState extends State<PerformanceGestorScreen> {
  final _api = ApiService();
  Map<String, String> _visual = {};
  List<Map<String, dynamic>> _materiais = [];
  Set<String> _bloqueadas = {};
  // Avaliações da equipe ainda pendentes (bolinha no card)
  int _pendEquipe = 0;
  int _pendExperiencia = 0; // colaboradores aguardando avaliação de experiência

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    Map<String, String> visual = {};
    List<Map<String, dynamic>> materiais = [];
    Set<String> bloqueadas = {};
    var pendEquipe = 0;
    var pendExperiencia = 0;
    try {
      final pend = await _api.listarPendenciasAvaliacao();
      for (final p in pend.where((p) => p['tipo'] == 'avaliacao_gestor')) {
        pendEquipe += (p['qtd'] as int?) ?? 1;
      }
      for (final p in pend
          .where((p) => p['tipo'] == 'avaliacao_experiencia_gestor')) {
        pendExperiencia += (p['qtd'] as int?) ?? 1;
      }
    } catch (_) {}
    try {
      visual = await _api.listarPerformanceVisual();
    } catch (_) {}
    try {
      materiais = await _api.listarMateriaisPerformance(gestor: true);
    } catch (_) {}
    try {
      bloqueadas = await _api.listarFuncionalidadesGestorBloqueadas();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _visual = visual;
      _materiais = materiais;
      _bloqueadas = bloqueadas;
      _pendEquipe = pendEquipe;
      _pendExperiencia = pendExperiencia;
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
        Text(
          'Este é o espaço para acompanhar a jornada de performance e crescimento da sua equipe. '
          'Aqui você encontrará avaliações, feedbacks e PDI\'s que ajudam a reconhecer os resultados, '
          'identificar oportunidades de desenvolvimento e construir os próximos passos profissionais dos seus colaboradores.',
          style: GoogleFonts.poppins(
              fontSize: 13, color: AppColors.cinzaTexto, height: 1.5),
        ),
        const SizedBox(height: 14),
        PerformanceMateriais(materiais: _materiais),
        const SizedBox(height: 10),
        if (!_bloqueadas.contains('avaliar_periodo_experiencia_gestor'))
          PerformanceCard(
            icone: Icons.explore_outlined,
            imagemUrl: _visual['periodo_experiencia'],
            titulo: 'Período de Experiência',
            descricao:
                'Avalie o período de experiência dos colaboradores da sua equipe.',
            badge: _pendExperiencia,
            onTap: () => _abrir(const AvaliarPeriodoExperienciaGestorScreen()),
          ),
        if (!_bloqueadas.contains('avaliar_equipe_gestor'))
          PerformanceCard(
            icone: Icons.leaderboard_outlined,
            imagemUrl: _visual['avaliacao'],
            titulo: 'Avaliação de Desempenho',
            descricao: 'Avalie o desempenho da sua equipe no ciclo aberto.',
            badge: _pendEquipe,
            onTap: () => _abrir(const AvaliarEquipeScreen()),
          ),
        if (!_bloqueadas.contains('feedback_gestor'))
          PerformanceCard(
            icone: Icons.rate_review_outlined,
            imagemUrl: _visual['feedback'],
            titulo: 'Feedback',
            descricao:
                'Registre e acompanhe os feedbacks realizados com sua equipe.',
            onTap: () => _abrir(const FeedbackGestorScreen()),
          ),
        if (!_bloqueadas.contains('pdi_gestor'))
          PerformanceCard(
            icone: Icons.trending_up_outlined,
            imagemUrl: _visual['pdi'],
            titulo: 'PDI',
            descricao: 'Crie e acompanhe os PDIs da sua equipe, junto com o RH.',
            onTap: () => _abrir(const PdiGestorScreen()),
          ),
        PerformanceCard(
          icone: Icons.route_outlined,
          imagemUrl: _visual['programa_carreira'],
          titulo: 'Programa de Carreira',
          descricao:
              'Conheça o Tô na Trilha: fluxograma, critérios e formulários de promoção.',
          onTap: () => _abrir(const ToNaTrilhaScreen()),
        ),
      ],
    );
  }
}
