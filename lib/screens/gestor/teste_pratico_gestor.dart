import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../services/api_service.dart';

/// Bloco do kanban do gestor: "Avaliar teste prático" (vaga com teste prático,
/// modelo em matriz) ou, depois de avaliado, o resultado em somente leitura.
/// Tolerante a coluna/tabela ausente (migration onda3_teste_pratico).
class TestePraticoGestorAcao extends StatefulWidget {
  final int candidaturaId;
  final int vagaId;
  final String nomeCandidato;
  final VoidCallback? onAction;
  const TestePraticoGestorAcao({
    super.key,
    required this.candidaturaId,
    required this.vagaId,
    required this.nomeCandidato,
    this.onAction,
  });

  @override
  State<TestePraticoGestorAcao> createState() => _TestePraticoGestorAcaoState();
}

class _TestePraticoGestorAcaoState extends State<TestePraticoGestorAcao> {
  SupabaseClient get _c => Supabase.instance.client;
  bool _temTeste = false;
  Map<String, dynamic>? _cand; // teste_pratico_* da candidatura

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    var tem = false;
    Map<String, dynamic>? cand;
    try {
      final v = await _c
          .from('vagas')
          .select('teste_pratico')
          .eq('id', widget.vagaId)
          .maybeSingle();
      tem = v?['teste_pratico'] == true;
      if (tem) {
        try {
          cand = await _c
              .from('candidaturas')
              .select(
                  'teste_pratico_status, teste_pratico_media, teste_pratico_parecer')
              .eq('id', widget.candidaturaId)
              .maybeSingle();
        } catch (_) {
          cand = await _c
              .from('candidaturas')
              .select('teste_pratico_status')
              .eq('id', widget.candidaturaId)
              .maybeSingle();
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _temTeste = tem;
        _cand = cand;
      });
    }
  }

  String? get _status => _cand?['teste_pratico_status'] as String?;
  bool get _avaliado => _status != null && _status!.isNotEmpty;

  /// Modelo da vaga (pesquisa_teste_pratico_id) ou a única pesquisa ativa
  /// tipo teste_pratico; devolve a pesquisa com 'perguntas'.
  Future<Map<String, dynamic>?> _modelo() async {
    int? id;
    try {
      final v = await _c
          .from('vagas')
          .select('pesquisa_teste_pratico_id')
          .eq('id', widget.vagaId)
          .maybeSingle();
      id = (v?['pesquisa_teste_pratico_id'] as num?)?.toInt();
    } catch (_) {}
    if (id == null) {
      try {
        final ativos = await _c
            .from('pesquisas')
            .select('id')
            .eq('tipo', 'teste_pratico')
            .eq('ativa', true);
        if ((ativos as List).length == 1) {
          id = (ativos.first['id'] as num).toInt();
        }
      } catch (_) {}
    }
    if (id == null) return null;
    final p = await _c.from('pesquisas').select().eq('id', id).maybeSingle();
    if (p == null) return null;
    final perguntas = await _c
        .from('pesquisa_perguntas')
        .select()
        .eq('pesquisa_id', id)
        .order('ordem', ascending: true);
    return {...p, 'perguntas': perguntas};
  }

  Future<Map<int, Map<String, int>>> _notasSalvas() async {
    final out = <int, Map<String, int>>{};
    try {
      final r = await _c
          .from('pesquisa_respostas')
          .select('id')
          .eq('candidatura_id', widget.candidaturaId)
          .order('respondido_em', ascending: false)
          .limit(1);
      if ((r as List).isEmpty) return out;
      final itens = await _c
          .from('pesquisa_resposta_itens')
          .select('pergunta_id, valor_texto')
          .eq('resposta_id', r.first['id']);
      for (final i in itens as List) {
        try {
          final m = jsonDecode(i['valor_texto'] as String) as Map;
          out[(i['pergunta_id'] as num).toInt()] =
              m.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

  Future<void> _abrir({required bool somenteLeitura}) async {
    final modelo = await _modelo();
    if (!mounted) return;
    final perguntas = [
      for (final p in (modelo?['perguntas'] as List? ?? const []))
        if (p['tipo'] == 'escala_matriz') Map<String, dynamic>.from(p as Map),
    ];
    if (modelo == null || perguntas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Esta vaga não tem modelo de teste prático configurado. Fale com o RH.')));
      return;
    }
    final notas = somenteLeitura ? await _notasSalvas() : <int, Map<String, int>>{};
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FormTeste(
        nome: widget.nomeCandidato,
        perguntas: perguntas,
        somenteLeitura: somenteLeitura,
        notasIniciais: notas,
        parecerInicial: _cand?['teste_pratico_parecer'] as String?,
        resultadoInicial: _status,
        onSalvar: (n, parecer, resultado) =>
            _salvar((modelo['id'] as num).toInt(), n, parecer, resultado),
      ),
    );
    if (ok == true) {
      await _carregar();
      widget.onAction?.call();
    }
  }

  Future<void> _salvar(int pesquisaId, Map<int, Map<String, int>> notas,
      String parecer, String resultado) async {
    final colab = ApiService().colaboradorAtual;
    final agora = DateTime.now().toUtc().toIso8601String();
    try {
      final resp = await _c
          .from('pesquisa_respostas')
          .insert({
            'pesquisa_id': pesquisaId,
            'candidatura_id': widget.candidaturaId,
            'respondido_por': colab?.matricula ?? '',
            'respondido_em': agora,
          })
          .select('id')
          .single();
      for (final e in notas.entries) {
        await _c.from('pesquisa_resposta_itens').insert({
          'resposta_id': resp['id'],
          'pergunta_id': e.key,
          'valor_texto': jsonEncode(e.value),
        });
      }
    } catch (_) {}
    final todas = notas.values.expand((m) => m.values).toList();
    final media =
        todas.isEmpty ? null : todas.reduce((a, b) => a + b) / todas.length;
    try {
      await _c.from('candidaturas').update({
        'teste_pratico_status': resultado,
        'teste_pratico_media': media,
        'teste_pratico_parecer': parecer.isEmpty ? null : parecer,
        'teste_pratico_avaliado_em': agora,
        'teste_pratico_avaliador': colab?.nome ?? '',
      }).eq('id', widget.candidaturaId);
    } catch (_) {
      await _c
          .from('candidaturas')
          .update({'teste_pratico_status': resultado}).eq('id', widget.candidaturaId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_temTeste) return const SizedBox.shrink();
    final aprovado = _status == 'APROVADO';
    final cor = aprovado ? AppColors.sucesso : AppColors.erro;
    final media = (_cand?['teste_pratico_media'] as num?)?.toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: _avaliado
          ? Row(children: [
              Icon(aprovado ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 16, color: cor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Teste prático: ${aprovado ? 'Aprovado' : 'Reprovado'}'
                    '${media != null ? ' · média ${media.toStringAsFixed(1)}' : ''}',
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w600, color: cor)),
              ),
              TextButton(
                  onPressed: () => _abrir(somenteLeitura: true),
                  child: Text('Ver avaliação',
                      style: GoogleFonts.poppins(fontSize: 12))),
            ])
          : SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _abrir(somenteLeitura: false),
                icon: const Icon(Icons.assignment_turned_in_outlined, size: 16),
                label: Text('Avaliar teste prático',
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.laranja,
                    side: const BorderSide(color: AppColors.laranja),
                    padding: const EdgeInsets.symmetric(vertical: 10)),
              ),
            ),
    );
  }
}

