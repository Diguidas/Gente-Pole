import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/documentos_cadastrais_service.dart';

const _corCadastro = Color(0xFF0369A1);

Future<PlatformFile?> _escolherArquivo() async {
  final r = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    withData: true,
  );
  if (r == null || r.files.isEmpty || r.files.first.bytes == null) return null;
  return r.files.first;
}

void _snackErro(BuildContext context, Object e) =>
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.erro));

/// Atualização cadastral do colaborador: documentos pessoais e dependentes
/// (com documentos). Aparece quando o DP solicita um pedido.
class AtualizacaoCadastralScreen extends StatefulWidget {
  const AtualizacaoCadastralScreen({super.key});

  @override
  State<AtualizacaoCadastralScreen> createState() =>
      _AtualizacaoCadastralScreenState();
}

class _AtualizacaoCadastralScreenState
    extends State<AtualizacaoCadastralScreen> {
  final _svc = DocumentosCadastraisService.instance;
  String? _colabId;
  bool _loading = true;
  bool _temPedido = false;
  bool _concluindo = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final colab = ApiService().colaboradorAtual;
      if (colab == null) {
        setState(() {
          _erro = 'Perfil não encontrado.';
          _loading = false;
        });
        return;
      }
      final id = colab.id.toString();
      final pedidos = await _svc.listarPedidosPendentes(id);
      if (!mounted) return;
      setState(() {
        _colabId = id;
        _temPedido = pedidos.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar: $e';
        _loading = false;
      });
    }
  }

  Future<void> _concluir() async {
    setState(() => _concluindo = true);
    try {
      await _svc.concluirPedidos(_colabId!);
      if (!mounted) return;
      setState(() {
        _temPedido = false;
        _concluindo = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Atualização cadastral concluída. Obrigado!')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _concluindo = false);
      _snackErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        backgroundColor: _corCadastro,
        foregroundColor: Colors.white,
        title: Text('Atualização cadastral',
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text(_erro!))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                        'Mantenha seus documentos e os de seus dependentes em dia (PDF, JPG ou PNG).',
                        style: GoogleFonts.poppins(
                            fontSize: 12.5, color: AppColors.cinzaTexto)),
                    if (_temPedido) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                            'O DP solicitou a atualização do seu cadastro. Envie/atualize os documentos e conclua abaixo.',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: const Color(0xFF9A5B13))),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _DocumentosPessoaisEditor(colaboradorId: _colabId!),
                    const SizedBox(height: 24),
                    _DependentesEditor(colaboradorId: _colabId!),
                    const SizedBox(height: 24),
                    if (_temPedido)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _corCadastro,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: _concluindo ? null : _concluir,
                        child: _concluindo
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text('Concluir atualização',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
    );
  }
}

class _LinhaDocumento extends StatelessWidget {
  final String rotulo;
  final Map<String, dynamic>? doc;
  final bool enviando;
  final VoidCallback onUpload;
  const _LinhaDocumento({
    required this.rotulo,
    required this.doc,
    required this.enviando,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final enviado = doc != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(enviado ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16, color: enviado ? AppColors.sucesso : AppColors.cinzaTexto),
        const SizedBox(width: 8),
        Expanded(
          child: Text(rotulo,
              style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.dark)),
        ),
        if (enviado)
          IconButton(
            tooltip: 'Abrir',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            onPressed: () => launchUrl(Uri.parse(doc!['arquivo_url'] as String),
                mode: LaunchMode.externalApplication),
          ),
        enviando
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton(
                onPressed: onUpload,
                child: Text(enviado ? 'Substituir' : 'Enviar',
                    style: GoogleFonts.poppins(fontSize: 12)),
              ),
      ]),
    );
  }
}

class _DocumentosPessoaisEditor extends StatefulWidget {
  final String colaboradorId;
  const _DocumentosPessoaisEditor({required this.colaboradorId});

  @override
  State<_DocumentosPessoaisEditor> createState() =>
      _DocumentosPessoaisEditorState();
}

