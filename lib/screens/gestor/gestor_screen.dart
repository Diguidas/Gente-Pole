import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import 'vagas_gestor_screen.dart';
import 'minha_equipe_screen.dart';
import 'avaliar_equipe_screen.dart';
import 'avaliar_periodo_experiencia_gestor_screen.dart';
import 'solicitacoes_gestor_screen.dart';
import 'feedback_gestor_screen.dart';
import 'exames_gestor_screen.dart';

class GestorScreen extends StatefulWidget {
  const GestorScreen({super.key});

  @override
  State<GestorScreen> createState() => _GestorScreenState();
}

class _GestorScreenState extends State<GestorScreen> {
  final _api = ApiService();
  bool _loading = true;
  Set<String> _bloqueadas = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final bloqueadas = await _api.listarFuncionalidadesGestorBloqueadas();
    if (!mounted) return;
    setState(() {
      _bloqueadas = bloqueadas;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final nome = _api.colaboradorAtual?.primeiroNome ?? 'Gestor';
    final setor = _api.colaboradorAtual?.setor ?? '';

    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 260,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 24, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Gestão de Equipe',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Olá, $nome',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (setor.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.business_outlined,
                                    color: Colors.white, size: 14),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    setor,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Corpo ────────────────────────────────────────────────
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 28),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
                            children: [
                              Text(
                                'O que deseja fazer?',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.cinzaTexto,
                                ),
                              ),
                              const SizedBox(height: 20),

                              if (!_bloqueadas.contains('vagas_gestor')) ...[
                                _BotaoGestor(
                                  icone: Icons.work_outline_rounded,
                                  titulo: 'Aumento de Quadro',
                                  subtitulo:
                                      'Solicite vagas e acompanhe candidatos',
                                  cor: AppColors.laranja,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const VagasGestorScreen(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (!_bloqueadas
                                  .contains('minha_equipe_gestor')) ...[
                                _BotaoGestor(
                                  icone: Icons.group_outlined,
                                  titulo: 'Minha Equipe',
                                  subtitulo:
                                      'Veja os colaboradores do seu setor',
                                  cor: const Color(0xFF6366F1),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const MinhaEquipeScreen(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (!_bloqueadas
                                  .contains('avaliar_equipe_gestor')) ...[
                                _BotaoGestor(
                                  icone: Icons.leaderboard_outlined,
                                  titulo: 'Avaliar Equipe',
                                  subtitulo:
                                      'Avaliação 9-box dos colaboradores do setor',
                                  cor: AppColors.laranja,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const AvaliarEquipeScreen(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (!_bloqueadas.contains(
                                  'avaliar_periodo_experiencia_gestor')) ...[
                                _BotaoGestor(
                                  icone: Icons.explore_outlined,
                                  titulo: 'Avaliar Período de Experiência',
                                  subtitulo:
                                      'Avalie novos colaboradores da equipe',
                                  cor: const Color(0xFF6366F1),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const AvaliarPeriodoExperienciaGestorScreen(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (!_bloqueadas
                                  .contains('solicitacoes_gestor')) ...[
                                _BotaoGestor(
                                  icone: Icons.assignment_outlined,
                                  titulo: 'Solicitações',
                                  subtitulo: 'Abra e aprove pedidos da equipe',
                                  cor: const Color(0xFF7C3AED),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const SolicitacoesGestorScreen(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (!_bloqueadas.contains('feedback_gestor')) ...[
                                _BotaoGestor(
                                  icone: Icons.rate_review_outlined,
                                  titulo: 'Feedback',
                                  subtitulo:
                                      'Dê feedback à equipe e responda pedidos',
                                  cor: const Color(0xFFE91E8C),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const FeedbackGestorScreen(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (!_bloqueadas.contains('exames_gestor'))
                                _BotaoGestor(
                                  icone: Icons.medical_information_outlined,
                                  titulo: 'Exames',
                                  subtitulo:
                                      'Confirme os exames marcados pelo SESMT',
                                  cor: const Color(0xFF16A34A),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ExamesGestorScreen(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BotaoGestor extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String subtitulo;
  final Color cor;
  final VoidCallback onTap;

  const _BotaoGestor({
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.cor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: cor.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: cor.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icone, color: cor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitulo,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.cinzaTexto,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cor.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}
