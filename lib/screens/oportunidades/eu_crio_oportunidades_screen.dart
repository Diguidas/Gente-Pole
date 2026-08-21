import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/vaga_model.dart';
import '../../services/api_service.dart';

class EuCrioOportunidadesScreen extends StatefulWidget {
  const EuCrioOportunidadesScreen({super.key});

  @override
  State<EuCrioOportunidadesScreen> createState() =>
      _EuCrioOportunidadesScreenState();
}

class _EuCrioOportunidadesScreenState
    extends State<EuCrioOportunidadesScreen> {
  final _api = ApiService();
  List<VagaModel> _vagas = [];
  List<Map<String, dynamic>> _indicacoesPendentes = [];
  Set<int> _vagasJaCandidatadas = {};
  Map<int, String> _vagasJaIndicadas = {};
  bool _loading = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final results = await Future.wait([
        _api.listarVagasAbertas(),
        _api.buscarIndicacoesPendentes(),
        _api.buscarVagasJaCandidatadas(),
        _api.buscarIndicacoesDoColaborador(),
      ]);
      if (mounted) {
        setState(() {
          _vagas = results[0] as List<VagaModel>;
          _indicacoesPendentes =
              results[1] as List<Map<String, dynamic>>;
          _vagasJaCandidatadas = results[2] as Set<int>;
          _vagasJaIndicadas = results[3] as Map<int, String>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = 'Erro ao carregar vagas.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _responderIndicacao(int candidaturaId, bool confirmar) async {
    try {
      await _api.confirmarIndicacao(
          candidaturaId: candidaturaId, confirmar: confirmar);
      if (mounted) {
        setState(() {
          _indicacoesPendentes
              .removeWhere((i) => i['id'] == candidaturaId);
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(confirmar
              ? 'Indicação confirmada! ⭐'
              : 'Indicação recusada.'),
          backgroundColor:
              confirmar ? const Color(0xFFF59E0B) : Colors.grey.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erro ao registrar resposta. Tente novamente.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _abrirOpcoes(VagaModel vaga) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _OpcoesCandidaturaSheet(
        vaga: vaga,
        api: _api,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 200,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(28)),
                    child: Image.asset(
                      'assets/oportunidade.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  child: SafeArea(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Eu Crio Oportunidades',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Vagas abertas para indicação e candidatura',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          // ── Corpo ───────────────────────────────────────────────
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FC),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF10B981),
                      ),
                    )
                  : _erro != null
                      ? _buildErro()
                      : RefreshIndicator(
                          color: const Color(0xFF10B981),
                          onRefresh: _carregar,
                          child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              // ── Indicações pendentes ─────────────────
                              if (_indicacoesPendentes.isNotEmpty) ...[
                                _sectionHeader(
                                  '⭐ Confirmação de indicação',
                                  'Alguém colocou seu nome como indicador',
                                  const Color(0xFFF59E0B),
                                ),
                                const SizedBox(height: 12),
                                ..._indicacoesPendentes.map((ind) =>
                                    _CardIndicacaoPendente(
                                      indicacao: ind,
                                      onConfirmar: () => _responderIndicacao(
                                          ind['id'] as int, true),
                                      onRecusar: () => _responderIndicacao(
                                          ind['id'] as int, false),
                                    )),
                                const SizedBox(height: 24),
                                const Divider(height: 1),
                                const SizedBox(height: 20),
                              ],

                              // ── Vagas ────────────────────────────────
                              if (_vagas.isEmpty)
                                _buildVazio()
                              else ...[
                                _sectionHeader(
                                  'Vagas abertas',
                                  'Candidate-se ou indique alguém',
                                  const Color(0xFF10B981),
                                ),
                                const SizedBox(height: 12),
                                ..._vagas
                                    .asMap()
                                    .entries
                                    .expand((e) => [
                                          _CardVaga(
                                            vaga: e.value,
                                            jaCandidatado: _vagasJaCandidatadas
                                                .contains(e.value.id),
                                            nomeIndicado:
                                                _vagasJaIndicadas[e.value.id],
                                            onTap: () =>
                                                _abrirOpcoes(e.value),
                                          ),
                                          if (e.key < _vagas.length - 1)
                                            const SizedBox(height: 12),
                                        ]),
                              ],
                            ],
                          ),
                        ),
            ),
          ),
              ],
            ),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_erro!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _carregar,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Tentar novamente',
                  style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔍', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              'Nenhuma vaga aberta\nno momento.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  color: Colors.grey.shade600, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String titulo, String subtitulo, Color cor) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 36,
          decoration: BoxDecoration(
            color: cor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.black87)),
            Text(subtitulo,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
      ],
    );
  }
}

