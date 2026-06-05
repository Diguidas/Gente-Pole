import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/vaga_model.dart';
import '../../services/api_service.dart';

class KanbanGestorScreen extends StatefulWidget {
  final VagaModel vaga;

  const KanbanGestorScreen({super.key, required this.vaga});

  @override
  State<KanbanGestorScreen> createState() => _KanbanGestorScreenState();
}

class _KanbanGestorScreenState extends State<KanbanGestorScreen> {
  final _api = ApiService();
  late Future<List<CandidaturaGestorModel>> _futureCandidatos;

  // Filtro de status
  String _filtroStatus = 'TODOS';

  @override
  void initState() {
    super.initState();
    _carregarCandidatos();
  }

  void _carregarCandidatos() {
    setState(() {
      _futureCandidatos =
          _api.listarCandidatosGestor(widget.vaga.id);
    });
  }

  List<CandidaturaGestorModel> _filtrar(List<CandidaturaGestorModel> lista) {
    if (_filtroStatus == 'TODOS') return lista;
    return lista.where((c) => c.status == _filtroStatus).toList();
  }

  @override
  Widget build(BuildContext context) {
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
                // Header
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
                              widget.vaga.titulo,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              widget.vaga.departamento ?? 'Candidatos',
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

                // Filtros rápidos
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chipFiltro('TODOS', 'Todos'),
                        _chipFiltro('ENTREV_GESTOR', 'Entrevista'),
                        _chipFiltro('PROPOSTA', 'Proposta'),
                        _chipFiltro('APROVADO', 'Aprovados'),
                        _chipFiltro('REPROVADO', 'Reprovados'),
                      ],
                    ),
                  ),
                ),

                // Lista
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: FutureBuilder<List<CandidaturaGestorModel>>(
                      future: _futureCandidatos,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.magenta));
                        }

                        final lista = _filtrar(snap.data ?? []);

                        if (lista.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.inbox_outlined,
                                      size: 56,
                                      color: AppColors.cinzaTexto),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Nenhum candidato aqui',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.dark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return RefreshIndicator(
                          color: AppColors.magenta,
                          onRefresh: () async => _carregarCandidatos(),
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 20, 16, 32),
                            itemCount: lista.length,
                            itemBuilder: (ctx, i) =>
                                _cardCandidato(lista[i]),
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

  // ── Card do candidato ────────────────────────────────────────────────────────

  Widget _cardCandidato(CandidaturaGestorModel c) {
    final cor = _corStatus(c.status);
    final labelStatus = _labelStatus(c.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          // Cabeçalho do card
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                _avatar(c.candidatoNome),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.candidatoNome,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                      Text(
                        c.candidatoEmail,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppColors.cinzaTexto,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    labelStatus,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Info extra
          if (c.salarioEsperado != null || c.candidatoCidade != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Row(
                children: [
                  if (c.candidatoCidade != null)
                    _infoChip(Icons.location_on_outlined,
                        '${c.candidatoCidade}${c.candidatoEstado != null ? ", ${c.candidatoEstado}" : ""}'),
                  if (c.salarioEsperado != null) ...[
                    const SizedBox(width: 12),
                    _infoChip(Icons.attach_money_rounded,
                        'R\$ ${c.salarioEsperado!.toStringAsFixed(0)}'),
                  ],
                ],
              ),
            ),

          // Teste prático (se a vaga tiver)
          if (widget.vaga.testePratico)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: _secaoTestePratico(c),
            ),

          // Botões de ação por status
          if (c.status == 'ENTREV_GESTOR')
            _botoesEntrevista(c)
          else if (c.status == 'PROPOSTA')
            _botoesProposta(c),

          // Acompanhamento de admissão
          if (c.status == 'APROVADO')
            _secaoAdmissao(c),

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── Teste prático ────────────────────────────────────────────────────────────

  Widget _secaoTestePratico(CandidaturaGestorModel c) {
    final status = c.testePraticoStatus;
    if (status == null && c.status == 'ENTREV_GESTOR') {
      // Gestor pode lançar resultado
      return Row(
        children: [
          Text(
            'Teste prático:',
            style: GoogleFonts.poppins(
                fontSize: 12, color: AppColors.cinzaTexto),
          ),
          const SizedBox(width: 8),
          _botaoAcaoSmall(
            label: '✓ Aprovado',
            cor: const Color(0xFF10B981),
            onTap: () => _lancarTeste(c, 'APROVADO'),
          ),
          const SizedBox(width: 6),
          _botaoAcaoSmall(
            label: '✗ Reprovado',
            cor: AppColors.magenta,
            onTap: () => _lancarTeste(c, 'REPROVADO'),
          ),
        ],
      );
    }

    final cor = status == 'APROVADO'
        ? const Color(0xFF10B981)
        : status == 'REPROVADO'
            ? AppColors.magenta
            : AppColors.cinzaTexto;

    return Row(
      children: [
        const Icon(Icons.assignment_outlined,
            size: 14, color: AppColors.cinzaTexto),
        const SizedBox(width: 6),
        Text(
          'Teste: ',
          style: GoogleFonts.poppins(
              fontSize: 12, color: AppColors.cinzaTexto),
        ),
        Text(
          status ?? 'Pendente',
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cor,
          ),
        ),
      ],
    );
  }

  // ── Botões entrevista ────────────────────────────────────────────────────────

  Widget _botoesEntrevista(CandidaturaGestorModel c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _confirmarReprovacao(c),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.magenta,
                side: const BorderSide(color: AppColors.magenta),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text('Reprovar',
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _aprovarEntrevista(c),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.laranja,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text('Aprovar',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Botões proposta ──────────────────────────────────────────────────────────

  Widget _botoesProposta(CandidaturaGestorModel c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _aprovarProposta(c),
          icon: const Icon(Icons.thumb_up_outlined,
              size: 16, color: Colors.white),
          label: Text('Confirmar Proposta',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  // ── Seção admissão ───────────────────────────────────────────────────────────

  Widget _secaoAdmissao(CandidaturaGestorModel c) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _api.buscarStatusAdmissao(c.id),
      builder: (context, snap) {
        if (!snap.hasData || snap.data == null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Row(
              children: [
                const Icon(Icons.hourglass_empty_rounded,
                    size: 14, color: AppColors.cinzaTexto),
                const SizedBox(width: 6),
                Text(
                  'Admissão sendo iniciada pelo RH',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: AppColors.cinzaTexto),
                ),
              ],
            ),
          );
        }

        final adm = snap.data!;
        final statusAdm = adm['status'] as String? ?? '';
        final steps = _stepsAdmissao();
        final idxAtual = steps.indexWhere((s) => s['key'] == statusAdm);

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Acompanhamento da admissão',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.cinzaTexto,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: List.generate(steps.length, (i) {
                  final done = idxAtual >= i;
                  return Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: done
                                      ? AppColors.laranja
                                      : const Color(0xFFE5E7EB),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  done
                                      ? Icons.check_rounded
                                      : Icons.circle_outlined,
                                  size: 14,
                                  color: done
                                      ? Colors.white
                                      : AppColors.cinzaTexto,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                steps[i]['label'] as String,
                                style: GoogleFonts.poppins(
                                  fontSize: 9,
                                  color: done
                                      ? AppColors.laranja
                                      : AppColors.cinzaTexto,
                                  fontWeight: done
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        if (i < steps.length - 1)
                          Container(
                            height: 2,
                            width: 12,
                            color: done && idxAtual > i
                                ? AppColors.laranja
                                : const Color(0xFFE5E7EB),
                          ),
                      ],
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Ações assíncronas ────────────────────────────────────────────────────────

  Future<void> _aprovarEntrevista(CandidaturaGestorModel c) async {
    final gestorId = _api.colaboradorAtual?.id ?? 0;
    final ok = await _api.aprovarEntrevistaGestor(
      candidaturaId: c.id,
      gestorId: gestorId,
    );
    if (ok) _carregarCandidatos();
    _snack(ok ? 'Candidato avançado para Proposta ✅' : 'Erro ao mover', ok);
  }

  Future<void> _confirmarReprovacao(CandidaturaGestorModel c) async {
    final motivo = await _dialogMotivo(context);
    if (motivo == null || motivo.trim().isEmpty) return;

    final gestorId = _api.colaboradorAtual?.id ?? 0;
    final ok = await _api.reprovarEntrevistaGestor(
      candidaturaId: c.id,
      gestorId: gestorId,
      motivo: motivo.trim(),
    );
    if (ok) _carregarCandidatos();
    _snack(ok ? 'Candidato reprovado' : 'Erro ao reprovar', ok);
  }

  Future<void> _aprovarProposta(CandidaturaGestorModel c) async {
    final gestorId = _api.colaboradorAtual?.id ?? 0;
    final ok = await _api.aprovarProposta(
      candidaturaId: c.id,
      gestorId: gestorId,
    );
    if (ok) _carregarCandidatos();
    _snack(ok ? 'Proposta confirmada! 🎉' : 'Erro ao confirmar', ok);
  }

  Future<void> _lancarTeste(CandidaturaGestorModel c, String resultado) async {
    final ok = await _api.lancarResultadoTeste(
      candidaturaId: c.id,
      resultado: resultado,
    );
    if (ok) _carregarCandidatos();
    _snack(ok ? 'Resultado registrado' : 'Erro ao registrar', ok);
  }

  // ── Helpers de UI ────────────────────────────────────────────────────────────

  Widget _chipFiltro(String valor, String label) {
    final sel = _filtroStatus == valor;
    return GestureDetector(
      onTap: () => setState(() => _filtroStatus = valor),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? Colors.white : Colors.white.withOpacity(0.25),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: sel ? AppColors.laranja : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _avatar(String nome) {
    final iniciais = nome.trim().split(' ').length >= 2
        ? '${nome.trim().split(' ').first[0]}${nome.trim().split(' ').last[0]}'
            .toUpperCase()
        : nome.isNotEmpty
            ? nome[0].toUpperCase()
            : '?';

    final cores = [
      AppColors.laranja,
      AppColors.magenta,
      const Color(0xFF6C63FF),
      const Color(0xFF00BFA5),
    ];
    final cor = cores[nome.codeUnits.fold(0, (a, b) => a + b) % cores.length];

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [cor, cor.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          iniciais,
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.cinzaTexto),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 11, color: AppColors.cinzaTexto)),
      ],
    );
  }

  Widget _botaoAcaoSmall({
    required String label,
    required Color cor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cor.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w600, color: cor),
        ),
      ),
    );
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'ENTREV_GESTOR':
        return AppColors.amarelo;
      case 'PROPOSTA':
        return AppColors.laranja;
      case 'APROVADO':
        return const Color(0xFF10B981);
      case 'REPROVADO':
        return AppColors.magenta;
      default:
        return AppColors.cinzaTexto;
    }
  }

  String _labelStatus(String status) {
    switch (status) {
      case 'ENTREV_GESTOR':
        return 'Entrevista';
      case 'PROPOSTA':
        return 'Proposta';
      case 'APROVADO':
        return 'Aprovado';
      case 'REPROVADO':
        return 'Reprovado';
      default:
        return status;
    }
  }

  List<Map<String, String>> _stepsAdmissao() {
    return [
      {'key': 'AGUARDANDO_DADOS', 'label': 'Dados'},
      {'key': 'DOCUMENTOS_EM_ANALISE', 'label': 'Docs'},
      {'key': 'ASO_AGENDADO', 'label': 'ASO'},
      {'key': 'CONTRATO_ENVIADO', 'label': 'Contrato'},
      {'key': 'CONCLUIDO', 'label': 'Concluído'},
    ];
  }

  void _snack(String msg, bool sucesso) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins()),
        backgroundColor:
            sucesso ? const Color(0xFF10B981) : AppColors.magenta,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<String?> _dialogMotivo(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Motivo da reprovação',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Descreva o motivo...',
            hintStyle: GoogleFonts.poppins(fontSize: 13),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            filled: true,
            fillColor: AppColors.cinzaClaro,
          ),
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: AppColors.cinzaTexto)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.magenta, elevation: 0),
            child: Text('Confirmar',
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}