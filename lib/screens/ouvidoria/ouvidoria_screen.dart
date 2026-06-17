import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

class OuvidoriaScreen extends StatefulWidget {
  const OuvidoriaScreen({super.key});

  @override
  State<OuvidoriaScreen> createState() => _OuvidoriaScreenState();
}

class _OuvidoriaScreenState extends State<OuvidoriaScreen> {
  final _api = ApiService();
  final _formKey = GlobalKey<FormState>();

  final _ocorridoCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();
  final _sugestaoCtrl = TextEditingController();

  bool _salvando = false;

  static const Color _cor = Color(0xFF64748B);

  @override
  void dispose() {
    _ocorridoCtrl.dispose();
    _telefoneCtrl.dispose();
    _sugestaoCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);
    final ok = await _api.salvarOuvidoria(
      ocorrido: _ocorridoCtrl.text.trim(),
      telefone: _telefoneCtrl.text.trim(),
      sugestao: _sugestaoCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _salvando = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Mensagem enviada com sucesso. Obrigado pelo seu retorno!',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: _cor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      _ocorridoCtrl.clear();
      _telefoneCtrl.clear();
      _sugestaoCtrl.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao enviar. Tente novamente.',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
                            'Ouvidoria',
                            style: AppTextStyles.tituloGrande.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Fale com a gente',
                            style: AppTextStyles.corpoBranco.copyWith(
                              color: AppColors.brancoOp80,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Corpo
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Info
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _cor.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    Border.all(color: _cor.withOpacity(0.2)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.lock_outline_rounded,
                                      color: _cor, size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Suas informações serão tratadas com sigilo pelo RH.',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // O que ocorreu
                            _label('O que ocorreu?'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _ocorridoCtrl,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: _inputDec(
                                hint:
                                    'Descreva o ocorrido com o máximo de detalhes possível...',
                                icone: Icons.description_outlined,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().length < 10) {
                                  return 'Descreva o ocorrido (mínimo 10 caracteres)';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),

                            // Telefone
                            _label('Telefone para contato'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _telefoneCtrl,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(11),
                              ],
                              decoration: _inputDec(
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
                            const SizedBox(height: 20),

                            // Sugestão (opcional)
                            _label('Sugestão de melhoria (opcional)'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _sugestaoCtrl,
                              maxLines: 3,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: _inputDec(
                                hint:
                                    'Se tiver alguma sugestão sobre como podemos melhorar...',
                                icone: Icons.lightbulb_outline_rounded,
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Botão
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _salvando ? null : _enviar,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _cor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 4,
                                  shadowColor: _cor.withOpacity(0.4),
                                ),
                                child: _salvando
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        'Enviar mensagem',
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

  Widget _label(String texto) {
    return Text(
      texto,
      style: GoogleFonts.poppins(
        fontWeight: FontWeight.w700,
        fontSize: 14,
        color: Colors.black87,
      ),
    );
  }

  InputDecoration _inputDec({
    required String hint,
    required IconData icone,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(
        color: Colors.grey.shade400,
        fontSize: 13,
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