// ─── Card de Indicação Pendente ───────────────────────────────────────────────

class _CardIndicacaoPendente extends StatelessWidget {
  final Map<String, dynamic> indicacao;
  final VoidCallback onConfirmar;
  final VoidCallback onRecusar;

  const _CardIndicacaoPendente({
    required this.indicacao,
    required this.onConfirmar,
    required this.onRecusar,
  });

  @override
  Widget build(BuildContext context) {
    final candidato = indicacao['candidatos'] as Map<String, dynamic>? ?? {};
    final vaga = indicacao['vagas'] as Map<String, dynamic>? ?? {};
    final nomeCandidato = candidato['nome'] as String? ?? 'Candidato';
    final tituloVaga = vaga['titulo'] as String? ?? 'Vaga';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_outline,
                    color: Color(0xFFF59E0B), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nomeCandidato,
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Colors.black87)),
                    Text(tituloVaga,
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: const Color(0xFFF59E0B),
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Este candidato disse que foi indicado por você.',
            style: GoogleFonts.poppins(
                fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onRecusar,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text('Não fui eu',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: onConfirmar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.star_rounded,
                      color: Colors.white, size: 18),
                  label: Text('Sim, indiquei!',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Card da Vaga ─────────────────────────────────────────────────────────────

class _CardVaga extends StatelessWidget {
  final VagaModel vaga;
  final VoidCallback onTap;
  final bool jaCandidatado;
  final String? nomeIndicado;

  const _CardVaga({
    required this.vaga,
    required this.onTap,
    this.jaCandidatado = false,
    this.nomeIndicado,
  });

  String get _salario {
    if (!vaga.salarioAExibir) return 'Salário a combinar';
    final min = vaga.faixaSalarialMin;
    final max = vaga.faixaSalarialMax;
    if (min == null && max == null) return 'Salário a combinar';
    String fmt(double v) =>
        'R\$ ${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')}';
    if (min != null && max != null) return '${fmt(min)} – ${fmt(max)}';
    if (min != null) return 'A partir de ${fmt(min)}';
    return 'Até ${fmt(max!)}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Ícone
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.work_outline_rounded,
                color: Color(0xFF10B981),
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            // Texto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          vaga.titulo,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (jaCandidatado) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle,
                                  size: 11, color: Color(0xFF10B981)),
                              const SizedBox(width: 3),
                              Text('Você já se candidatou',
                                  style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF10B981))),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (nomeIndicado != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.person_add_alt_1_outlined,
                            size: 12, color: Color(0xFF10B981)),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text('Você indicou $nomeIndicado',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF10B981)),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                  if (vaga.departamento != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      vaga.departamento!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (vaga.localidade != null) ...[
                        Icon(Icons.location_on_outlined,
                            size: 13, color: Colors.grey.shade400),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            vaga.localidade!,
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey.shade500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Icon(Icons.attach_money,
                          size: 13, color: Colors.grey.shade400),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          _salario,
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey.shade500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF10B981), size: 22),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom Sheet de Opções ───────────────────────────────────────────────────

class _OpcoesCandidaturaSheet extends StatelessWidget {
  final VagaModel vaga;
  final ApiService api;

