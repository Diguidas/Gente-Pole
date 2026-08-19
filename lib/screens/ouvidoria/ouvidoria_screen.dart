import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const _tiposOuvidoria = {
  'reclamacao': 'Reclamação',
  'sugestao': 'Sugestão',
  'denuncia': 'Denúncia',
};

class OuvidoriaScreen extends StatefulWidget {
  const OuvidoriaScreen({super.key});

  @override
  State<OuvidoriaScreen> createState() => _OuvidoriaScreenState();
}

class _OuvidoriaScreenState extends State<OuvidoriaScreen> {
  final _api = ApiService();
  final _formKey = GlobalKey<FormState>();

  final _assuntoCtrl = TextEditingController();
  final _ocorridoCtrl = TextEditingController();

  String? _tipo;
  bool _anonimo = false;
  PlatformFile? _anexo;

  bool _salvando = false;

  static const Color _cor = Color(0xFF64748B);

  @override
  void dispose() {
    _assuntoCtrl.dispose();
    _ocorridoCtrl.dispose();
    super.dispose();
  }

  Future<void> _escolherAnexo() async {
    final resultado = await FilePicker.platform.pickFiles(withData: true);
    if (!mounted) return;
    if (resultado != null && resultado.files.isNotEmpty) {
      setState(() => _anexo = resultado.files.first);
    }
  }

  Future<void> _enviar() async {
    final formValido = _formKey.currentState!.validate();
    if (!formValido) return;
    if (_ocorridoCtrl.text.trim().isEmpty && _anexo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Descreva o ocorrido ou anexe um arquivo.',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }
    if (_tipo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selecione o tipo de ouvidoria.',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    setState(() => _salvando = true);
    final ok = await _api.enviarOuvidoriaColab(
      assunto: _assuntoCtrl.text.trim(),
      tipo: _tipo!,
      texto: _ocorridoCtrl.text.trim(),
      anonimo: _anonimo,
      anexoBytes: _anexo?.bytes,
      anexoNomeArquivo: _anexo?.name,
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
      _assuntoCtrl.clear();
      _ocorridoCtrl.clear();
      setState(() {
        _tipo = null;
        _anonimo = false;
        _anexo = null;
      });
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
                      'assets/ouvidoria.png',
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
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 18),
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
                Text('Fale com a Gente', style: AppTextStyles.tituloGrande),
                Text('Fale com a gente',
                    style: AppTextStyles.corpoBranco
                        .copyWith(color: AppColors.cinzaTexto)),
              ],
            ),
          ),
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

                            // Assunto
                            _label('Assunto'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _assuntoCtrl,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: _inputDec(
                                hint: 'Resuma em poucas palavras...',
                                icone: Icons.short_text_rounded,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Informe o assunto';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),

                            // Tipo de ouvidoria
                            _label('Tipo de ouvidoria'),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _tipo,
                              onChanged: (v) => setState(() => _tipo = v),
                              decoration: _inputDec(
                                hint: 'Selecione...',
                                icone: Icons.category_outlined,
                              ),
                              items: _tiposOuvidoria.entries
                                  .map((e) => DropdownMenuItem(
                                        value: e.key,
                                        child: Text(e.value,
                                            style: GoogleFonts.poppins(
                                                fontSize: 14)),
                                      ))
                                  .toList(),
                              validator: (v) =>
                                  v == null ? 'Selecione o tipo' : null,
                            ),
                            const SizedBox(height: 20),

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
                            ),
                            const SizedBox(height: 20),

                            // Anexo (opcional)
                            _label('Anexo (opcional)'),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _escolherAnexo,
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: Colors.grey.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.attach_file_rounded,
                                      size: 20,
                                      color: _anexo == null
                                          ? Colors.grey.shade400
                                          : _cor,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _anexo?.name ?? 'Anexar arquivo',
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: _anexo == null
                                              ? Colors.grey.shade400
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    if (_anexo != null)
                                      InkWell(
                                        onTap: () =>
                                            setState(() => _anexo = null),
                                        child: Icon(Icons.close_rounded,
                                            size: 18,
                                            color: Colors.grey.shade400),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Anônimo
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border:
                                    Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Enviar como anônimo',
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          'Seu nome não será exibido para quem visualizar essa mensagem.',
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _anonimo,
                                    onChanged: (v) =>
                                        setState(() => _anonimo = v),
                                    activeColor: _cor,
                                  ),
                                ],
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