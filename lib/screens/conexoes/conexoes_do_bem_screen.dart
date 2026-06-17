import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

class ConexoesDoiemScreen extends StatefulWidget {
  const ConexoesDoiemScreen({super.key});

  @override
  State<ConexoesDoiemScreen> createState() => _ConexoesDoiemScreenState();
}

class _ConexoesDoiemScreenState extends State<ConexoesDoiemScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiService();

  // ── Voluntário ──────────────────────────────────────────────────────────
  final _formVolKey = GlobalKey<FormState>();
  final _whatsappCtrl = TextEditingController();
  String? _tamanhoSelecionado;
  bool _salvandoVol = false;
  bool _verificandoVol = true;
  Map<String, dynamic>? _inscricaoExistente;

  static const _tamanhos = ['PP', 'P', 'M', 'G', 'GG', 'XGG'];

  // ── Indicar instituição ─────────────────────────────────────────────────
  final _formInstKey = GlobalKey<FormState>();
  final _nomeInstCtrl = TextEditingController();
  final _telefoneInstCtrl = TextEditingController();
  bool _salvandoInst = false;

  static const Color _cor = Color(0xFFEC4899);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _verificarInscricao();
  }

  Future<void> _verificarInscricao() async {
    final inscricao = await _api.buscarVoluntarioCadastrado();
    if (mounted) {
      setState(() {
        _inscricaoExistente = inscricao;
        _verificandoVol = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _whatsappCtrl.dispose();
    _nomeInstCtrl.dispose();
    _telefoneInstCtrl.dispose();
    super.dispose();
  }

  // ── Ações ─────────────────────────────────────────────────────────────

  Future<void> _salvarVoluntario() async {
    if (!_formVolKey.currentState!.validate()) return;
    if (_tamanhoSelecionado == null) {
      _snack('Selecione o tamanho da camisa.', erro: true);
      return;
    }
    setState(() => _salvandoVol = true);
    final ok = await _api.salvarVoluntarioConexoes(
      tamanho: _tamanhoSelecionado!,
      whatsapp: _whatsappCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _salvandoVol = false);
    if (ok) {
      _snack('Inscrição enviada! Em breve entraremos em contato. 💚');
      _whatsappCtrl.clear();
      setState(() => _tamanhoSelecionado = null);
    } else {
      _snack('Erro ao salvar. Tente novamente.', erro: true);
    }
  }

  Future<void> _salvarInstituicao() async {
    if (!_formInstKey.currentState!.validate()) return;
    setState(() => _salvandoInst = true);
    final ok = await _api.salvarInstituicaoConexoes(
      nome: _nomeInstCtrl.text.trim(),
      telefoneResponsavel: _telefoneInstCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _salvandoInst = false);
    if (ok) {
      _snack('Instituição indicada com sucesso! 🙏');
      _nomeInstCtrl.clear();
      _telefoneInstCtrl.clear();
    } else {
      _snack('Erro ao salvar. Tente novamente.', erro: true);
    }
  }

  void _snack(String msg, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins()),
        backgroundColor: erro ? Colors.red.shade700 : _cor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 200,
            decoration: const BoxDecoration(
              color: _cor,
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 20),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Conexões do Bem',
                            style: AppTextStyles.tituloGrande.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Voluntariado e solidariedade',
                            style: AppTextStyles.corpoBranco.copyWith(
                              color: AppColors.brancoOp80,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // TabBar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    labelColor: _cor,
                    unselectedLabelColor: Colors.white,
                    labelStyle: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    unselectedLabelStyle:
                        GoogleFonts.poppins(fontSize: 13),
                    tabs: const [
                      Tab(text: 'Ser Voluntário'),
                      Tab(text: 'Indicar Instituição'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Corpo
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildAbaVoluntario(),
                        _buildAbaInstituicao(),
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

  // ── Aba Voluntário ────────────────────────────────────────────────────

  Widget _buildAbaVoluntario() {
    if (_verificandoVol) {
      return const Center(child: CircularProgressIndicator(color: _cor));
    }

    if (_inscricaoExistente != null) {
      final tamanho = _inscricaoExistente!['tamanho_camisa'] as String? ?? '';
      final whatsapp = _inscricaoExistente!['whatsapp'] as String? ?? '';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _cor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: _cor, size: 40),
              ),
              const SizedBox(height: 20),
              Text(
                'Você já está inscrito!',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sua inscrição como voluntário foi registrada com sucesso. '
                'Em breve entraremos em contato.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _cor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _cor.withOpacity(0.2)),
                ),
                child: Column(children: [
                  _InfoLinha(
                      icone: Icons.checkroom_outlined,
                      label: 'Tamanho da camisa',
                      valor: tamanho),
                  const SizedBox(height: 10),
                  _InfoLinha(
                      icone: Icons.phone_outlined,
                      label: 'WhatsApp',
                      valor: whatsapp),
                ]),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formVolKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.favorite_rounded, color: _cor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Quero ser voluntário nas ações sociais do Conexões do Bem!',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Tamanho da camisa
            Text(
              'Tamanho da camisa',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tamanhos.map((t) {
                final sel = t == _tamanhoSelecionado;
                return GestureDetector(
                  onTap: () => setState(() => _tamanhoSelecionado = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 56,
                    height: 48,
                    decoration: BoxDecoration(
                      color: sel ? _cor : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel ? _cor : Colors.grey.shade300,
                      ),
                      boxShadow: sel
                          ? [
                              BoxShadow(
                                color: _cor.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : [],
                    ),
                    child: Center(
                      child: Text(
                        t,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: sel ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // WhatsApp
            Text(
              'Seu WhatsApp',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _whatsappCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              decoration: _inputDecoration(
                hint: '(85) 99999-9999',
                icone: Icons.phone_outlined,
              ),
              validator: (v) {
                if (v == null || v.trim().length < 10) {
                  return 'Informe um WhatsApp válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),

            // Botão
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _salvandoVol ? null : _salvarVoluntario,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _cor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                  shadowColor: _cor.withOpacity(0.4),
                ),
                child: _salvandoVol
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        'Quero ser voluntário!',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Aba Indicar Instituição ────────────────────────────────────────────

  Widget _buildAbaInstituicao() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formInstKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.business_outlined, color: _cor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Indique uma instituição social para parcerias com o Conexões do Bem.',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Nome da instituição
            Text(
              'Nome da instituição',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nomeInstCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: _inputDecoration(
                hint: 'Ex: Instituto Esperança',
                icone: Icons.business_outlined,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Informe o nome da instituição';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Telefone do responsável
            Text(
              'Telefone do responsável',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _telefoneInstCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              decoration: _inputDecoration(
                hint: '(85) 99999-9999',
                icone: Icons.phone_outlined,
              ),
              validator: (v) {
                if (v == null || v.trim().length < 10) {
                  return 'Informe um telefone válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _salvandoInst ? null : _salvarInstituicao,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _cor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                  shadowColor: _cor.withOpacity(0.4),
                ),
                child: _salvandoInst
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        'Indicar instituição',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icone,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(
        color: Colors.grey.shade400,
        fontSize: 14,
      ),
      prefixIcon: Icon(icone, color: Colors.grey.shade400, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _cor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
    );
  }
}

class _InfoLinha extends StatelessWidget {
  final IconData icone;
  final String label;
  final String valor;
  const _InfoLinha(
      {required this.icone, required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icone, size: 18, color: const Color(0xFFEC4899)),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
        Text(valor,
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87)),
      ]),
    ]);
  }
}