  const _OpcoesCandidaturaSheet({
    required this.vaga,
    required this.api,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            vaga.titulo,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          if (vaga.departamento != null)
            Text(
              vaga.departamento!,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
          const SizedBox(height: 6),
          if (vaga.descricao != null && vaga.descricao!.isNotEmpty) ...[
            Text(
              vaga.descricao!,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.black87,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
          ],

          const Divider(),
          const SizedBox(height: 16),

          Text(
            'O que você quer fazer?',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 14),

          // Candidatar-me
          _BotaoOpcao(
            icone: Icons.person_add_outlined,
            titulo: 'Candidatar-me',
            subtitulo: 'Quero me candidatar para esta vaga',
            cor: const Color(0xFF10B981),
            onTap: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => _CandidatarMeSheet(vaga: vaga, api: api),
              );
            },
          ),

          const SizedBox(height: 12),

          // Indicar
          _BotaoOpcao(
            icone: Icons.people_alt_outlined,
            titulo: 'Indicar alguém',
            subtitulo: 'Conheço alguém perfeito para esta vaga',
            cor: const Color(0xFFF59E0B),
            onTap: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => _IndicarSheet(vaga: vaga, api: api),
              );
            },
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _BotaoOpcao extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String subtitulo;
  final Color cor;
  final VoidCallback onTap;

  const _BotaoOpcao({
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cor.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icone, color: cor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.black87)),
                  Text(subtitulo,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: cor.withOpacity(0.6), size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet: Candidatar-me ─────────────────────────────────────────────────────

class _CandidatarMeSheet extends StatefulWidget {
  final VagaModel vaga;
  final ApiService api;

  const _CandidatarMeSheet({required this.vaga, required this.api});

  @override
  State<_CandidatarMeSheet> createState() => _CandidatarMeSheetState();
}

class _CandidatarMeSheetState extends State<_CandidatarMeSheet> {
  bool _enviando = false;
  String? _erro;
  bool _sucesso = false;

  Future<void> _confirmar() async {
    final colaborador = widget.api.colaboradorAtual;
    if (colaborador == null) return;

    setState(() {
      _enviando = true;
      _erro = null;
    });

    try {
      await widget.api.inscreverColaboradorNaVaga(
        colaboradorId: colaborador.id,
        vagaId: widget.vaga.id,
        nome: colaborador.nome,
        cpf: colaborador.cpf ?? '',
        email: '',
        telefone: '',
      );
      if (mounted) setState(() => _sucesso = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = e.toString().contains('já inscrito')
              ? 'Você já está inscrito nesta vaga.'
              : 'Erro ao enviar candidatura. Tente novamente.';
        });
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colaborador = widget.api.colaboradorAtual;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: _sucesso
            ? _buildSucesso()
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Confirmar candidatura',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700, fontSize: 17)),
                  const SizedBox(height: 6),
                  Text(widget.vaga.titulo,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: const Color(0xFF10B981),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 20),

                  // Card do colaborador
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFF10B981).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor:
                              const Color(0xFF10B981).withOpacity(0.15),
                          backgroundImage: colaborador?.fotoUrl != null
                              ? NetworkImage(colaborador!.fotoUrl!)
                              : null,
                          child: colaborador?.fotoUrl == null
                              ? Text(
                                  colaborador?.nome
                                          .split(' ')
                                          .map((p) => p[0])
                                          .take(2)
                                          .join() ??
                                      '?',
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF10B981)),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(colaborador?.nome ?? '',
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              Text(colaborador?.cargo ?? '',
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Colaborador',
                              style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF10B981))),
                        ),
                      ],
                    ),
                  ),

                  if (_erro != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_erro!,
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: Colors.red.shade700)),
                    ),
                  ],

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _enviando ? null : _confirmar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _enviando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text('Confirmar candidatura',
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSucesso() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const Text('🎉', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 16),
        Text('Candidatura enviada!',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, fontSize: 18)),
        const SizedBox(height: 8),
        Text(
          'Sua candidatura para "${widget.vaga.titulo}" foi registrada. O RH entrará em contato.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
              fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('Fechar',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Sheet: Indicar alguém ────────────────────────────────────────────────────

class _IndicarSheet extends StatefulWidget {
  final VagaModel vaga;
  final ApiService api;

  const _IndicarSheet({required this.vaga, required this.api});

  @override
  State<_IndicarSheet> createState() => _IndicarSheetState();
}

class _IndicarSheetState extends State<_IndicarSheet> {
  final _cpfCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Candidato encontrado após busca
  Map<String, dynamic>? _candidatoEncontrado;

  bool _buscando  = false;
  bool _enviando  = false;
  String? _erro;
  bool _sucesso   = false;

  @override
  void dispose() {
    _cpfCtrl.dispose();
    super.dispose();
  }

  void _onCpfChanged(String v) {
    // Limpa resultado anterior quando o usuário edita o CPF
    if (_candidatoEncontrado != null) setState(() => _candidatoEncontrado = null);

    final digits = v.replaceAll(RegExp(r'\D'), '');
    final buf = StringBuffer();
    for (int i = 0; i < digits.length && i < 11; i++) {
      if (i == 3 || i == 6) buf.write('.');
      if (i == 9) buf.write('-');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    if (formatted != v) {
      _cpfCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  bool _cpfValido(String cpf) {
    final d = cpf.replaceAll(RegExp(r'\D'), '');
    if (d.length != 11 || RegExp(r'^(\d)\1+$').hasMatch(d)) return false;
    int soma = 0;
    for (int i = 0; i < 9; i++) soma += int.parse(d[i]) * (10 - i);
    int r = (soma * 10) % 11;
    if (r == 10 || r == 11) r = 0;
    if (r != int.parse(d[9])) return false;
    soma = 0;
    for (int i = 0; i < 10; i++) soma += int.parse(d[i]) * (11 - i);
    r = (soma * 10) % 11;
    if (r == 10 || r == 11) r = 0;
    return r == int.parse(d[10]);
  }

  Future<void> _buscar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _buscando = true; _erro = null; _candidatoEncontrado = null; });
    try {
      final cpf = _cpfCtrl.text.replaceAll(RegExp(r'\D'), '');
      final candidato = await widget.api.buscarCandidatoPorCpf(cpf);
      if (!mounted) return;
      if (candidato == null) {
        setState(() => _erro = 'Nenhum candidato encontrado com este CPF.\nVerifique se ele já se cadastrou no portal.');
      } else {
        setState(() => _candidatoEncontrado = candidato);
      }
    } catch (_) {
      if (mounted) setState(() => _erro = 'Erro ao buscar candidato. Tente novamente.');
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _confirmarIndicacao() async {
    final colaborador = widget.api.colaboradorAtual;
    final candidato   = _candidatoEncontrado;
    if (colaborador == null || candidato == null) return;

    setState(() { _enviando = true; _erro = null; });
    try {
      await widget.api.vincularIndicacao(
        candidatoId:   candidato['id'] as int,
        vagaId:        widget.vaga.id,
        colaboradorId: colaborador.id,
      );
      if (mounted) setState(() => _sucesso = true);
    } catch (e) {
      if (mounted) {
        setState(() => _erro = e.toString().contains('já indicado')
            ? 'Este candidato já possui uma indicação para esta vaga.'
            : 'Erro ao registrar indicação. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: _sucesso ? _buildSucesso() : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text('Indicar para a vaga',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 4),
          Text(widget.vaga.titulo,
              style: GoogleFonts.poppins(
                  fontSize: 14, color: const Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),

          // Instrução
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Informe o CPF do candidato que você quer indicar. Ele precisa ter se cadastrado no portal da Pole.',
                    style: GoogleFonts.poppins(fontSize: 11, color: Colors.orange.shade800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Campo CPF + botão buscar
          Text('CPF do candidato',
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _cpfCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: _onCpfChanged,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '000.000.000-00',
                    hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1.5)),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Informe o CPF';
                    if (!_cpfValido(v)) return 'CPF inválido';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _buscando ? null : _buscar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: _buscando
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Buscar',
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),

          // Candidato encontrado
          if (_candidatoEncontrado != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF10B981).withOpacity(0.15),
                    child: Text(
                      (_candidatoEncontrado!['nome'] as String? ?? '?')[0].toUpperCase(),
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700, color: const Color(0xFF10B981)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_candidatoEncontrado!['nome'] as String? ?? '',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        if ((_candidatoEncontrado!['area_interesse'] as String?)?.isNotEmpty == true)
                          Text(_candidatoEncontrado!['area_interesse'] as String,
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF10B981), size: 22),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _enviando ? null : _confirmarIndicacao,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _enviando
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Confirmar indicação',
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],

          // Erro
          if (_erro != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
              child: Text(_erro!,
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.red.shade700)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSucesso() {
    final nome = _candidatoEncontrado?['nome'] as String? ?? 'O candidato';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const Text('🌟', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 16),
        Text('Indicação registrada!',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18)),
        const SizedBox(height: 8),
        Text(
          '$nome foi vinculado como sua indicação para "${widget.vaga.titulo}".\nO RH verá seu nome como indicador.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('Fechar',
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}