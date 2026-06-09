import 'package:flutter/material.dart';
import 'package:gentepole/screens/lojinha/lojinha_home_screen.dart';
import 'package:gentepole/screens/lojinha/lojinha_screen.dart';
import 'package:gentepole/screens/massoterapia/massoterapia_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import 'gestor/gestor_screen.dart';

class ServicosScreen extends StatefulWidget {
  const ServicosScreen({super.key});

  @override
  State<ServicosScreen> createState() => _ServicosScreenState();
}

class _ServicosScreenState extends State<ServicosScreen> {
  final _api = ApiService();
  bool _ehGestor = false;
  bool _loadingGestor = true;

  @override
  void initState() {
    super.initState();
    _verificarGestor();
  }

  Future<void> _verificarGestor() async {
    final resultado = await _api.verificarSeEhGestor();
    if (mounted)
      setState(() {
        _ehGestor = resultado;
        _loadingGestor = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiService();
    final colaborador = api.colaboradorAtual;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 200,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⚡ Serviços',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Benefícios para você',
                        style: GoogleFonts.poppins(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Corpo ─────────────────────────────────────────────────
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_loadingGestor) const SizedBox.shrink(),
                          if (!_loadingGestor && _ehGestor) ...[
                            Text(
                              'Painel do Gestor',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: AppColors.laranja,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _botaoServico(
                              context,
                              icone: Icons.work_outline_rounded,
                              titulo: 'Painel do Gestor',
                              subtitulo:
                                  'Solicite vagas e acompanhe candidatos',
                              cor: AppColors.laranja,
                              emBreve: false,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const GestorScreen(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Serviços para Colaboradores',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: AppColors.cinzaTexto,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 4),
                            Text(
                              'Serviços para Colaboradores',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: AppColors.cinzaTexto,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),

                          // ── Lojinha ──────────────────────────────────────
                          _botaoServico(
                            context,
                            icone: Icons.storefront_outlined,
                            titulo: 'Lojinha',
                            subtitulo: 'Produtos e benefícios exclusivos',
                            cor: AppColors.laranja,
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LojinhaHomeScreen(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // ── Massoterapia ─────────────────────────────────
                          _botaoServico(
                            context,
                            icone: Icons.self_improvement_rounded,
                            titulo: 'Massoterapia',
                            subtitulo: 'Agende sua sessão de bem-estar',
                            cor: AppColors.magenta,
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MassoterapiaScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
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

  Widget _botaoServico(
    BuildContext context, {
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required Color cor,
    required bool emBreve,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap:
          onTap ??
          () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$titulo estará disponível em breve! 🚀',
                  style: GoogleFonts.poppins(),
                ),
                backgroundColor: cor,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          },
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
        ),
        child: Row(
          children: [
            // Ícone
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

            // Texto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          titulo,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark,
                          ),
                        ),
                      ),
                      if (emBreve) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Em breve',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: cor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AppColors.cinzaTexto,
                    ),
                  ),
                ],
              ),
            ),

            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.cinzaTexto,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
