import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';
import '../models/comunicado_model.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Callback para navegar para a aba de Comunicados no MainLayout
  final VoidCallback? onVerComunicados;

  const HomeScreen({super.key, this.onVerComunicados});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  late Future<List<ComunicadoModel>> _futureComunicados;

  @override
  void initState() {
    super.initState();
    _futureComunicados = _api.buscarUltimosComunicados();
  }

  // ── Build principal ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colaborador = _api.colaboradorAtual;

    return Scaffold(
      body: Stack(
        children: [
          // Gradiente de fundo no topo
          Container(
            height: 240,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ── Header: dados do usuário ─────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      // Avatar
                      _avatarUsuario(colaborador?.nome ?? ''),

                      const SizedBox(width: 14),

                      // Nome + cargo·setor
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Olá, ${colaborador?.primeiroNome ?? ''} 👋',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              [colaborador?.cargo, colaborador?.setor]
                                  .where((e) => e != null && e!.isNotEmpty)
                                  .join(' · '),
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Botão alterar senha
                      _headerIconButton(
                        icon: Icons.lock_outline_rounded,
                        tooltip: 'Alterar senha',
                        onTap: () => _abrirAlterarSenha(context),
                      ),

                      // Botão sair
                      _headerIconButton(
                        icon: Icons.logout_rounded,
                        tooltip: 'Sair',
                        onTap: () => _confirmarSaida(context),
                      ),
                    ],
                  ),
                ),

                // Informações do colaborador (matrícula + admissão)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _chipInfo(
                        Icons.badge_outlined,
                        'Matrícula',
                        colaborador?.matricula ?? '—',
                      ),
                      const SizedBox(width: 10),
                      _chipInfo(
                        Icons.calendar_today_outlined,
                        'Admissão',
                        colaborador?.dataAdmissaoFormatada ?? '—',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Corpo (fundo branco arredondado) ────────────────────────
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: FutureBuilder<List<ComunicadoModel>>(
                      future: _futureComunicados,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.magenta),
                          );
                        }

                        final lista = snap.data ?? [];

                        return RefreshIndicator(
                          color: AppColors.magenta,
                          onRefresh: () async => setState(() {
                            _futureComunicados =
                                _api.buscarUltimosComunicados();
                          }),
                          child: ListView(
                            padding:
                                const EdgeInsets.fromLTRB(16, 24, 16, 32),
                            children: [
                              // ── Comunicado em destaque ───────────────────
                              if (lista.isNotEmpty) ...[
                                _labelSecao('📢 Em destaque'),
                                const SizedBox(height: 10),
                                _cardDestaque(lista.first),
                                const SizedBox(height: 24),
                              ],

                              // ── Últimos comunicados ──────────────────────
                              if (lista.length > 1) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _labelSecao('Últimos comunicados'),
                                    TextButton(
                                      onPressed: widget.onVerComunicados,
                                      child: Text(
                                        'Ver todos',
                                        style: GoogleFonts.poppins(
                                          color: AppColors.magenta,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...lista
                                    .skip(1)
                                    .take(3)
                                    .map(_cardComunicadoSimples),
                              ],

                              // Sem comunicados
                              if (lista.isEmpty)
                                _semComunicados(),
                            ],
                          ),
                        );
                      },
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

  // ── Card de destaque ─────────────────────────────────────────────────────────

  Widget _cardDestaque(ComunicadoModel c) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.magenta.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Foto (se tiver) ou banner colorido
            if (c.fotoUrl != null && c.fotoUrl!.isNotEmpty)
              Image.network(
                c.fotoUrl!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.fitWidth,
                errorBuilder: (_, __, ___) => _bannerSemFoto(),
              )
            else
              _bannerSemFoto(),

            // Texto
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.titulo,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.dark,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (c.descricao != null && c.descricao!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      c.descricao!,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.cinzaTexto,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    c.dataFormatada,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.cinzaTexto,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bannerSemFoto() => Container(
        height: 120,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppColors.gradientePrincipal,
        ),
        child: const Center(
          child: Icon(Icons.campaign_rounded, color: Colors.white, size: 48),
        ),
      );

  // ── Card simples (lista) ─────────────────────────────────────────────────────

  Widget _cardComunicadoSimples(ComunicadoModel c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Mini ícone ou miniatura
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppColors.laranja.withOpacity(0.1),
              ),
              child: c.fotoUrl != null && c.fotoUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        c.fotoUrl!,
                        fit: BoxFit.fitWidth,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.campaign_outlined,
                            color: AppColors.laranja,
                            size: 22),
                      ),
                    )
                  : const Icon(Icons.campaign_outlined,
                      color: AppColors.laranja, size: 22),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.titulo,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.dark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    c.dataFormatada,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.cinzaTexto,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(Icons.chevron_right_rounded,
                color: AppColors.cinzaTexto, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Widgets de apoio ─────────────────────────────────────────────────────────

  Widget _avatarUsuario(String nome) {
    final iniciais = _iniciais(nome);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.25),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          iniciais,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _headerIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      );

  Widget _chipInfo(IconData icon, String label, String valor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    valor,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelSecao(String texto) => Text(
        texto,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.dark,
        ),
      );

  Widget _semComunicados() => Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Column(
            children: [
              const Icon(Icons.campaign_outlined,
                  size: 52, color: AppColors.cinzaTexto),
              const SizedBox(height: 12),
              Text(
                'Nenhum comunicado ainda',
                style: GoogleFonts.poppins(
                    fontSize: 15, color: AppColors.cinzaTexto),
              ),
            ],
          ),
        ),
      );

  // ── Modals ───────────────────────────────────────────────────────────────────

  void _abrirAlterarSenha(BuildContext context) {
    final senhaAtualCtrl = TextEditingController();
    final novaSenhaCtrl = TextEditingController();
    bool enviando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.cinzaTexto.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  '🔒 Alterar senha',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: senhaAtualCtrl,
                  obscureText: true,
                  style: GoogleFonts.poppins(),
                  decoration: const InputDecoration(
                    labelText: 'Senha atual',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: novaSenhaCtrl,
                  obscureText: true,
                  style: GoogleFonts.poppins(),
                  decoration: const InputDecoration(
                    labelText: 'Nova senha',
                    prefixIcon: Icon(Icons.lock_reset_rounded),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: enviando
                        ? null
                        : () async {
                            final atual = senhaAtualCtrl.text.trim();
                            final nova = novaSenhaCtrl.text.trim();
                            if (atual.isEmpty || nova.length < 6) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Nova senha deve ter pelo menos 6 caracteres.',
                                    style: GoogleFonts.poppins(),
                                  ),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              return;
                            }
                            setModalState(() => enviando = true);
                            final ok = await _api.alterarSenha(
                              senhaAtual: atual,
                              novaSenha: nova,
                            );
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Senha alterada com sucesso!'
                                      : 'Senha atual incorreta.',
                                  style: GoogleFonts.poppins(),
                                ),
                                backgroundColor:
                                    ok ? AppColors.magenta : Colors.red,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.magenta,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: enviando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'Salvar',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmarSaida(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              _api.limparSessao();
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

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _iniciais(String nome) {
    final p = nome.trim().split(' ');
    return p.length >= 2
        ? '${p.first[0]}${p.last[0]}'.toUpperCase()
        : nome.isNotEmpty
            ? nome[0].toUpperCase()
            : '?';
  }
}