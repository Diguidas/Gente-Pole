import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';

const _tiposPlano = {
  'tecnico': 'Desenvolvimento Técnico',
  'comportamental': 'Desenvolvimento Comportamental',
};
const _modalidadesAcao = {
  'presencial': 'Presencial',
  'online': 'Online',
  'benchmarking': 'Benchmarking',
  'artigo': 'Artigo',
  'curso_online': 'Curso online',
  'ebook': 'eBook',
  'filme': 'Filme',
  'livro_fisico': 'Livro Físico',
  'livro_online': 'Livro Online',
  'podcast': 'Podcast',
  'serie': 'Série',
  'ted_talk': 'TED Talk',
  'unipole': 'UniPole',
  'video': 'Vídeo',
  'webinar': 'Webinar',
};
const _statusAcao = {
  'em_andamento': 'Em andamento',
  'concluido': 'Concluído',
  'cancelado': 'Cancelado',
};

Color _corStatus(String status) {
  switch (status) {
    case 'concluido':
      return AppColors.sucesso;
    case 'cancelado':
      return AppColors.erro;
    default:
      return AppColors.laranja;
  }
}

String _dataBr(String iso) => iso.split('T').first.split('-').reversed.join('/');

List<Map<String, dynamic>> _acoesDoPdi(Map<String, dynamic> g) => [
      for (final p in (g['pdi_planos'] as List?) ?? const [])
        ...((p as Map)['pdi_acoes'] as List? ?? const [])
            .cast<Map<String, dynamic>>(),
    ];

/// PDI encerrado = tem ações e todas estão concluídas ou canceladas.
bool _pdiEncerrado(Map<String, dynamic> g) {
  final acoes = _acoesDoPdi(g);
  return acoes.isNotEmpty &&
      acoes.every((a) => a['status'] == 'concluido' || a['status'] == 'cancelado');
}

/// PDI do gestor: criar, acompanhar e editar os PDIs de quem está abaixo dele
/// (líder direto, flag `pdi_gestor`). Compartilhado com o RH — as duas pontas
/// leem e gravam nas mesmas tabelas, então o que um cria o outro vê.
class PdiGestorScreen extends StatefulWidget {
  const PdiGestorScreen({super.key});

  @override
  State<PdiGestorScreen> createState() => _PdiGestorScreenState();
}

class _PdiGestorScreenState extends State<PdiGestorScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _erro;
  List<ColaboradorModel> _equipe = [];
  Map<int, ColaboradorModel> _equipePorId = {};
  List<Map<String, dynamic>> _pdis = [];
  bool _verHistorico = false;

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
      final equipe = await _api.buscarMinhaEquipe(
          apenasLiderDireto: true, funcionalidade: 'pdi_gestor');
      final pdis = await _api.listarPdisDaEquipe(equipe.map((c) => c.id).toList());
      if (!mounted) return;
      setState(() {
        _equipe = equipe;
        _equipePorId = {for (final c in equipe) c.id: c};
        _pdis = pdis;
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

  Future<void> _abrirPdi(Map<String, dynamic> pdi) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PdiDetalheScreen(
          grupoId: pdi['id'] as int,
          colaboradorId: pdi['colaborador_id'] as int,
          nomeColaborador:
              _equipePorId[pdi['colaborador_id'] as int]?.nome ?? 'Colaborador',
        ),
      ),
    );
    _carregar();
  }

  Future<void> _novoPdi() async {
    final colab = await showModalBottomSheet<ColaboradorModel>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _SeletorColaborador(equipe: _equipe),
    );
    if (colab == null || !mounted) return;
    final dados = await _dialogoNovoPdi(context, colab.nome);
    if (dados == null || !mounted) return;
    try {
      final grupoId = await _api.criarPdiGrupo(
        colaboradorId: colab.id,
        titulo: dados.$1,
        objetivo: dados.$2,
        criadoPor: _api.colaboradorAtual?.id.toString(),
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _PdiDetalheScreen(
            grupoId: grupoId,
            colaboradorId: colab.id,
            nomeColaborador: colab.nome,
            abrirNovoPlano: true,
          ),
        ),
      );
      _carregar();
    } catch (e) {
      _erroSnack(context, 'Erro ao criar PDI: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = _pdis.where((g) => _pdiEncerrado(g) == _verHistorico).toList();
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: Text('PDI da equipe',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.dark,
        elevation: 0.5,
      ),
      floatingActionButton: _loading || _erro != null || _equipe.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _novoPdi,
              backgroundColor: AppColors.laranja,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text('Novo PDI', style: GoogleFonts.poppins()),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.laranja))
          : _erro != null
              ? Center(child: Text(_erro!, style: AppTextStyles.corpoCinza))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  color: AppColors.laranja,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    children: [
                      Text(
                          'Você vê e edita os PDIs de quem está abaixo de você. O RH acompanha os mesmos PDIs.',
                          style: AppTextStyles.corpoMinimo),
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Em andamento')),
                          ButtonSegment(value: true, label: Text('Histórico')),
                        ],
                        selected: {_verHistorico},
                        onSelectionChanged: (v) =>
                            setState(() => _verHistorico = v.first),
                      ),
                      const SizedBox(height: 14),
                      if (_equipe.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                              'Nenhum colaborador da sua equipe direta para criar PDI.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.corpoCinza),
                        )
                      else if (lista.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                              _verHistorico
                                  ? 'Nenhum PDI encerrado ainda.'
                                  : 'Nenhum PDI em andamento. Toque em "Novo PDI" para criar.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.corpoCinza),
                        )
                      else
                        ...lista.map(_cardPdi),
                    ],
                  ),
                ),
    );
  }

  Widget _cardPdi(Map<String, dynamic> g) {
    final colab = _equipePorId[g['colaborador_id'] as int];
    final acoes = _acoesDoPdi(g);
    final feitas = acoes.where((a) => a['status'] == 'concluido').length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => _abrirPdi(g),
          title: Text(colab?.nome ?? 'Colaborador',
              style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text(g['titulo'] as String? ?? 'PDI',
              style: AppTextStyles.corpoMinimo),
          trailing: Text(acoes.isEmpty ? 'Sem ações' : '$feitas/${acoes.length} ações',
              style: AppTextStyles.corpoMinimo
                  .copyWith(fontWeight: FontWeight.w600, color: AppColors.laranja)),
        ),
      ),
    );
  }
}

