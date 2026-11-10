import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/conexoes_acoes_service.dart';

/// Lista de ações do Conexões do Bem com inscrição por período e vagas.
/// Se as tabelas novas não existirem, exibe [fallback] (fluxo antigo).
class ConexoesAcoesColabView extends StatefulWidget {
  final int colaboradorId;
  final String matricula;
  final Widget fallback;
  const ConexoesAcoesColabView({
    super.key,
    required this.colaboradorId,
    required this.matricula,
    required this.fallback,
  });

  @override
  State<ConexoesAcoesColabView> createState() => _ConexoesAcoesColabViewState();
}

class _ConexoesAcoesColabViewState extends State<ConexoesAcoesColabView> {
  static const _cor = Color(0xFF8B5CF6);
  static const _tamanhos = ['PP', 'P', 'M', 'G', 'GG', 'XGG'];

  bool _loading = true;
  List<Map<String, dynamic>>? _acoes;
  Map<int, Map<String, dynamic>> _minhas = {};
  int? _agindo;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final acoes = await ConexoesAcoesService.listarAcoesColab();
    final minhas = acoes == null
        ? <int, Map<String, dynamic>>{}
        : await ConexoesAcoesService.minhasInscricoes(widget.colaboradorId);
    if (!mounted) return;
    setState(() {
      _acoes = acoes;
      _minhas = minhas;
      _loading = false;
    });
  }

  void _snack(String msg, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: erro ? Colors.red.shade700 : const Color(0xFF16A34A),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _inscrever(Map<String, dynamic> acao) async {
    final acaoId = (acao['id'] as num).toInt();
    String? tam;
    final zap = TextEditingController(
        text: _minhas.values
            .map((m) => '${m['whatsapp'] ?? ''}')
            .firstWhere((w) => w.isNotEmpty, orElse: () => ''));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Inscrição: ${acao['titulo']}',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tamanho da camisa',
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _tamanhos.map((t) {
                      final sel = t == tam;
                      return ChoiceChip(
                        label: Text(t),
                        selected: sel,
                        selectedColor: _cor,
                        labelStyle: TextStyle(
                            color: sel ? Colors.white : Colors.black87),
                        onSelected: (_) => setD(() => tam = t),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text('WhatsApp',
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: zap,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9()\- +]'))
                    ],
                    decoration: const InputDecoration(
                        hintText: '(00) 00000-0000',
                        border: OutlineInputBorder()),
                  ),
                ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _cor),
                onPressed: () {
                  if (tam == null) {
                    _snack('Selecione o tamanho da camisa.', erro: true);
                    return;
                  }
                  if (zap.text.trim().length < 10) {
                    _snack('Informe um WhatsApp válido.', erro: true);
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Inscrever-me',
                    style: TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _agindo = acaoId);
    final r = await ConexoesAcoesService.inscrever(
      acaoId: acaoId,
      colaboradorId: widget.colaboradorId,
      matricula: widget.matricula,
      tamanhoCamisa: tam!,
      whatsapp: zap.text.trim(),
    );
    if (!mounted) return;
    setState(() => _agindo = null);
    _snack('${r['mensagem'] ?? ''}', erro: r['ok'] != true);
    await _carregar();
  }

  Future<void> _cancelar(Map<String, dynamic> acao) async {
    final acaoId = (acao['id'] as num).toInt();
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar inscrição?'),
        content: Text('Sua vaga em "${acao['titulo']}" será liberada.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancelar inscrição')),
        ],
      ),
    );
    if (conf != true || !mounted) return;
    setState(() => _agindo = acaoId);
    final ok =
        await ConexoesAcoesService.cancelar(acaoId, widget.colaboradorId);
    if (!mounted) return;
    setState(() => _agindo = null);
    _snack(ok ? 'Inscrição cancelada.' : 'Não foi possível cancelar.',
        erro: !ok);
    await _carregar();
  }

  Widget _card(Map<String, dynamic> a) {
    final id = (a['id'] as num).toInt();
    final st = ConexoesAcoesService.status(a);
    final vagas = (a['vagas'] as num?)?.toInt() ?? 0;
    final insc = (a['inscritos'] as num?)?.toInt() ?? 0;
    final restantes = (vagas - insc).clamp(0, vagas);
    final minha = _minhas[id];
    final desc = '${a['descricao'] ?? ''}'.trim();
    final dataAcao = ConexoesAcoesService.fmtData(a['data_acao']);

    Widget acao;
    if (minha != null) {
      acao = Row(children: [
        const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 18),
        const SizedBox(width: 6),
        Expanded(
            child: Text('Inscrito (camisa ${minha['tamanho_camisa'] ?? '-'})',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: const Color(0xFF16A34A)))),
        TextButton(
            onPressed: _agindo == id ? null : () => _cancelar(a),
            child: const Text('Cancelar inscrição')),
      ]);
    } else if (st == 'nao_iniciou') {
      acao = Text(
          'Inscrições a partir de ${ConexoesAcoesService.fmtData(a['inscricao_inicio'], hora: true)}',
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey));
    } else if (st == 'esgotada') {
      acao = Text('Vagas esgotadas',
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.red.shade700));
    } else if (st == 'aberta') {
      acao = SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _cor),
          onPressed: _agindo == id ? null : () => _inscrever(a),
          child: _agindo == id
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text('Quero participar',
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      );
    } else {
      acao = Text('Inscrições encerradas',
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${a['titulo'] ?? ''}',
            style:
                GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
        if (dataAcao.isNotEmpty)
          Text('Data da ação: $dataAcao',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(desc, style: GoogleFonts.poppins(fontSize: 13)),
        ],
        const SizedBox(height: 8),
        Text(
            st == 'nao_iniciou'
                ? '$vagas vagas'
                : '$restantes de $vagas vagas restantes',
            style: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w600, color: _cor)),
        if (a['inscricao_fim'] != null && st == 'aberta')
          Text(
              'Inscrições até ${ConexoesAcoesService.fmtData(a['inscricao_fim'], hora: true)}',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        acao,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator(color: _cor)));
    }
    if (_acoes == null) return widget.fallback;
    if (_acoes!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
            child: Text('Nenhuma ação com inscrições abertas no momento.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.grey))),
      );
    }
    return Column(children: _acoes!.map(_card).toList());
  }
}
