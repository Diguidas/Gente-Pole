import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/vaga_model.dart';
import '../../services/api_service.dart';
import 'solicitar_vaga_screen.dart';
import 'kanban_gestor_screen.dart';

class VagasGestorScreen extends StatefulWidget {
  const VagasGestorScreen({super.key});

  @override
  State<VagasGestorScreen> createState() => _VagasGestorScreenState();
}

class _VagasGestorScreenState extends State<VagasGestorScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabController;
  late Future<List<VagaModel>> _futureVagas;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _carregarVagas();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _carregarVagas() {
    final id = _api.colaboradorAtual?.id ?? 0;
    setState(() {
      _futureVagas = _api.listarMinhasRequisicoes(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 220,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
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
                              'Aumento de Quadro',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Vagas e candidatos',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      labelColor: AppColors.laranja,
                      unselectedLabelColor: Colors.white,
                      labelStyle: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Minhas Vagas'),
                        Tab(text: 'Candidatos'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _TabMinhasVagas(
                          futureVagas: _futureVagas,
                          onRecarregar: _carregarVagas,
                          onSolicitarVaga: _abrirSolicitarVaga,
                        ),
                        _TabCandidatos(futureVagas: _futureVagas),
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

  Future<void> _abrirSolicitarVaga() async {
    final criado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SolicitarVagaScreen()),
    );
    if (criado == true) _carregarVagas();
  }
}

// ─── Tab: Minhas Vagas ────────────────────────────────────────────────────────

class _TabMinhasVagas extends StatelessWidget {
  final Future<List<VagaModel>> futureVagas;
  final VoidCallback onRecarregar;
  final VoidCallback onSolicitarVaga;

  const _TabMinhasVagas({
    required this.futureVagas,
    required this.onRecarregar,
    required this.onSolicitarVaga,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VagaModel>>(
      future: futureVagas,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.magenta));
        }

        final vagas = snap.data ?? [];

        return RefreshIndicator(
          color: AppColors.magenta,
          onRefresh: () async => onRecarregar(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            children: [
              GestureDetector(
                onTap: onSolicitarVaga,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientePrincipal,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.laranja.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.add_rounded,
                            color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Solicitar Nova Vaga',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Envia para aprovação do RH',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: Colors.white),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (vagas.isEmpty)
                _estadoVazio()
              else ...[
                Text(
                  'Suas requisições (${vagas.length})',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cinzaTexto,
                  ),
                ),
                const SizedBox(height: 12),
                ...vagas.map((v) => _cardVaga(v)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _cardVaga(VagaModel v) {
    final statusReq = v.statusRequisicao;
    final corStatus = statusReq == 'APROVADA'
        ? const Color(0xFF10B981)
        : statusReq == 'RECUSADA'
            ? AppColors.magenta
            : AppColors.amarelo;
    final labelStatus = statusReq == 'APROVADA'
        ? 'Aprovada'
        : statusReq == 'RECUSADA'
            ? 'Recusada'
            : 'Aguardando RH';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  v.titulo,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: corStatus.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  labelStatus,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: corStatus,
                  ),
                ),
              ),
            ],
          ),
          if (v.departamento != null) ...[
            const SizedBox(height: 4),
            Text(
              v.departamento!,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.cinzaTexto),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _chip(Icons.business_center_outlined, v.tipoContrato),
              const SizedBox(width: 8),
              _chip(
                  Icons.category_outlined,
                  v.tipoVaga == 'MULTIPLA'
                      ? 'Múltiplas vagas'
                      : 'Vaga única'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.cinzaTexto),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto),
        ),
      ],
    );
  }

  Widget _estadoVazio() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.work_outline_rounded,
                size: 56, color: AppColors.cinzaTexto),
            const SizedBox(height: 16),
            Text(
              'Nenhuma requisição ainda',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite uma nova vaga acima.',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.cinzaTexto),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab: Candidatos ──────────────────────────────────────────────────────────

class _TabCandidatos extends StatelessWidget {
  final Future<List<VagaModel>> futureVagas;

  const _TabCandidatos({required this.futureVagas});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VagaModel>>(
      future: futureVagas,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.magenta));
        }

        final vagasAbertas = (snap.data ?? [])
            .where((v) =>
                v.statusRequisicao == 'APROVADA' && v.status == 'ABERTA')
            .toList();

        if (vagasAbertas.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_outline_rounded,
                      size: 56, color: AppColors.cinzaTexto),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma vaga aberta',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Candidatos aparecerão quando suas\nvagas forem aprovadas pelo RH.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.cinzaTexto),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            Text(
              'Selecione uma vaga para ver os candidatos',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.cinzaTexto),
            ),
            const SizedBox(height: 14),
            ...vagasAbertas.map(
              (v) => GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => KanbanGestorScreen(vaga: v),
                  ),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x08000000),
                          blurRadius: 8,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.laranja.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.people_outline_rounded,
                            color: AppColors.laranja),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              v.titulo,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.dark,
                              ),
                            ),
                            if (v.departamento != null)
                              Text(
                                v.departamento!,
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: AppColors.cinzaTexto),
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: AppColors.cinzaTexto),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