class _DocumentosPessoaisEditorState extends State<_DocumentosPessoaisEditor> {
  final _svc = DocumentosCadastraisService.instance;
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  final Set<String> _enviando = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final d = await _svc.listarDocumentosPessoais(widget.colaboradorId);
      if (mounted) setState(() => _docs = d);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _upload(String tipo) async {
    final f = await _escolherArquivo();
    if (f == null) return;
    setState(() => _enviando.add(tipo));
    try {
      await _svc.uploadDocumentoPessoal(
          colaboradorId: widget.colaboradorId,
          tipo: tipo,
          bytes: f.bytes!,
          nomeArquivo: f.name);
      await _carregar();
    } catch (e) {
      if (mounted) _snackErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando.remove(tipo));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Documentos pessoais',
            style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.dark)),
        const SizedBox(height: 8),
        for (final t in DocumentosCadastraisService.tiposDocumentoPessoal)
          _LinhaDocumento(
            rotulo: t.$2,
            doc: _docs.where((d) => d['tipo'] == t.$1).firstOrNull,
            enviando: _enviando.contains(t.$1),
            onUpload: () => _upload(t.$1),
          ),
      ]),
    );
  }
}

class _DependentesEditor extends StatefulWidget {
  final String colaboradorId;
  const _DependentesEditor({required this.colaboradorId});

  @override
  State<_DependentesEditor> createState() => _DependentesEditorState();
}

class _DependentesEditorState extends State<_DependentesEditor> {
  final _svc = DocumentosCadastraisService.instance;
  List<Map<String, dynamic>> _deps = [];
  bool _loading = true;
  final Set<String> _enviando = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final d = await _svc.listarDependentes(widget.colaboradorId);
      if (mounted) setState(() => _deps = d);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _adicionar() async {
    final nomeCtrl = TextEditingController();
    String parentesco = 'filho';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Adicionar dependente',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nomeCtrl,
              decoration: const InputDecoration(labelText: 'Nome completo'),
              onChanged: (_) => setD(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: parentesco,
              decoration: const InputDecoration(labelText: 'Parentesco'),
              items: [
                for (final p in DocumentosCadastraisService.parentescos)
                  DropdownMenuItem(value: p.$1, child: Text(p.$2)),
              ],
              onChanged: (v) => setD(() => parentesco = v ?? 'filho'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: nomeCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );
    final nome = nomeCtrl.text;
    nomeCtrl.dispose();
    if (ok != true) return;
    try {
      await _svc.adicionarDependente(
          colaboradorId: widget.colaboradorId,
          nome: nome,
          parentesco: parentesco);
      await _carregar();
    } catch (e) {
      if (mounted) _snackErro(context, e);
    }
  }

  Future<void> _remover(Map<String, dynamic> dep) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover dependente?'),
        content: Text('${dep['nome']} e os documentos enviados serão removidos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.removerDependente(dep['id']);
      await _carregar();
    } catch (e) {
      if (mounted) _snackErro(context, e);
    }
  }

  Future<void> _upload(Map<String, dynamic> dep, String tipo) async {
    final f = await _escolherArquivo();
    if (f == null) return;
    final chave = '${dep['id']}:$tipo';
    setState(() => _enviando.add(chave));
    try {
      await _svc.uploadDocumentoDependente(
          dependenteId: dep['id'],
          tipo: tipo,
          bytes: f.bytes!,
          nomeArquivo: f.name);
      await _carregar();
    } catch (e) {
      if (mounted) _snackErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando.remove(chave));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text('Dependentes',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark)),
        ),
        TextButton.icon(
          onPressed: _adicionar,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 16),
          label: Text('Adicionar dependente',
              style: GoogleFonts.poppins(fontSize: 12)),
        ),
      ]),
      if (_deps.isEmpty)
        Text('Nenhum dependente informado.',
            style: GoogleFonts.poppins(
                fontSize: 12, color: AppColors.cinzaTexto)),
      for (final dep in _deps)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                    '${dep['nome']} · ${DocumentosCadastraisService.rotuloParentesco(dep['parentesco'] as String?)}',
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Remover',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _remover(dep),
              ),
            ]),
            const SizedBox(height: 6),
            for (final t in DocumentosCadastraisService.tiposDocumentoDependente)
              _LinhaDocumento(
                rotulo: t.$2,
                doc: (dep['documentos'] as List)
                    .cast<Map<String, dynamic>>()
                    .where((d) => d['tipo'] == t.$1)
                    .firstOrNull,
                enviando: _enviando.contains('${dep['id']}:${t.$1}'),
                onUpload: () => _upload(dep, t.$1),
              ),
          ]),
        ),
    ]);
  }
}
