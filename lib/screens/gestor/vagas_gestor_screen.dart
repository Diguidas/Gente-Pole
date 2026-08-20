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

class _VagasGestorScreenState extends State<VagasGestorScreen> {
  final _api = ApiService();
  late Future<List<VagaModel>> _futureVagas;
  Map<int, int> _aprovadosPorVaga = {};

  @override
  void initState() {
    super.initState();
    _carregarVagas();
  }

  void _carregarVagas() {
    final id = _api.colaboradorAtual?.id ?? 0;
    final future = _api.listarMinhasRequisicoes(id);
    setState(() {
      _futureVagas = future;
    });
    future.then((vagas) async {
      final aprovadasIds = vagas
          .where((v) => v.statusRequisicao == 'APROVADA')
          .map((v) => v.id)
          .toList();
      final contagem = await _api.contarAprovadosPorVaga(aprovadasIds);
      if (mounted) setState(() => _aprovadosPorVaga = contagem);
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
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: _TabMinhasVagas(
                      futureVagas: _futureVagas,
                      aprovadosPorVaga: _aprovadosPorVaga,
                      onRecarregar: _carregarVagas,
                      onSolicitarVaga: _abrirSolicitarVaga,
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
  final Map<int, int> aprovadosPorVaga;
  final VoidCallback onRecarregar;
  final VoidCallback onSolicitarVaga;

  const _TabMinhasVagas({
    required this.futureVagas,
    required this.aprovadosPorVaga,
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
                ...vagas.map((v) => _cardVaga(
                    context, v, aprovadosPorVaga[v.id] ?? 0)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _cardVaga(BuildContext context, VagaModel v, int totalAprovados) {
    final statusReq = v.statusRequisicao;
    final vagaPreenchida =
        statusReq == 'APROVADA' && totalAprovados >= v.quantidadeVagas;

    Color corStatus;
    String labelStatus;
    if (vagaPreenchida) {
      corStatus = AppColors.cinzaTexto;
      labelStatus = 'Vaga preenchida';
    } else if (statusReq == 'APROVADA') {
      corStatus = const Color(0xFF10B981);
      labelStatus = 'Aprovada';
    } else if (statusReq == 'RECUSADA') {
      corStatus = AppColors.magenta;
      labelStatus = 'Recusada';
    } else {
      corStatus = AppColors.amarelo;
      labelStatus = 'Aguardando RH';
    }
    final podeVerCandidatos = statusReq == 'APROVADA' && v.status == 'ABERTA';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: podeVerCandidatos
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => KanbanGestorScreen(vaga: v),
                    ),
                  )
              : null,
          child: Padding(
            padding: const EdgeInsets.all(18),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
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
                    if (podeVerCandidatos) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded,
                          size: 20, color: AppColors.cinzaTexto),
                    ],
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
                if (statusReq == 'APROVADA') ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (vagaPreenchida
                                  ? AppColors.cinzaTexto
                                  : const Color(0xFF10B981))
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                            '$totalAprovados de ${v.quantidadeVagas} aprovados',
                            style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: vagaPreenchida
                                    ? AppColors.cinzaTexto
                                    : const Color(0xFF10B981))),
                      ),
                      if (podeVerCandidatos) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.laranja.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('Ver candidatos',
                              style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.laranja)),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
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

