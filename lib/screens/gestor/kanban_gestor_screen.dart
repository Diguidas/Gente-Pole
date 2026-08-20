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
  String _filtroStatus = 'TODOS';

  // Grupos para os chips de filtro
  static const _grupoTriagem = {'INSCRITO', 'TRIAGEM', 'AVALIACAO_COMP', 'ENTREV_RH'};
  static const _grupoEntrevista = {'ENTREV_GESTOR', 'PROPOSTA'};
  static const _grupoAso = {'AGUARDANDO_SESMT', 'ASO_AGENDADO', 'ASO_REALIZADO', 'ASO_APROVADO'};
  static const _grupoAdmissao = {
    'AGUARDANDO_DADOS', 'ADMISSAO_INICIADA', 'DADOS_ENVIADOS',
    'DOCUMENTOS_EM_ANALISE', 'DOCUMENTOS_APROVADOS',
  };
  static const _grupoContrato = {'CONTRATO_ENVIADO', 'CONTRATO_ASSINADO'};

  // Status que entram na barra de progresso
  static const _statusProgresso = {
    'AGUARDANDO_SESMT', 'ASO_AGENDADO', 'ASO_REALIZADO', 'ASO_APROVADO',
    'AGUARDANDO_DADOS', 'ADMISSAO_INICIADA', 'DADOS_ENVIADOS',
    'DOCUMENTOS_EM_ANALISE', 'DOCUMENTOS_APROVADOS',
    'CONTRATO_ENVIADO', 'CONTRATO_ASSINADO', 'INTEGRACAO',
  };

  @override
  void initState() {
    super.initState();
    _carregarCandidatos();
  }

  void _carregarCandidatos() {
    if (!mounted) return;
    setState(() {
      _futureCandidatos = _api.listarCandidatosGestor(widget.vaga.id);
    });
  }

  List<CandidaturaGestorModel> _filtrar(List<CandidaturaGestorModel> lista) {
    switch (_filtroStatus) {
      case 'GRUPO_TRIAGEM':
        return lista.where((c) => _grupoTriagem.contains(c.statusEfetivo)).toList();
      case 'GRUPO_ENTREVISTA':
        return lista.where((c) => _grupoEntrevista.contains(c.statusEfetivo)).toList();
      case 'GRUPO_ASO':
        return lista.where((c) => _grupoAso.contains(c.statusEfetivo)).toList();
      case 'GRUPO_ADMISSAO':
        return lista.where((c) => _grupoAdmissao.contains(c.statusEfetivo)).toList();
      case 'GRUPO_CONTRATO':
        return lista.where((c) => _grupoContrato.contains(c.statusEfetivo)).toList();
      case 'INTEGRACAO':
        return lista.where((c) => c.statusEfetivo == 'INTEGRACAO').toList();
      default:
        return lista;
    }
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

                // Filtros
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chipFiltro('TODOS', 'Todos'),
                        _chipFiltro('GRUPO_TRIAGEM', 'Triagem'),
                        _chipFiltro('GRUPO_ENTREVISTA', 'Entrevista'),
                        _chipFiltro('GRUPO_ASO', 'ASO'),
                        _chipFiltro('GRUPO_ADMISSAO', 'Admissão'),
                        _chipFiltro('GRUPO_CONTRATO', 'Contrato'),
                        _chipFiltro('INTEGRACAO', 'Integração'),
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
                                      size: 56, color: AppColors.cinzaTexto),
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
                            itemBuilder: (ctx, i) => _cardCandidato(lista[i]),
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

  // ── Card ─────────────────────────────────────────────────────────────────────

  Widget _cardCandidato(CandidaturaGestorModel c) {
    final cor = _corStatus(c.statusEfetivo);
    final label = _labelStatus(c.statusEfetivo);

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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _abrirFicha(c),
          child: Column(
        children: [
          // Cabeçalho
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
                            fontSize: 11, color: AppColors.cinzaTexto),
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
                    label,
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

          // Info extra (localização / salário)
          if (c.candidatoCidade != null || c.salarioEsperado != null)
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

          // Botões de entrevista
          if (c.statusEfetivo == 'ENTREV_GESTOR') _botoesEntrevista(c),

          // Botão de proposta
          if (c.statusEfetivo == 'PROPOSTA') _botaoProposta(c),

          // Barra de progresso (a partir do ASO)
          if (_statusProgresso.contains(c.statusEfetivo)) _barraProgresso(c),

          const SizedBox(height: 4),
        ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirFicha(CandidaturaGestorModel c) async {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _FichaCandidatoDialog(candidato: c),
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

  // ── Botão proposta ───────────────────────────────────────────────────────────

  Widget _botaoProposta(CandidaturaGestorModel c) {
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  // ── Barra de progresso (ASO → Admissão → Contrato → Integração) ──────────────

  Widget _barraProgresso(CandidaturaGestorModel c) {
    final idx = _idxProgresso(c.statusEfetivo);
    const steps = [
      {'label': 'ASO'},
      {'label': 'Admissão'},
      {'label': 'Contrato'},
      {'label': 'Integração'},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Progresso',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.cinzaTexto,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(steps.length, (i) {
              final concluido = idx > i;
              final atual = idx == i;
              final cor = atual
                  ? AppColors.laranja
                  : concluido
                      ? const Color(0xFF10B981)
                      : const Color(0xFFE5E7EB);
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
                              color: cor,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              atual
                                  ? Icons.radio_button_checked_rounded
                                  : concluido
                                      ? Icons.check_rounded
                                      : Icons.circle_outlined,
                              size: 14,
                              color: (atual || concluido)
                                  ? Colors.white
                                  : AppColors.cinzaTexto,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            steps[i]['label']!,
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: (atual || concluido)
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: atual
                                  ? AppColors.laranja
                                  : concluido
                                      ? const Color(0xFF10B981)
                                      : AppColors.cinzaTexto,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    if (i < steps.length - 1)
                      Container(
                        height: 2,
                        width: 10,
                        color: concluido
                            ? const Color(0xFF10B981)
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
  }

  // 0=ASO, 1=Admissão, 2=Contrato, 3=Integração
  int _idxProgresso(String status) {
    if (_grupoAso.contains(status) || status == 'APROVADO') return 0;
    if (_grupoAdmissao.contains(status)) return 1;
    if (_grupoContrato.contains(status)) return 2;
    if (status == 'INTEGRACAO') return 3;
    return -1;
  }

  // ── Ações ────────────────────────────────────────────────────────────────────

  Future<void> _aprovarEntrevista(CandidaturaGestorModel c) async {
    final parecer = await _dialogParecer(
      context,
      titulo: 'Parecer da entrevista',
      instrucao:
          'Vai avançar ${c.candidatoNome} para a Proposta. Se quiser, registre '
          'seu parecer sobre a entrevista (pontos fortes, riscos, adequação à vaga).',
      obrigatorio: false,
      hint: 'Descreva o parecer (opcional)...',
    );
    if (parecer == null) return;
    final ok = await _api.aprovarEntrevistaGestor(
      candidaturaId: c.id,
      gestorId: _api.colaboradorAtual?.id ?? 0,
      observacao: parecer.isEmpty ? null : parecer,
    );
    if (ok) _carregarCandidatos();
    _snack(ok ? 'Candidato avançado para Proposta ✅' : 'Erro ao mover', ok);
  }

  Future<void> _confirmarReprovacao(CandidaturaGestorModel c) async {
    final motivo = await _dialogParecer(
      context,
      titulo: 'Motivo da reprovação',
      instrucao:
          'Descreva o motivo pelo qual ${c.candidatoNome} está sendo reprovado(a) '
          'nesta etapa.',
      hint: 'Descreva o motivo...',
      corDestaque: AppColors.magenta,
    );
    if (motivo == null || motivo.isEmpty) return;
    final ok = await _api.reprovarEntrevistaGestor(
      candidaturaId: c.id,
      gestorId: _api.colaboradorAtual?.id ?? 0,
      motivo: motivo,
    );
    if (ok) _carregarCandidatos();
    _snack(ok ? 'Candidato reprovado' : 'Erro ao reprovar', ok);
  }

  Future<void> _aprovarProposta(CandidaturaGestorModel c) async {
    final parecer = await _dialogParecer(
      context,
      titulo: 'Parecer da proposta',
      instrucao:
          'Vai confirmar a proposta de ${c.candidatoNome}. Se quiser, registre seu '
          'parecer sobre a negociação (condições aceitas, observações relevantes).',
      obrigatorio: false,
      hint: 'Descreva o parecer (opcional)...',
    );
    if (parecer == null) return;
    final ok = await _api.aprovarProposta(
      candidaturaId: c.id,
      gestorId: _api.colaboradorAtual?.id ?? 0,
      observacao: parecer.isEmpty ? null : parecer,
    );
    if (ok) {
      await _api.encerrarVagaSePreenchida(c.vagaId);
      _carregarCandidatos();
    }
    _snack(ok ? 'Proposta confirmada! 🎉' : 'Erro ao confirmar', ok);
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
      AppColors.laranja, AppColors.magenta,
      const Color(0xFF6C63FF), const Color(0xFF00BFA5),
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
        child: Text(iniciais,
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
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

  Color _corStatus(String status) {
    switch (status) {
      case 'INSCRITO':       return AppColors.cinzaTexto;
      case 'TRIAGEM':        return const Color(0xFF64748B);
      case 'AVALIACAO_COMP': return const Color(0xFF8B5CF6);
      case 'ENTREV_RH':      return const Color(0xFF0EA5E9);
      case 'ENTREV_GESTOR': return AppColors.amarelo;
      case 'PROPOSTA':      return AppColors.laranja;
      case 'AGUARDANDO_DADOS': return AppColors.cinzaTexto;
      case 'AGUARDANDO_SESMT': return const Color(0xFF0EA5E9);
      case 'ASO_AGENDADO':
      case 'ASO_REALIZADO': return const Color(0xFF6366F1);
      case 'ASO_APROVADO':  return const Color(0xFF10B981);
      case 'ADMISSAO_INICIADA':
      case 'DADOS_ENVIADOS': return AppColors.laranja;
      case 'DOCUMENTOS_EM_ANALISE': return AppColors.amarelo;
      case 'DOCUMENTOS_APROVADOS':  return const Color(0xFF10B981);
      case 'CONTRATO_ENVIADO': return AppColors.laranja;
      case 'CONTRATO_ASSINADO': return const Color(0xFF10B981);
      case 'INTEGRACAO': return const Color(0xFF059669);
      default: return AppColors.cinzaTexto;
    }
  }

  String _labelStatus(String status) {
    switch (status) {
      case 'INSCRITO':            return 'Inscrito';
      case 'TRIAGEM':             return 'Triagem';
      case 'AVALIACAO_COMP':      return 'Aval. Comportamental';
      case 'ENTREV_RH':           return 'Entrevista RH';
      case 'ENTREV_GESTOR':       return 'Entrevista';
      case 'PROPOSTA':            return 'Proposta';
      case 'AGUARDANDO_DADOS':    return 'Aguardando';
      case 'AGUARDANDO_SESMT':    return 'Aguard. SESMT';
      case 'ASO_AGENDADO':        return 'ASO Agendado';
      case 'ASO_REALIZADO':       return 'ASO Realizado';
      case 'ASO_APROVADO':        return 'ASO Aprovado';
      case 'ADMISSAO_INICIADA':   return 'Admissão Aberta';
      case 'DADOS_ENVIADOS':      return 'Dados Enviados';
      case 'DOCUMENTOS_EM_ANALISE': return 'Docs em Análise';
      case 'DOCUMENTOS_APROVADOS':  return 'Docs Aprovados';
      case 'CONTRATO_ENVIADO':    return 'Contrato Enviado';
      case 'CONTRATO_ASSINADO':   return 'Contrato Assinado';
      case 'INTEGRACAO':          return 'Integração';
      default: return status;
    }
  }

  void _snack(String msg, bool sucesso) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins()),
      backgroundColor: sucesso ? const Color(0xFF10B981) : AppColors.magenta,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  /// Diálogo de parecer/observação usado antes de aprovar ou reprovar uma
  /// etapa da candidatura. Quando [obrigatorio] é true (reprovação), o texto
  /// é exigido; quando false (aprovação), fica livre para o gestor registrar
  /// uma observação se quiser.
  Future<String?> _dialogParecer(
    BuildContext context, {
    required String titulo,
    required String instrucao,
    bool obrigatorio = true,
    String hint = 'Descreva o parecer...',
    Color corDestaque = AppColors.laranja,
  }) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: corDestaque.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.rate_review_outlined,
                            color: corDestaque, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(titulo,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700, fontSize: 17)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    instrucao,
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.cinzaTexto, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: ctrl,
                    minLines: 4,
                    maxLines: 8,
                    autofocus: true,
                    onChanged: (_) => setSt(() {}),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: GoogleFonts.poppins(fontSize: 13),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      filled: true,
                      fillColor: AppColors.cinzaClaro,
                      contentPadding: const EdgeInsets.all(14),
                    ),
                    style: GoogleFonts.poppins(fontSize: 13.5),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancelar',
                            style: GoogleFonts.poppins(
                                color: AppColors.cinzaTexto)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: obrigatorio && ctrl.text.trim().isEmpty
                            ? null
                            : () => Navigator.pop(ctx, ctrl.text.trim()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: corDestaque,
                          disabledBackgroundColor: AppColors.cinzaClaro,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: Text('Confirmar',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Ficha do Candidato (somente leitura) ────────────────────────────────
//
// Mostra os dados do candidato e os pareceres já registrados (pelo RH no
// gentepole_admin e pelo próprio gestor) — o mesmo dado que o painel web já
// exibe na ficha do colaborador, mas que faltava aqui no app do gestor.
class _FichaCandidatoDialog extends StatefulWidget {
  final CandidaturaGestorModel candidato;
  const _FichaCandidatoDialog({required this.candidato});

  @override
  State<_FichaCandidatoDialog> createState() => _FichaCandidatoDialogState();
}

class _FichaCandidatoDialogState extends State<_FichaCandidatoDialog> {
  final _api = ApiService();
  List<Map<String, dynamic>> _observacoes = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarObservacoes();
  }

  Future<void> _carregarObservacoes() async {
    try {
      final r = await _api.listarObservacoesCandidatura(widget.candidato.id);
      if (mounted) setState(() => _observacoes = r);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidato;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(c.candidatoNome,
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.cinzaTexto),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(spacing: 12, runSpacing: 4, children: [
                if (c.candidatoEmail.isNotEmpty)
                  _chipFicha(Icons.email_outlined, c.candidatoEmail),
                if (c.candidatoTelefone != null &&
                    c.candidatoTelefone!.isNotEmpty)
                  _chipFicha(Icons.phone_outlined, c.candidatoTelefone!),
                if (c.candidatoCidade != null)
                  _chipFicha(
                      Icons.location_on_outlined,
                      c.candidatoEstado != null
                          ? '${c.candidatoCidade}, ${c.candidatoEstado}'
                          : c.candidatoCidade!),
                if (c.salarioEsperado != null)
                  _chipFicha(Icons.attach_money_rounded,
                      'R\$ ${c.salarioEsperado!.toStringAsFixed(0)}'),
              ]),
              const Divider(height: 24),
              Text('Pareceres',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark)),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: _carregando
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.magenta, strokeWidth: 2)),
                        )
                      : _observacoes.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text('Nenhum parecer registrado.',
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: AppColors.cinzaTexto)),
                            )
                          : Column(
                              children: _observacoes
                                  .map((o) => _ParecerItem(o))
                                  .toList(),
                            ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipFicha(IconData icon, String label) {
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
}

class _ParecerItem extends StatelessWidget {
  final Map<String, dynamic> observacao;
  const _ParecerItem(this.observacao);

  @override
  Widget build(BuildContext context) {
    final etapa = observacao['etapa'] as String? ?? '';
    final texto = observacao['texto'] as String? ?? '';
    final criadoEmRaw = observacao['criado_em'] as String?;
    final criadoEm =
        criadoEmRaw != null ? DateTime.tryParse(criadoEmRaw) : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FC),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (etapa.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.magenta.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(etapa,
                        style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppColors.magenta)),
                  ),
                const Spacer(),
                if (criadoEm != null)
                  Text(
                    '${criadoEm.day.toString().padLeft(2, '0')}/'
                    '${criadoEm.month.toString().padLeft(2, '0')}/'
                    '${criadoEm.year} '
                    '${criadoEm.hour.toString().padLeft(2, '0')}:'
                    '${criadoEm.minute.toString().padLeft(2, '0')}',
                    style: GoogleFonts.poppins(
                        fontSize: 10, color: AppColors.cinzaTexto),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(texto,
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.dark)),
          ],
        ),
      ),
    );
  }
}
