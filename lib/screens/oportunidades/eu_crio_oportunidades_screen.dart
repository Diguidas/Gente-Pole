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
      final vagas = await _api.listarVagasAbertas();
      if (mounted) setState(() => _vagas = vagas);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Erro ao carregar vagas.');
    } finally {
      if (mounted) setState(() => _loading = false);
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
      body: Stack(
        children: [
          Container(
            height: 220,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Header ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 24, 20),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Eu Crio Oportunidades',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Vagas abertas para indicação e candidatura',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 12,
                              ),
                            ),
                          ],
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
                            : _vagas.isEmpty
                                ? _buildVazio()
                                : RefreshIndicator(
                                    color: const Color(0xFF10B981),
                                    onRefresh: _carregar,
                                    child: ListView.separated(
                                      padding: const EdgeInsets.all(20),
                                      itemCount: _vagas.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 12),
                                      itemBuilder: (_, i) =>
                                          _CardVaga(
                                        vaga: _vagas[i],
                                        onTap: () =>
                                            _abrirOpcoes(_vagas[i]),
                                      ),
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
    );
  }
}

// ─── Card da Vaga ─────────────────────────────────────────────────────────────

class _CardVaga extends StatelessWidget {
  final VagaModel vaga;
  final VoidCallback onTap;

  const _CardVaga({required this.vaga, required this.onTap});

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
                  Text(
                    vaga.titulo,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
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
                        Text(
                          vaga.localidade!,
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey.shade500),
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
  final _nomeCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _enviando = false;
  String? _erro;
  bool _sucesso = false;

  @override
  void dispose() {
    _nomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    final colaborador = widget.api.colaboradorAtual;
    if (colaborador == null) return;

    setState(() {
      _enviando = true;
      _erro = null;
    });

    try {
      await widget.api.indicarCandidato(
        colaboradorId: colaborador.id,
        vagaId: widget.vaga.id,
        nomeIndicado: _nomeCtrl.text.trim(),
      );
      if (mounted) setState(() => _sucesso = true);
    } catch (e) {
      if (mounted) {
        setState(() => _erro = 'Erro ao enviar indicação. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            : Form(
                key: _formKey,
                child: Column(
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
                    Text('Indicar para a vaga',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700, fontSize: 17)),
                    const SizedBox(height: 4),
                    Text(widget.vaga.titulo,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: const Color(0xFFF59E0B),
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 20),

                    Text('Nome do indicado',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nomeCtrl,
                      textCapitalization: TextCapitalization.words,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Nome completo',
                        hintStyle: GoogleFonts.poppins(
                            color: Colors.grey.shade400, fontSize: 14),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFFF59E0B), width: 1.5),
                        ),
                      ),
                      validator: (v) => (v == null || v.trim().length < 3)
                          ? 'Informe o nome completo'
                          : null,
                    ),

                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                const Color(0xFFF59E0B).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 16, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'O indicado deverá apresentar seu currículo na entrevista. O RH entrará em contato com ele.',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.orange.shade800),
                            ),
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
                                fontSize: 13,
                                color: Colors.red.shade700)),
                      ),
                    ],

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _enviando ? null : _enviar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _enviando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Text('Enviar indicação',
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSucesso() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const Text('🌟', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 16),
        Text('Indicação enviada!',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, fontSize: 18)),
        const SizedBox(height: 8),
        Text(
          'Sua indicação de "${_nomeCtrl.text.trim()}" para "${widget.vaga.titulo}" foi registrada. Obrigado!',
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
              backgroundColor: const Color(0xFFF59E0B),
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