import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/vaga_model.dart';
import '../../services/api_service.dart';

class SolicitarVagaScreen extends StatefulWidget {
  const SolicitarVagaScreen({super.key});

  @override
  State<SolicitarVagaScreen> createState() => _SolicitarVagaScreenState();
}

class _SolicitarVagaScreenState extends State<SolicitarVagaScreen> {
  final _api = ApiService();
  final _formKey = GlobalKey<FormState>();

  final _tituloCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  final _departamentoCtrl = TextEditingController();
  final _localidadeCtrl = TextEditingController();
  final _salMinCtrl = TextEditingController();
  final _salMaxCtrl = TextEditingController();

  String _tipoContrato = 'CLT';
  String _tipoVaga = 'UNICA';
  bool _salarioAExibir = false;
  bool _testePratico = false;
  bool _enviando = false;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descricaoCtrl.dispose();
    _departamentoCtrl.dispose();
    _localidadeCtrl.dispose();
    _salMinCtrl.dispose();
    _salMaxCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enviando = true);

    final colaborador = _api.colaboradorAtual;
    final vaga = VagaModel(
      id: 0,
      titulo: _tituloCtrl.text.trim(),
      descricao: _descricaoCtrl.text.trim().isEmpty
          ? null
          : _descricaoCtrl.text.trim(),
      departamento: _departamentoCtrl.text.trim().isEmpty
          ? null
          : _departamentoCtrl.text.trim(),
      localidade: _localidadeCtrl.text.trim().isEmpty
          ? null
          : _localidadeCtrl.text.trim(),
      tipoContrato: _tipoContrato,
      faixaSalarialMin: double.tryParse(_salMinCtrl.text.replaceAll(',', '.')),
      faixaSalarialMax: double.tryParse(_salMaxCtrl.text.replaceAll(',', '.')),
      salarioAExibir: _salarioAExibir,
      testePratico: _testePratico,
      status: 'FECHADA',
      tipoVaga: _tipoVaga,
      requisitadoPorId: colaborador?.id,
      statusRequisicao: 'AGUARDANDO_APROVACAO_RH',
      createdAt: DateTime.now(),
    );

    final ok = await _api.solicitarVaga(vaga);
    setState(() => _enviando = false);

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Solicitação enviada! O RH será notificado. ✅',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar. Tente novamente.',
              style: GoogleFonts.poppins()),
          backgroundColor: AppColors.magenta,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 180,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),
          SafeArea(
            child: Column(
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
                              'Solicitar Vaga',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Preencha os dados da vaga',
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

                // Formulário
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                        children: [
                          _secao('Informações da Vaga'),
                          const SizedBox(height: 12),

                          _campo(
                            controller: _tituloCtrl,
                            label: 'Título da vaga *',
                            hint: 'Ex: Analista de Logística',
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Obrigatório'
                                    : null,
                          ),
                          const SizedBox(height: 12),

                          _campo(
                            controller: _descricaoCtrl,
                            label: 'Descrição / Requisitos',
                            hint: 'Descreva as responsabilidades e requisitos',
                            maxLines: 4,
                          ),
                          const SizedBox(height: 12),

                          _campo(
                            controller: _departamentoCtrl,
                            label: 'Departamento',
                            hint: 'Ex: Operações',
                          ),
                          const SizedBox(height: 12),

                          _campo(
                            controller: _localidadeCtrl,
                            label: 'Localidade',
                            hint: 'Ex: Fortaleza - CE',
                          ),
                          const SizedBox(height: 24),

                          _secao('Tipo de Contrato'),
                          const SizedBox(height: 12),

                          _seletorChips(
                            opcoes: ['CLT', 'PJ', 'Estágio'],
                            selecionado: _tipoContrato,
                            onSelect: (v) =>
                                setState(() => _tipoContrato = v),
                          ),
                          const SizedBox(height: 24),

                          _secao('Tipo de Vaga'),
                          const SizedBox(height: 8),
                          Text(
                            'Vaga única encerra automaticamente após admissão',
                            style: GoogleFonts.poppins(
                                fontSize: 11, color: AppColors.cinzaTexto),
                          ),
                          const SizedBox(height: 12),

                          _seletorChips(
                            opcoes: ['UNICA', 'MULTIPLA'],
                            labels: ['Vaga Única', 'Múltiplas Vagas'],
                            selecionado: _tipoVaga,
                            onSelect: (v) =>
                                setState(() => _tipoVaga = v),
                          ),
                          const SizedBox(height: 24),

                          _secao('Faixa Salarial'),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                child: _campo(
                                  controller: _salMinCtrl,
                                  label: 'Mínimo',
                                  hint: '0,00',
                                  teclado: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _campo(
                                  controller: _salMaxCtrl,
                                  label: 'Máximo',
                                  hint: '0,00',
                                  teclado: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          _toggle(
                            label: 'Exibir salário no portal público',
                            value: _salarioAExibir,
                            onChanged: (v) =>
                                setState(() => _salarioAExibir = v),
                          ),
                          const SizedBox(height: 8),

                          _toggle(
                            label: 'Requer teste prático',
                            value: _testePratico,
                            onChanged: (v) =>
                                setState(() => _testePratico = v),
                          ),
                          const SizedBox(height: 32),

                          // Botão enviar
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _enviando ? null : _enviar,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.magenta,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                elevation: 0,
                              ),
                              child: _enviando
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    )
                                  : Text(
                                      'Enviar Solicitação',
                                      style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ],
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

  // ── Helpers de UI ────────────────────────────────────────────────────────────

  Widget _secao(String titulo) {
    return Text(
      titulo,
      style: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.dark,
      ),
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType? teclado,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: teclado,
      validator: validator,
      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.dark),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle:
            GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto),
        labelStyle:
            GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
    );
  }

  Widget _seletorChips({
    required List<String> opcoes,
    List<String>? labels,
    required String selecionado,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 10,
      children: List.generate(opcoes.length, (i) {
        final v = opcoes[i];
        final label = labels != null ? labels[i] : v;
        final sel = selecionado == v;
        return GestureDetector(
          onTap: () => onSelect(v),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? AppColors.laranja : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    sel ? AppColors.laranja : const Color(0xFFE5E7EB),
              ),
            ),
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: sel ? Colors.white : AppColors.cinzaTexto,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _toggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.dark),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.laranja,
          ),
        ],
      ),
    );
  }
}