class _FormTeste extends StatefulWidget {
  final String nome;
  final List<Map<String, dynamic>> perguntas;
  final bool somenteLeitura;
  final Map<int, Map<String, int>> notasIniciais;
  final String? parecerInicial;
  final String? resultadoInicial;
  final Future<void> Function(
      Map<int, Map<String, int>> notas, String parecer, String resultado) onSalvar;

  const _FormTeste({
    required this.nome,
    required this.perguntas,
    required this.somenteLeitura,
    required this.notasIniciais,
    required this.parecerInicial,
    required this.resultadoInicial,
    required this.onSalvar,
  });

  @override
  State<_FormTeste> createState() => _FormTesteState();
}

class _FormTesteState extends State<_FormTeste> {
  late final Map<int, Map<String, int>> _notas;
  final _parecer = TextEditingController();
  String? _resultado;
  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _notas = {
      for (final e in widget.notasIniciais.entries) e.key: Map.of(e.value)
    };
    _parecer.text = widget.parecerInicial ?? '';
    _resultado = widget.resultadoInicial;
  }

  @override
  void dispose() {
    _parecer.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    var total = 0;
    for (final p in widget.perguntas) {
      total += (p['escala_linhas'] as List?)?.length ?? 0;
    }
    final preenchidos = _notas.values.fold<int>(0, (a, m) => a + m.length);
    if (preenchidos < total) {
      setState(() => _erro = 'Avalie todos os critérios ($preenchidos/$total).');
      return;
    }
    if (_resultado == null) {
      setState(() => _erro = 'Escolha o resultado final.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await widget.onSalvar(_notas, _parecer.text.trim(), _resultado!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = 'Erro ao salvar: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ro = widget.somenteLeitura;
    final todas = _notas.values.expand((m) => m.values).toList();
    final media =
        todas.isEmpty ? null : todas.reduce((a, b) => a + b) / todas.length;
    return AlertDialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(ro ? 'Teste prático avaliado' : 'Avaliar teste prático',
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.nome,
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppColors.cinzaTexto)),
              const SizedBox(height: 12),
              for (final p in widget.perguntas) _matriz(p, ro),
              if (media != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('Média: ${media.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              TextField(
                controller: _parecer,
                readOnly: ro,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Parecer', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Text('Resultado final',
                  style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final r in const [
                  ('APROVADO', 'Aprovado', AppColors.sucesso),
                  ('REPROVADO', 'Reprovado', AppColors.erro),
                ])
                  ChoiceChip(
                    label: Text(r.$2),
                    selected: _resultado == r.$1,
                    selectedColor: r.$3.withOpacity(0.2),
                    onSelected:
                        ro ? null : (_) => setState(() => _resultado = r.$1),
                  ),
              ]),
              if (_erro != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_erro!,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.erro)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.of(context).pop(false),
          child: Text(ro ? 'Fechar' : 'Cancelar'),
        ),
        if (!ro)
          ElevatedButton(
            onPressed: _salvando ? null : _salvar,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.laranja),
            child: _salvando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salvar',
                    style: TextStyle(color: Colors.white)),
          ),
      ],
    );
  }

  Widget _matriz(Map<String, dynamic> p, bool ro) {
    final id = (p['id'] as num).toInt();
    final min = (p['escala_min'] as num?)?.toInt() ?? 1;
    final max = (p['escala_max'] as num?)?.toInt() ?? 5;
    final linhas =
        (p['escala_linhas'] as List?)?.map((e) => '$e').toList() ?? <String>[];
    final colunas = (p['escala_colunas'] as List?)?.map((e) => '$e').toList() ??
        <String>[];
    final niveis = List.generate((max - min + 1).clamp(1, 10), (i) => min + i);
    final valores = _notas.putIfAbsent(id, () => <String, int>{});
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((p['texto'] as String?)?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(p['texto'] as String,
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          for (final linha in linhas)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.cinzaClaro,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(linha,
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(children: [
                    for (var i = 0; i < niveis.length; i++)
                      Expanded(
                        child: InkWell(
                          onTap: ro
                              ? null
                              : () => setState(() => valores[linha] = niveis[i]),
                          child: Column(children: [
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: valores[linha] == niveis[i]
                                  ? AppColors.laranja
                                  : Colors.white,
                              child: Text('${niveis[i]}',
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: valores[linha] == niveis[i]
                                          ? Colors.white
                                          : AppColors.dark)),
                            ),
                            if (i < colunas.length && colunas[i].isNotEmpty)
                              Text(colunas[i],
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                      fontSize: 9, color: AppColors.cinzaTexto)),
                          ]),
                        ),
                      ),
                  ]),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
