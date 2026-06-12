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

  static const _grupoAso = {'ASO_AGENDADO', 'ASO_REALIZADO', 'ASO_APROVADO'};
  static const _grupoAdmissao = {
    'AGUARDANDO_DADOS',
    'ADMISSAO_INICIADA',
    'DADOS_ENVIADOS',
    'DOCUMENTOS_EM_ANALISE',
    'DOCUMENTOS_APROVADOS',
  };
  static const _grupoContrato = {'CONTRATO_ENVIADO', 'CONTRATO_ASSINADO'};

  List<CandidaturaGestorModel> _filtrar(List<CandidaturaGestorModel> lista) {
    switch (_filtroStatus) {
      case 'GRUPO_ASO':
        return lista.where((c) => _grupoAso.contains(c.status)).toList();
      case 'GRUPO_ADMISSAO':
        return lista.where((c) => _grupoAdmissao.contains(c.status)).toList();
      case 'GRUPO_CONTRATO':
        return lista.where((c) => _grupoContrato.contains(c.status)).toList();
      case 'TODOS':
        return lista;
      default:
        return lista.where((c) => c.status == _filtroStatus).toList();
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

                // Filtros rápidos
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chipFiltro('TODOS', 'Todos'),
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

          // Acompanhamento do fluxo de admissão
          _secaoAdmissao(c),

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── Seção admissão ───────────────────────────────────────────────────────────

  Widget _secaoAdmissao(CandidaturaGestorModel c) {
    final steps = _stepsAdmissao();
    final idxAtual = _idxVisual(c.status);
    if (idxAtual < 0) return const SizedBox.shrink();

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
              final done = idxAtual >= i;
              final atual = idxAtual == i;
              final cor = atual ? AppColors.laranja : done
                  ? const Color(0xFF10B981)
                  : const Color(0xFFE5E7EB);
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: cor,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              atual
                                  ? Icons.radio_button_checked_rounded
                                  : done
                                      ? Icons.check_rounded
                                      : Icons.circle_outlined,
                              size: 13,
                              color: done || atual
                                  ? Colors.white
                                  : AppColors.cinzaTexto,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            steps[i]['label'] as String,
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              color: atual
                                  ? AppColors.laranja
                                  : done
                                      ? const Color(0xFF10B981)
                                      : AppColors.cinzaTexto,
                              fontWeight: atual || done
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
                        width: 8,
                        color: idxAtual > i
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

  Color _corStatus(String status) {
    switch (status) {
      case 'AGUARDANDO_DADOS':
        return AppColors.cinzaTexto;
      case 'ASO_AGENDADO':
      case 'ASO_REALIZADO':
        return const Color(0xFF6366F1);
      case 'ASO_APROVADO':
        return const Color(0xFF10B981);
      case 'ADMISSAO_INICIADA':
      case 'DADOS_ENVIADOS':
        return AppColors.laranja;
      case 'DOCUMENTOS_EM_ANALISE':
        return AppColors.amarelo;
      case 'DOCUMENTOS_APROVADOS':
        return const Color(0xFF10B981);
      case 'CONTRATO_ENVIADO':
        return AppColors.laranja;
      case 'CONTRATO_ASSINADO':
        return const Color(0xFF10B981);
      case 'INTEGRACAO':
        return const Color(0xFF059669);
      default:
        return AppColors.cinzaTexto;
    }
  }

  String _labelStatus(String status) {
    switch (status) {
      case 'AGUARDANDO_DADOS':
        return 'Aguardando';
      case 'ASO_AGENDADO':
        return 'ASO Agendado';
      case 'ASO_REALIZADO':
        return 'ASO Realizado';
      case 'ASO_APROVADO':
        return 'ASO Aprovado';
      case 'ADMISSAO_INICIADA':
        return 'Admissão Aberta';
      case 'DADOS_ENVIADOS':
        return 'Dados Enviados';
      case 'DOCUMENTOS_EM_ANALISE':
        return 'Docs em Análise';
      case 'DOCUMENTOS_APROVADOS':
        return 'Docs Aprovados';
      case 'CONTRATO_ENVIADO':
        return 'Contrato Enviado';
      case 'CONTRATO_ASSINADO':
        return 'Contrato Assinado';
      case 'INTEGRACAO':
        return 'Integração';
      default:
        return status;
    }
  }

  // 5 etapas visuais agrupadas para não sobrecarregar
  List<Map<String, String>> _stepsAdmissao() {
    return [
      {'key': 'ASO_AGENDADO', 'label': 'ASO'},
      {'key': 'ADMISSAO_INICIADA', 'label': 'Admissão'},
      {'key': 'DOCUMENTOS_EM_ANALISE', 'label': 'Documentos'},
      {'key': 'CONTRATO_ENVIADO', 'label': 'Contrato'},
      {'key': 'INTEGRACAO', 'label': 'Integração'},
    ];
  }

  // Retorna o índice visual do step com base no status real
  int _idxVisual(String status) {
    if ({'ASO_AGENDADO', 'ASO_REALIZADO', 'ASO_APROVADO'}.contains(status)) {
      return 0;
    }
    if ({'AGUARDANDO_DADOS', 'ADMISSAO_INICIADA', 'DADOS_ENVIADOS'}
        .contains(status)) {
      return 1;
    }
    if ({'DOCUMENTOS_EM_ANALISE', 'DOCUMENTOS_APROVADOS'}.contains(status)) {
      return 2;
    }
    if ({'CONTRATO_ENVIADO', 'CONTRATO_ASSINADO'}.contains(status)) {
      return 3;
    }
    if (status == 'INTEGRACAO') return 4;
    return -1;
  }

}