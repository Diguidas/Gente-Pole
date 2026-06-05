import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';
import '../models/aniversariante_model.dart';
import '../services/api_service.dart';

class AniversariantesScreen extends StatefulWidget {
  const AniversariantesScreen({super.key});

  @override
  State<AniversariantesScreen> createState() => _AniversariantesScreenState();
}

class _AniversariantesScreenState extends State<AniversariantesScreen> {
  final _api = ApiService();
  late Future<List<AniversarianteModel>> _future;

  // Matrícula de quem já recebeu parabéns nesta sessão (evita duplicar)
  final Set<int> _jaParabenisei = {};

  @override
  void initState() {
    super.initState();
    _future = _api.buscarAniversariantesMes();
  }

  void _recarregar() => setState(() {
        _future = _api.buscarAniversariantesMes();
      });

  // ─── UI principal ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Gradiente de fundo no topo
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
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🎂 Aniversariantes',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _mesAtual(),
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _recarregar,
                        icon: const Icon(Icons.refresh_rounded,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),

                // Conteúdo com card flutuante
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: FutureBuilder<List<AniversarianteModel>>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.magenta,
                            ),
                          );
                        }
                        if (snap.hasError) {
                          return _erroWidget();
                        }

                        final lista = snap.data ?? [];
                        if (lista.isEmpty) return _vazioWidget();

                        final hoje =
                            lista.where((a) => a.ehHoje).toList();
                        final restante =
                            lista.where((a) => !a.ehHoje).toList();

                        return RefreshIndicator(
                          color: AppColors.magenta,
                          onRefresh: () async => _recarregar(),
                          child: CustomScrollView(
                            slivers: [
                              // ── Aniversariantes de hoje ──────────────────
                              if (hoje.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 24, 20, 12),
                                    child: Text(
                                      'Hoje 🎉',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.dark,
                                      ),
                                    ),
                                  ),
                                ),
                                SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (ctx, i) => _cardHoje(hoje[i]),
                                    childCount: hoje.length,
                                  ),
                                ),
                              ],

                              // ── Demais do mês ────────────────────────────
                              if (restante.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 24, 20, 12),
                                    child: Text(
                                      'Este mês',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.dark,
                                      ),
                                    ),
                                  ),
                                ),
                                SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (ctx, i) => _itemMes(restante[i]),
                                    childCount: restante.length,
                                  ),
                                ),
                              ],

                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 32)),
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

  // ─── Card destaque (aniversário hoje) ────────────────────────────────────────

  Widget _cardHoje(AniversarianteModel a) {
    final jaParabenisei = _jaParabenisei.contains(a.colaborador.id);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B00), Color(0xFFE91E8C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.magenta.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Avatar
            _avatar(a.colaborador, raio: 30, fonteGrande: true),
            const SizedBox(width: 16),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.colaborador.nome,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (a.colaborador.setor != null)
                    Text(
                      a.colaborador.setor!,
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Hoje é dia de celebrar! 🎊',
                    style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  if (a.totalParabens > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${a.totalParabens} parabéns recebidos',
                        style: GoogleFonts.poppins(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Botão parabenizar
            GestureDetector(
              onTap: jaParabenisei
                  ? null
                  : () => _abrirModalParabens(a),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: jaParabenisei
                      ? Colors.white.withOpacity(0.2)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  jaParabenisei ? '✓ Enviado' : '🎉 Parabenizar',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: jaParabenisei
                        ? Colors.white.withOpacity(0.7)
                        : AppColors.magenta,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Item lista (demais do mês) ───────────────────────────────────────────────

  Widget _itemMes(AniversarianteModel a) {
    final jaParabenisei = _jaParabenisei.contains(a.colaborador.id);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Data badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.laranja.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  a.diaNascimento.toString().padLeft(2, '0'),
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: AppColors.laranja,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Avatar pequeno
            _avatar(a.colaborador, raio: 18),
            const SizedBox(width: 12),

            // Nome + setor
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.colaborador.nome,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.dark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (a.colaborador.setor != null)
                    Text(
                      a.colaborador.setor!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.cinzaTexto,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Botão parabenizar
            TextButton(
              onPressed: jaParabenisei
                  ? null
                  : () => _abrirModalParabens(a),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.magenta,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: jaParabenisei
                        ? AppColors.cinzaTexto.withOpacity(0.3)
                        : AppColors.magenta.withOpacity(0.4),
                  ),
                ),
              ),
              child: Text(
                jaParabenisei ? '✓' : 'Parabenizar',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: jaParabenisei
                      ? AppColors.cinzaTexto
                      : AppColors.magenta,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Modal de parabéns ────────────────────────────────────────────────────────

  void _abrirModalParabens(AniversarianteModel a) {
    final controller = TextEditingController(
      text:
          'Feliz aniversário, ${a.colaborador.primeiroNome}! 🎉 Que seu dia seja incrível!',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ModalParabens(
        aniversariante: a,
        controller: controller,
        onEnviar: (mensagem) async {
          final ok = await _api.enviarParabens(
            destinatarioId: a.colaborador.id,
            mensagem: mensagem,
          );
          if (!mounted) return;
          if (ok) {
            setState(() => _jaParabenisei.add(a.colaborador.id));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Parabéns enviado para ${a.colaborador.primeiroNome}! 🎊',
                  style: GoogleFonts.poppins(),
                ),
                backgroundColor: AppColors.magenta,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao enviar. Tente novamente.',
                    style: GoogleFonts.poppins()),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────────

  Widget _avatar(colaborador, {double raio = 22, bool fonteGrande = false}) {
    final iniciais = _iniciais(colaborador.nome);
    return CircleAvatar(
      radius: raio,
      backgroundColor: AppColors.laranja.withOpacity(0.2),
      backgroundImage:
          colaborador.fotoUrl != null ? NetworkImage(colaborador.fotoUrl!) : null,
      child: colaborador.fotoUrl == null
          ? Text(
              iniciais,
              style: GoogleFonts.poppins(
                fontSize: fonteGrande ? 18 : 12,
                fontWeight: FontWeight.w700,
                color: AppColors.laranja,
              ),
            )
          : null,
    );
  }

  String _iniciais(String nome) {
    final p = nome.trim().split(' ');
    return p.length >= 2
        ? '${p.first[0]}${p.last[0]}'.toUpperCase()
        : nome.isNotEmpty
            ? nome[0].toUpperCase()
            : '?';
  }

  String _mesAtual() {
    const meses = [
      '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];
    final now = DateTime.now();
    return '${meses[now.month]} ${now.year}';
  }

  Widget _erroWidget() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.cinzaTexto, size: 48),
            const SizedBox(height: 12),
            Text('Erro ao carregar',
                style: GoogleFonts.poppins(color: AppColors.cinzaTexto)),
            TextButton(
                onPressed: _recarregar,
                child: const Text('Tentar novamente')),
          ],
        ),
      );

  Widget _vazioWidget() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎂', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              'Nenhum aniversariante este mês',
              style: GoogleFonts.poppins(color: AppColors.cinzaTexto),
            ),
          ],
        ),
      );
}

// ─── Modal de parabéns (widget separado) ─────────────────────────────────────

class _ModalParabens extends StatefulWidget {
  final AniversarianteModel aniversariante;
  final TextEditingController controller;
  final Future<void> Function(String mensagem) onEnviar;

  const _ModalParabens({
    required this.aniversariante,
    required this.controller,
    required this.onEnviar,
  });

  @override
  State<_ModalParabens> createState() => _ModalParabensState();
}

class _ModalParabensState extends State<_ModalParabens> {
  bool _enviando = false;

  // Mensagens rápidas sugeridas
  static const _sugestoes = [
    '🎂 Feliz aniversário! Muitas felicidades!',
    '🥳 Parabéns! Que venham muitas conquistas!',
    '🎊 Feliz aniversário! Que seu dia seja especial!',
    '✨ Mais um ano de vida e conquistas. Parabéns!',
  ];

  @override
  Widget build(BuildContext context) {
    final a = widget.aniversariante;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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

            // Cabeçalho
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.laranja.withOpacity(0.15),
                  child: Text(
                    _iniciais(a.colaborador.nome),
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.laranja,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Parabenizar ${a.colaborador.primeiroNome}',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: AppColors.dark,
                        ),
                      ),
                      if (a.colaborador.setor != null)
                        Text(
                          a.colaborador.setor!,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.cinzaTexto,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Mensagens rápidas
            Text(
              'Sugestões',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.cinzaTexto,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _sugestoes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => GestureDetector(
                  onTap: () => setState(
                      () => widget.controller.text = _sugestoes[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.magenta.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.magenta.withOpacity(0.2)),
                    ),
                    child: Text(
                      _sugestoes[i],
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.magenta,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Campo de mensagem
            TextField(
              controller: widget.controller,
              maxLines: 3,
              maxLength: 280,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Escreva sua mensagem...',
                hintStyle: GoogleFonts.poppins(color: AppColors.cinzaTexto),
                filled: true,
                fillColor: AppColors.cinzaClaro,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 16),

            // Botão enviar
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _enviando
                    ? null
                    : () async {
                        final msg = widget.controller.text.trim();
                        if (msg.isEmpty) return;
                        setState(() => _enviando = true);
                        await widget.onEnviar(msg);
                        if (mounted) Navigator.pop(context);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.magenta,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: _enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        '🎉 Enviar parabéns',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _iniciais(String nome) {
    final p = nome.trim().split(' ');
    return p.length >= 2
        ? '${p.first[0]}${p.last[0]}'.toUpperCase()
        : nome.isNotEmpty
            ? nome[0].toUpperCase()
            : '?';
  }
}