import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const _corTi = Color(0xFFE64A19);

class NovoChamadoTiScreen extends StatefulWidget {
  const NovoChamadoTiScreen({super.key});

  @override
  State<NovoChamadoTiScreen> createState() => _NovoChamadoTiScreenState();
}

class _NovoChamadoTiScreenState extends State<NovoChamadoTiScreen> {
  final _api = ApiService();
  final _formKey = GlobalKey<FormState>();

  final _tituloCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String? _tipoSolicitacao;
  String? _departamento;
  String? _nivelUrgencia;
  String? _atribuidoPara; // guarda o id (string) do ti_membro selecionado
  PlatformFile? _anexo;
  List<Map<String, dynamic>> _membros = [];
  List<String> _tiposSolicitacao = [];
  List<String> _departamentos = [];
  List<String> _niveisUrgencia = [];

  bool _loading = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _carregarOpcoes();
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descricaoCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarOpcoes() async {
    setState(() => _loading = true);
    final membros = await _api.listarTiMembros();
    final tipos = await _api.listarTiChamadoOpcoes('tipo_solicitacao');
    final departamentos = await _api.listarTiChamadoOpcoes('departamento');
    final urgencias = await _api.listarTiChamadoOpcoes('nivel_urgencia');
    if (!mounted) return;
    setState(() {
      _membros = membros;
      _tiposSolicitacao = tipos.map((o) => o['valor'] as String).toList();
      _departamentos = departamentos.map((o) => o['valor'] as String).toList();
      _niveisUrgencia = urgencias.map((o) => o['valor'] as String).toList();
      _loading = false;
    });
  }

  Future<void> _escolherAnexo() async {
    final resultado = await FilePicker.platform.pickFiles(withData: true);
    if (!mounted) return;
    if (resultado != null && resultado.files.isNotEmpty) {
      setState(() => _anexo = resultado.files.first);
    }
  }

  Future<void> _enviar() async {
    final formValido = _formKey.currentState?.validate() ?? false;
    if (!formValido) return;
    if (_tipoSolicitacao == null) {
      _snack('Selecione o tipo de solicitação.', erro: true);
      return;
    }
    if (_departamento == null) {
      _snack('Selecione seu departamento.', erro: true);
      return;
    }
    if (_nivelUrgencia == null) {
      _snack('Selecione o nível de urgência.', erro: true);
      return;
    }
    if (_atribuidoPara == null) {
      _snack('Selecione para quem será o chamado.', erro: true);
      return;
    }

    final membro = _membros.firstWhere((m) => m['id'].toString() == _atribuidoPara);

    setState(() => _enviando = true);
    try {
      await _api.abrirChamadoAzureTI(
        titulo: _tituloCtrl.text,
        descricao: _descricaoCtrl.text,
        tipoSolicitacao: _tipoSolicitacao!,
        departamento: _departamento!,
        nivelUrgencia: _nivelUrgencia!,
        atribuidoPara: membro['azure_email'] as String,
        tiMembroId: membro['id'] as int,
        solicitanteEmail: _emailCtrl.text.trim(),
        anexoBytes: _anexo?.bytes != null ? Uint8List.fromList(_anexo!.bytes!) : null,
        anexoNomeArquivo: _anexo?.name,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _snack('Não foi possível abrir o chamado: $e', erro: true);
    }
  }

  void _snack(String msg, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AppTextStyles.corpoBranco),
      backgroundColor: erro ? AppColors.erro : AppColors.sucesso,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  InputDecoration _decoracao(String hint) => InputDecoration(hintText: hint);

  Widget _label(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(texto, style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _corTi,
        title: const Text('Abrir chamado de TI'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _corTi))
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(context).padding.bottom,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Para quem será'),
                    DropdownButtonFormField<String>(
                      value: _atribuidoPara,
                      onChanged: (v) => setState(() => _atribuidoPara = v),
                      decoration: _decoracao('Selecione o responsável...'),
                      items: _membros
                          .map((m) => DropdownMenuItem(
                                value: m['id'].toString(),
                                child: Text(m['nome'] as String),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 18),
                    _label('Seu e-mail'),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _decoracao('Para a TI poder retornar o contato...'),
                      validator: (v) {
                        final email = v?.trim() ?? '';
                        if (email.isEmpty) return 'Informe seu e-mail.';
                        if (!email.contains('@') || !email.contains('.')) return 'E-mail inválido.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    _label('Título'),
                    TextFormField(
                      controller: _tituloCtrl,
                      decoration: _decoracao('Resuma o problema em poucas palavras...'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o título.' : null,
                    ),
                    const SizedBox(height: 18),
                    _label('Tipo de solicitação'),
                    DropdownButtonFormField<String>(
                      value: _tipoSolicitacao,
                      onChanged: (v) => setState(() => _tipoSolicitacao = v),
                      decoration: _decoracao('Selecione...'),
                      items: _tiposSolicitacao.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    ),
                    const SizedBox(height: 18),
                    _label('Departamento'),
                    DropdownButtonFormField<String>(
                      value: _departamento,
                      onChanged: (v) => setState(() => _departamento = v),
                      decoration: _decoracao('Selecione...'),
                      items: _departamentos.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    ),
                    const SizedBox(height: 18),
                    _label('Nível de urgência'),
                    DropdownButtonFormField<String>(
                      value: _nivelUrgencia,
                      onChanged: (v) => setState(() => _nivelUrgencia = v),
                      decoration: _decoracao('Selecione...'),
                      items: _niveisUrgencia.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    ),
                    const SizedBox(height: 18),
                    _label('Descrição'),
                    TextFormField(
                      controller: _descricaoCtrl,
                      maxLines: 5,
                      decoration: _decoracao('Descreva com o máximo de detalhes possível...'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Descreva o problema.' : null,
                    ),
                    const SizedBox(height: 18),
                    _label('Anexo (opcional)'),
                    InkWell(
                      onTap: _escolherAnexo,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.cinzaClaro,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          Icon(Icons.attach_file_rounded, size: 18, color: _anexo == null ? AppColors.cinzaTexto : _corTi),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _anexo?.name ?? 'Anexar print ou foto',
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.corpoNormal.copyWith(
                                  color: _anexo == null ? AppColors.cinzaTexto : AppColors.dark),
                            ),
                          ),
                          if (_anexo != null)
                            InkWell(
                              onTap: () => setState(() => _anexo = null),
                              child: const Icon(Icons.close_rounded, size: 16, color: AppColors.cinzaTexto),
                            ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _enviando ? null : _enviar,
                        style: ElevatedButton.styleFrom(backgroundColor: _corTi, padding: const EdgeInsets.symmetric(vertical: 16)),
                        child: _enviando
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text('Abrir chamado', style: AppTextStyles.botaoPrimario),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
