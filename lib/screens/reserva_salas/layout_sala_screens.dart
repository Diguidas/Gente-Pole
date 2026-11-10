import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Identidade do colaborador logado (ids de texto em sala_layout_*).
({String id, String nome}) _eu() {
  final c = ApiService().colaboradorAtual;
  return (id: (c?.id ?? 0).toString(), nome: c?.nome ?? '');
}

String _fmtHora(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.day)}/${p(d.month)} ${p(d.hour)}:${p(d.minute)}';
}

/// Demandas de layout de sala. [facilites] = visão do time Facilites (todas
/// as demandas); senão, só as do próprio solicitante, que também pode abrir
/// uma nova.
class LayoutSalaListaScreen extends StatefulWidget {
  final bool facilites;
  const LayoutSalaListaScreen({super.key, this.facilites = false});
  @override
  State<LayoutSalaListaScreen> createState() => _LayoutSalaListaScreenState();
}

class _LayoutSalaListaScreenState extends State<LayoutSalaListaScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _demandas = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    try {
      final u = _eu();
      var q = _db.from('sala_layout_demandas').select();
      if (!widget.facilites) q = q.eq('solicitante_id', u.id);
      final res = await q.order('atualizado_em', ascending: false);
      if (!mounted) return;
      setState(() {
        _demandas = List<Map<String, dynamic>>.from(res as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _nova() async {
    final tituloCtrl = TextEditingController();
    final salaCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Alterar layout da sala',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: salaCtrl, decoration: const InputDecoration(labelText: 'Sala')),
            const SizedBox(height: 8),
            TextField(controller: tituloCtrl, decoration: const InputDecoration(labelText: 'Resumo do que você precisa')),
            const SizedBox(height: 8),
            TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Detalhes (opcional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (tituloCtrl.text.trim().isEmpty || salaCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Abrir demanda'),
          ),
        ],
      ),
    );
    final titulo = tituloCtrl.text.trim(), sala = salaCtrl.text.trim(), desc = descCtrl.text.trim();
    tituloCtrl.dispose();
    salaCtrl.dispose();
    descCtrl.dispose();
    if (ok != true || !mounted) return;
    final u = _eu();
    final d = await _db
        .from('sala_layout_demandas')
        .insert({
          'sala_nome': sala,
          'solicitante_id': u.id,
          'solicitante_nome': u.nome,
          'titulo': titulo,
        })
        .select()
        .single();
    if (desc.isNotEmpty) {
      await _db.from('sala_layout_mensagens').insert({
        'demanda_id': d['id'],
        'autor_id': u.id,
        'autor_nome': u.nome,
        'autor_facilites': false,
        'texto': desc,
      });
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LayoutSalaChatScreen(demanda: d, facilites: false)));
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: widget.facilites
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.dark,
              elevation: 0.5,
              title: Text('Layout de sala',
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
      floatingActionButton: widget.facilites
          ? null
          : FloatingActionButton.extended(
              onPressed: _nova,
              icon: const Icon(Icons.add),
              label: const Text('Nova demanda'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (widget.facilites)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('Demandas de layout de sala',
                          style: GoogleFonts.poppins(
                              fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.dark)),
                    ),
                  if (_demandas.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                          child: Text('Nenhuma demanda de layout.',
                              style: GoogleFonts.poppins(color: Colors.black54))),
                    ),
                  for (final d in _demandas)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Icon(
                            d['status'] == 'concluida'
                                ? Icons.check_circle_outline
                                : Icons.chat_bubble_outline,
                            color: d['status'] == 'concluida' ? Colors.green : AppColors.laranja),
                        title: Text('${d['sala_nome'] ?? ''} — ${d['titulo']}',
                            style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${widget.facilites ? '${d['solicitante_nome']} · ' : ''}${d['status'] == 'concluida' ? 'Concluída' : 'Aberta'} · ${_fmtHora(d['atualizado_em'] as String?)}',
                            style: GoogleFonts.poppins(fontSize: 11.5)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => LayoutSalaChatScreen(demanda: d, facilites: widget.facilites)));
                          _carregar();
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Bate-papo de uma demanda de layout: o Facilites registra etapas com prazo
/// (ex.: "Início do desenho gráfico — 48h") e imagens; o solicitante responde.
class LayoutSalaChatScreen extends StatefulWidget {
  final Map<String, dynamic> demanda;
  final bool facilites;
  const LayoutSalaChatScreen({super.key, required this.demanda, required this.facilites});
  @override
  State<LayoutSalaChatScreen> createState() => _LayoutSalaChatScreenState();
}

class _LayoutSalaChatScreenState extends State<LayoutSalaChatScreen> {
  final _textoCtrl = TextEditingController();
  final _etapaCtrl = TextEditingController();
  final _prazoCtrl = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _msgs = [];
  PlatformFile? _imagem;
  bool _enviando = false;
  late bool _concluida;

  @override
  void initState() {
    super.initState();
    _concluida = widget.demanda['status'] == 'concluida';
    _carregar();
  }

  @override
  void dispose() {
    _textoCtrl.dispose();
    _etapaCtrl.dispose();
    _prazoCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final res = await _db
        .from('sala_layout_mensagens')
        .select()
        .eq('demanda_id', widget.demanda['id'])
        .order('criado_em');
    if (!mounted) return;
    setState(() => _msgs = List<Map<String, dynamic>>.from(res as List));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _escolherImagem() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (r != null && r.files.isNotEmpty && r.files.first.bytes != null) {
      setState(() => _imagem = r.files.first);
    }
  }

  Future<void> _enviar() async {
    final texto = _textoCtrl.text.trim();
    final etapa = _etapaCtrl.text.trim();
    final prazo = int.tryParse(_prazoCtrl.text.trim());
    if (texto.isEmpty && _imagem == null && etapa.isEmpty) return;
    setState(() => _enviando = true);
    try {
      final u = _eu();
      String? url;
      if (_imagem != null) {
        url = await ApiService()
            .uploadAnexoSolicitacao(Uint8List.fromList(_imagem!.bytes!), _imagem!.name);
      }
      await _db.from('sala_layout_mensagens').insert({
        'demanda_id': widget.demanda['id'],
        'autor_id': u.id,
        'autor_nome': u.nome,
        'autor_facilites': widget.facilites,
        if (texto.isNotEmpty) 'texto': texto,
        if (url != null) 'imagem_url': url,
        if (widget.facilites && etapa.isNotEmpty) 'etapa': etapa,
        if (widget.facilites && prazo != null) 'prazo_horas': prazo,
      });
      await _db
          .from('sala_layout_demandas')
          .update({'atualizado_em': DateTime.now().toUtc().toIso8601String()})
          .eq('id', widget.demanda['id']);
      _textoCtrl.clear();
      _etapaCtrl.clear();
      _prazoCtrl.clear();
      _imagem = null;
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _alternarConclusao() async {
    final novo = _concluida ? 'aberta' : 'concluida';
    await _db.from('sala_layout_demandas').update({
      'status': novo,
      'atualizado_em': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', widget.demanda['id']);
    setState(() => _concluida = !_concluida);
  }

  Widget _bolha(Map<String, dynamic> m) {
    final fac = m['autor_facilites'] == true;
    final cor = fac ? const Color(0xFFFFF7ED) : const Color(0xFFEFF6FF);
    final etapa = m['etapa'] as String?;
    final prazo = m['prazo_horas'] as int?;
    return Align(
      alignment: fac ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${m['autor_nome']}${fac ? ' · Facilites' : ''} · ${_fmtHora(m['criado_em'] as String?)}',
              style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.black54)),
          if (etapa != null && etapa.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: const Color(0xFFFED7AA), borderRadius: BorderRadius.circular(8)),
              child: Text('$etapa${prazo != null ? ' · prazo: ${prazo}h' : ''}',
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF9A3412))),
            ),
          ] else if (prazo != null) ...[
            const SizedBox(height: 6),
            Text('Prazo: ${prazo}h',
                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
          if ((m['texto'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            SelectableText(m['texto'] as String, style: GoogleFonts.poppins(fontSize: 13)),
          ],
          if (m['imagem_url'] != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(m['imagem_url'] as String, height: 220, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Text('Imagem indisponível')),
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.demanda;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.dark,
        elevation: 0.5,
        title: Text('${d['sala_nome'] ?? ''} — ${d['titulo']}',
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
        actions: [
          if (widget.facilites)
            TextButton(
              onPressed: _alternarConclusao,
              child: Text(_concluida ? 'Reabrir' : 'Concluir demanda'),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: [
              if (_msgs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child: Text('Nenhuma mensagem ainda.',
                          style: GoogleFonts.poppins(color: Colors.black54))),
                ),
              for (final m in _msgs) _bolha(m),
            ],
          ),
        ),
        if (_concluida)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: const Color(0xFFF0FDF4),
            child: Text('Demanda concluída.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.green, fontWeight: FontWeight.w600)),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
                color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.facilites)
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _etapaCtrl,
                      decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Etapa (ex: Início do desenho gráfico)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _prazoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, labelText: 'Prazo (h)'),
                    ),
                  ),
                ]),
              if (_imagem != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    label: Text(_imagem!.name),
                    onDeleted: () => setState(() => _imagem = null),
                  ),
                ),
              Row(children: [
                IconButton(
                    onPressed: _enviando ? null : _escolherImagem,
                    icon: const Icon(Icons.image_outlined)),
                Expanded(
                  child: TextField(
                    controller: _textoCtrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(hintText: 'Escreva uma mensagem...'),
                  ),
                ),
                IconButton(
                  onPressed: _enviando ? null : _enviar,
                  icon: _enviando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded, color: AppColors.laranja),
                ),
              ]),
            ]),
          ),
      ]),
    );
  }
}