void _erroSnack(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: AppColors.erro,
    behavior: SnackBarBehavior.floating,
  ));
}

/// (título, objetivo) do novo PDI; null se cancelou.
Future<(String, String?)?> _dialogoNovoPdi(BuildContext context, String nome) {
  final tituloCtrl = TextEditingController();
  final objetivoCtrl = TextEditingController();
  return showDialog<(String, String?)>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Novo PDI para $nome',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tituloCtrl,
              decoration: const InputDecoration(
                  hintText: 'Título. Ex: PDI - AVD 2026.1, Plano de Liderança'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: objetivoCtrl,
              maxLines: 3,
              decoration:
                  const InputDecoration(hintText: 'Objetivo (descrição do PDI)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            final titulo = tituloCtrl.text.trim().isEmpty ? 'PDI' : tituloCtrl.text.trim();
            final obj = objetivoCtrl.text.trim();
            Navigator.pop(ctx, (titulo, obj.isEmpty ? null : obj));
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.laranja),
          child: const Text('Avançar', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

class _SeletorColaborador extends StatefulWidget {
  final List<ColaboradorModel> equipe;
  const _SeletorColaborador({required this.equipe});

  @override
  State<_SeletorColaborador> createState() => _SeletorColaboradorState();
}

class _SeletorColaboradorState extends State<_SeletorColaborador> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final lista = widget.equipe
        .where((c) => c.nome.toLowerCase().contains(_busca.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom, top: 16),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Text('Para quem é o PDI?',
                style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w700)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                onChanged: (v) => setState(() => _busca = v),
                decoration: const InputDecoration(
                    hintText: 'Buscar colaborador...',
                    prefixIcon: Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: ListView(
                children: lista
                    .map((c) => ListTile(
                          title: Text(c.nome, style: AppTextStyles.corpoMedio),
                          subtitle: Text(c.cargo ?? '', style: AppTextStyles.corpoMinimo),
                          onTap: () => Navigator.pop(context, c),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detalhe de um PDI: planos, ações (status, prazo, link), criar e excluir.
class _PdiDetalheScreen extends StatefulWidget {
  final int grupoId;
  final int colaboradorId;
  final String nomeColaborador;
  final bool abrirNovoPlano;

  const _PdiDetalheScreen({
    required this.grupoId,
    required this.colaboradorId,
    required this.nomeColaborador,
    this.abrirNovoPlano = false,
  });

  @override
  State<_PdiDetalheScreen> createState() => _PdiDetalheScreenState();
}

class _PdiDetalheScreenState extends State<_PdiDetalheScreen> {
  final _api = ApiService();
  bool _loading = true;
  Map<String, dynamic>? _grupo;

  @override
  void initState() {
    super.initState();
    _carregar().then((_) {
      if (widget.abrirNovoPlano && mounted && _grupo != null) _novoPlano();
    });
  }

  Future<void> _carregar() async {
    try {
      final grupos = await _api.listarPdiGrupos(widget.colaboradorId);
      final grupo = grupos.where((g) => g['id'] == widget.grupoId).toList();
      if (!mounted) return;
      setState(() {
        _grupo = grupo.isEmpty ? null : grupo.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _erroSnack(context, 'Erro ao carregar: $e');
    }
  }

  Future<bool> _confirmar(String titulo, String texto) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(texto, style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.erro),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _novoPlano() async {
    final tituloCtrl = TextEditingController();
    String tipo = 'tecnico';
    final criar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text('Novo plano de desenvolvimento',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: tituloCtrl,
                decoration:
                    const InputDecoration(hintText: 'Título. Ex: Curso Gestão do tempo'),
              ),
              const SizedBox(height: 12),
              Text('Tipo',
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: _tiposPlano.entries
                    .map((e) => ChoiceChip(
                          label: Text(e.value, style: GoogleFonts.poppins(fontSize: 12)),
                          selected: tipo == e.key,
                          selectedColor: AppColors.laranja.withOpacity(0.15),
                          onSelected: (_) => setStateDialog(() => tipo = e.key),
                        ))
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.laranja),
              child: const Text('Criar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (criar == true && tituloCtrl.text.trim().isNotEmpty) {
      try {
        await _api.criarPdiPlanoEmGrupo(
          colaboradorId: widget.colaboradorId,
          pdiGrupoId: widget.grupoId,
          titulo: tituloCtrl.text.trim(),
          tipo: tipo,
          criadoPor: _api.colaboradorAtual?.id.toString(),
        );
        await _carregar();
      } catch (e) {
        _erroSnack(context, 'Erro ao criar plano: $e');
      }
    }
  }

  Future<void> _novaAcao(int planoId) async {
    final descCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    DateTime? prazo;
    String? modalidade;
    final criar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text('Nova ação',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(hintText: 'O que precisa ser feito?'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: linkCtrl,
                  decoration: const InputDecoration(
                      hintText: 'Link dedicado desta ação (opcional)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: modalidade,
                  isExpanded: true,
                  hint: const Text('Modalidade (opcional)'),
                  items: [
                    for (final e in _modalidadesAcao.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setStateDialog(() => modalidade = v),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: prazo ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    );
                    if (d != null) setStateDialog(() => prazo = d);
                  },
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(prazo == null
                      ? 'Prazo (opcional)'
                      : 'Prazo: ${_dataBr(prazo!.toIso8601String())}'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.laranja),
              child: const Text('Adicionar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (criar == true && descCtrl.text.trim().isNotEmpty) {
      try {
        await _api.adicionarAcaoPdi(
          planoId: planoId,
          descricao: descCtrl.text.trim(),
          prazo: prazo,
          link: linkCtrl.text.trim().isEmpty ? null : linkCtrl.text.trim(),
          modalidade: modalidade,
        );
        await _carregar();
      } catch (e) {
        _erroSnack(context, 'Erro ao adicionar ação: $e');
      }
    }
  }

  Future<void> _excluirPlano(int planoId) async {
    if (!await _confirmar('Excluir plano',
        'Excluir esse plano? As ações e o termo vinculados também serão apagados. Não dá para desfazer.')) {
      return;
    }
    try {
      await _api.excluirPdiPlano(planoId);
      await _carregar();
    } catch (e) {
      _erroSnack(context, 'Erro ao excluir plano: $e');
    }
  }

  Future<void> _excluirPdi() async {
    if (!await _confirmar('Excluir PDI',
        'Excluir este PDI? Todos os planos, ações e termos também serão apagados. Não dá para desfazer.')) {
      return;
    }
    try {
      await _api.excluirPdiGrupo(widget.grupoId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _erroSnack(context, 'Erro ao excluir PDI: $e');
    }
  }

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _enviarTermoCompromisso() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    try {
      await _api.criarTermoCompromissoPdi(
        pdiGrupoId: widget.grupoId,
        bytes: bytes,
        nomeArquivo: file.name,
        criadoPor: _api.colaboradorAtual?.id.toString(),
      );
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      _erroSnack(context, 'Erro ao enviar termo: $e');
    }
  }

  Future<void> _excluirTermo(int termoId) async {
    if (!await _confirmar('Excluir termo',
        'Excluir este termo de compromisso? Não dá para desfazer.')) {
      return;
    }
    try {
      await _api.excluirTermoCompromissoPdi(termoId);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      _erroSnack(context, 'Erro ao excluir termo: $e');
    }
  }

  /// Termo de compromisso do PDI: o gestor anexa (PDF) e o colaborador baixa.
  Widget _blocoTermo(Map<String, dynamic> g) {
    final termos = (g['pdi_termos_compromisso'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Termo de compromisso',
              style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (termos.isEmpty)
            Text('Nenhum termo anexado ainda.', style: AppTextStyles.corpoCinza),
          ...termos.map((t) => Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _abrirUrl(t['arquivo_url'] as String),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        const Icon(Icons.description_outlined,
                            size: 16, color: AppColors.laranja),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(t['nome_arquivo'] as String? ?? 'termo.pdf',
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.corpoNormal.copyWith(
                                  color: AppColors.laranja,
                                  decoration: TextDecoration.underline)),
                        ),
                      ]),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Excluir termo',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => _excluirTermo(int.parse(t['id'].toString())),
                ),
              ])),
          TextButton.icon(
            onPressed: _enviarTermoCompromisso,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Enviar termo de compromisso (PDF)'),
            style: TextButton.styleFrom(foregroundColor: AppColors.laranja),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = _grupo;
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: Text(widget.nomeColaborador,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.dark,
        elevation: 0.5,
        actions: [
          if (g != null)
            IconButton(
              tooltip: 'Excluir PDI',
              icon: const Icon(Icons.delete_outline, color: AppColors.erro),
              onPressed: _excluirPdi,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.laranja))
          : g == null
              ? Center(
                  child: Text('Este PDI não existe mais.',
                      style: AppTextStyles.corpoCinza))
              : _corpo(g),
    );
  }

  Widget _corpo(Map<String, dynamic> g) {
    final objetivo = (g['objetivo'] as String?)?.trim() ?? '';
    final planos =
        (g['pdi_planos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text(g['titulo'] as String? ?? 'PDI', style: AppTextStyles.labelSecao),
        if (objetivo.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(objetivo, style: AppTextStyles.corpoMedio),
        ],
        const SizedBox(height: 16),
        if (planos.isEmpty)
          Text('Nenhum plano ainda. Toque em "Novo plano".',
              style: AppTextStyles.corpoCinza),
        ...planos.map(_blocoPlano),
        _blocoTermo(g),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _novoPlano,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Novo plano'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.laranja),
        ),
      ],
    );
  }

  Widget _blocoPlano(Map<String, dynamic> plano) {
    final acoes =
        (plano['pdi_acoes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  _tiposPlano[plano['tipo']] ?? (plano['tipo'] as String? ?? ''),
                  style: AppTextStyles.corpoMinimo.copyWith(
                      fontWeight: FontWeight.w700, color: AppColors.laranja)),
            ),
            IconButton(
              tooltip: 'Excluir plano',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.erro),
              onPressed: () => _excluirPlano(plano['id'] as int),
            ),
          ]),
          Text(plano['titulo'] as String? ?? '',
              style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (acoes.isEmpty)
            Text('Nenhuma ação cadastrada.', style: AppTextStyles.corpoCinza),
          ...acoes.map(_linhaAcao),
          TextButton.icon(
            onPressed: () => _novaAcao(plano['id'] as int),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Adicionar ação'),
            style: TextButton.styleFrom(foregroundColor: AppColors.laranja),
          ),
        ],
      ),
    );
  }

  Widget _linhaAcao(Map<String, dynamic> a) {
    final status = a['status'] as String? ?? 'em_andamento';
    final link = (a['link'] as String?)?.trim() ?? '';
    final modalidade = _modalidadesAcao[a['modalidade']];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a['descricao'] as String? ?? '', style: AppTextStyles.corpoMedio),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (a['prazo'] != null)
                Text('Prazo: ${_dataBr(a['prazo'] as String)}',
                    style: AppTextStyles.corpoMinimo),
              if (modalidade != null) Text(modalidade, style: AppTextStyles.corpoMinimo),
              if (link.isNotEmpty)
                InkWell(
                  onTap: () => _abrirUrl(link),
                  child: Text('Abrir link',
                      style: AppTextStyles.corpoMinimo.copyWith(
                          color: AppColors.laranja,
                          decoration: TextDecoration.underline)),
                ),
              DropdownButton<String>(
                value: _statusAcao.containsKey(status) ? status : 'em_andamento',
                isDense: true,
                underline: const SizedBox.shrink(),
                style: AppTextStyles.corpoMinimo
                    .copyWith(fontWeight: FontWeight.w600, color: _corStatus(status)),
                items: [
                  for (final e in _statusAcao.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  try {
                    await _api.atualizarStatusAcaoPdiGestor(a['id'] as int, v);
                    await _carregar();
                  } catch (e) {
                    _erroSnack(context, 'Erro ao atualizar: $e');
                  }
                },
              ),
              IconButton(
                tooltip: 'Excluir ação',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () async {
                  if (!await _confirmar('Excluir ação', 'Excluir esta ação?')) return;
                  try {
                    await _api.excluirAcaoPdi(a['id'] as int);
                    await _carregar();
                  } catch (e) {
                    _erroSnack(context, 'Erro ao excluir: $e');
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
