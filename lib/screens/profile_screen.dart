import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import '../screens/login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colaborador = ApiService().colaboradorAtual;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // AppBar com gradiente e avatar
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.gradientePrincipal,
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      // Avatar
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.25),
                          border: Border.all(color: Colors.white, width: 3),
                          image: colaborador?.fotoUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(colaborador!.fotoUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: colaborador?.fotoUrl == null
                            ? Center(
                                child: Text(
                                  _iniciais(colaborador?.nome ?? '?'),
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        colaborador?.nome ?? 'Colaborador',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (colaborador?.cargo != null)
                        Text(
                          colaborador!.cargo!,
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Título compacto quando rola
            title: Text(
              colaborador?.primeiroNome ?? 'Perfil',
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.laranja,
          ),

          // Conteúdo
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _secao('Informações'),
                  _infoCard([
                    _linha(
                      Icons.badge_outlined,
                      'Matrícula',
                      colaborador?.matricula ?? '—',
                    ),
                    _linha(
                      Icons.work_outline_rounded,
                      'Cargo',
                      colaborador?.cargo ?? '—',
                    ),
                    _linha(
                      Icons.apartment_rounded,
                      'Setor',
                      colaborador?.setor ?? '—',
                    ),
                    _linha(
                      Icons.calendar_today_outlined,
                      'Admissão',
                      colaborador?.dataAdmissaoFormatada ?? '—',
                    ),
                  ]),

                  const SizedBox(height: 20),
                  _secao('Conta'),
                  _infoCard([
                    _botaoAcao(
                      context,
                      icon: Icons.lock_outline_rounded,
                      label: 'Alterar senha',
                      onTap: () {
                        // TODO: tela de alterar senha
                      },
                    ),
                  ]),

                  const SizedBox(height: 20),
                  _infoCard([
                    _botaoAcao(
                      context,
                      icon: Icons.logout_rounded,
                      label: 'Sair da conta',
                      cor: AppColors.magenta,
                      onTap: () => _confirmarSaida(context),
                    ),
                  ]),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Widgets auxiliares ───────────────────────────────────────────────────────

  Widget _secao(String titulo) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(
          titulo,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.cinzaTexto,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _infoCard(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 12,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(children: children),
      );

  Widget _linha(IconData icon, String label, String valor) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.laranja),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.cinzaTexto,
                    ),
                  ),
                  Text(
                    valor,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.dark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _botaoAcao(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color cor = AppColors.dark,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cor),
              const SizedBox(width: 14),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: cor,
                ),
              ),
              const Spacer(),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.cinzaTexto, size: 20),
            ],
          ),
        ),
      );

  // ─── Helpers ──────────────────────────────────────────────────────────────────

  String _iniciais(String nome) {
    final partes = nome.trim().split(' ');
    if (partes.length >= 2) {
      return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
    }
    return nome.isNotEmpty ? nome[0].toUpperCase() : '?';
  }

  void _confirmarSaida(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Sair da conta?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text('Você precisará digitar sua matrícula e senha novamente.',
            style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: AppColors.cinzaTexto)),
          ),
          ElevatedButton(
            onPressed: () {
              ApiService().limparSessao();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            child: Text('Sair',
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}