import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import 'vagas_gestor_screen.dart';
import 'minha_equipe_screen.dart';
import 'solicitacoes_gestor_screen.dart';
import 'facilites_gestor_screen.dart';
import 'exames_gestor_screen.dart';
import 'candidaturas_gestor_screen.dart';
import 'requisitantes_screen.dart';
import '../performance/performance_gestor_screen.dart';

class GestorScreen extends StatefulWidget {
  /// true quando quem abriu é só requisitante de vaga (sem ser gestor/líder
  /// de verdade) — restringe o menu só ao "Aumento de Quadro", ignorando o
  /// bloqueio granular de [_bloqueadas] (que é pra quem já tem acesso pleno).
  final bool apenasVagas;

  const GestorScreen({super.key, this.apenasVagas = false});

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

                // ── Corpo ────────────────────────────────────────────────
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 28),
                    clipBehavior: Clip.antiAlias,
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

                              if (!widget.apenasVagas) ...[
                              // Igual ao web: Requisitantes não tem bloqueio
                              // próprio nem some com o bloqueio de Vagas.
                              _BotaoGestor(
                                icone: Icons.person_pin_circle_outlined,
                                titulo: 'Requisitantes de vaga',
                                subtitulo:
                                    'Defina quem pode requisitar vagas por função',
                                cor: const Color(0xFF0EA5E9),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const RequisitantesScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (!_bloqueadas
                                  .contains('minha_equipe_gestor')) ...[
                                _BotaoGestor(
                                  icone: Icons.group_outlined,
                                  titulo: 'Minha Equipe',
                                  subtitulo:
                                      'Veja os colaboradores da sua equipe',
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

                              _BotaoGestor(
                                icone: Icons.trending_up_rounded,
                                titulo: 'Performance',
                                subtitulo:
                                    'Avaliações, feedbacks, PDI e carreira da sua equipe',
                                cor: const Color(0xFF5B2C9F),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const PerformanceGestorScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

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

                              if (!_bloqueadas
                                  .contains('facilites_gestor')) ...[
                                _BotaoGestor(
                                  icone: Icons.apartment_outlined,
                                  titulo: 'Facilites',
                                  subtitulo:
                                      'Uber, Móveis Administrativos e Rota diária',
                                  cor: const Color(0xFFF59E0B),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const FacilitesGestorScreen(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (!_bloqueadas.contains('exames_gestor')) ...[
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
                                const SizedBox(height: 16),
                              ],

                              if (!_bloqueadas
                                  .contains('candidaturas_gestor')) ...[
                                _BotaoGestor(
                                  icone: Icons.how_to_reg_outlined,
                                  titulo: 'Candidaturas',
                                  subtitulo:
                                      'Aprove quem da equipe quer se candidatar a vagas',
                                  cor: const Color(0xFF0EA5E9),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const CandidaturasGestorScreen(),
                                    ),
                                  ),
                                ),
                              ],
                              ],
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
