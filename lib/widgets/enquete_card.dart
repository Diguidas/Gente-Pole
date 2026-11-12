import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gentepole/core/app_theme.dart';

/// Card de enquete do feed. Auto-contido: busca opções, voto do colaborador e
/// resultado direto no Supabase. Tolerante à ausência das tabelas/RPCs
/// (nesse caso simplesmente não renderiza nada).
class EnqueteCard extends StatefulWidget {
  final Map<String, dynamic> enquete;
  final int? meuId;

  /// true = dentro de um comunicado: sem moldura/margem própria (o card do
  /// comunicado já tem), só o conteúdo da enquete.
  final bool embutido;

  const EnqueteCard({
    super.key,
    required this.enquete,
    required this.meuId,
    this.embutido = false,
  });

  /// Enquetes de comunicados (qualquer estado) pelos ids — o comunicado
  /// continua mostrando o resultado depois que a enquete encerra.
  static Future<Map<int, Map<String, dynamic>>> carregarPorIds(
      Iterable<int> ids) async {
    if (ids.isEmpty) return {};
    try {
      final res = await Supabase.instance.client
          .from('enquetes')
          .select()
          .inFilter('id', ids.toList());
      return {
        for (final e in res as List)
          (e['id'] as num).toInt(): Map<String, dynamic>.from(e as Map)
      };
    } catch (_) {
      return {};
    }
  }

  /// Enquetes ativas e não encerradas, da mais nova pra mais antiga.
  /// Retorna lista vazia se a tabela ainda não existir. Não inclui as que
  /// pertencem a um comunicado (essas só aparecem dentro dele).
  static Future<List<Map<String, dynamic>>> carregarAtivas() async {
    try {
      final res = await Supabase.instance.client
          .from('enquetes')
          .select()
          .eq('ativa', true)
          .eq('em_comunicado', false)
          .order('criado_em', ascending: false)
          .limit(20);
      final agora = DateTime.now();
      return (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) {
        final fim = DateTime.tryParse(e['encerra_em']?.toString() ?? '');
        return fim == null || fim.isAfter(agora);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  State<EnqueteCard> createState() => _EnqueteCardState();
}

class _EnqueteCardState extends State<EnqueteCard> {
  SupabaseClient get _sb => Supabase.instance.client;

  List<Map<String, dynamic>> _opcoes = [];
  Map<int, int> _votos = {};
  int _totalVotantes = 0;
  Set<int> _selecionadas = {};
  bool _jaVotou = false;
  bool _carregando = true;
  bool _enviando = false;
  bool _falhou = false;

  int get _id => (widget.enquete['id'] as num).toInt();
  bool get _multipla => widget.enquete['multipla'] == true;

  bool get _encerrada {
    if (widget.enquete['ativa'] == false) return true;
    final fim =
        DateTime.tryParse(widget.enquete['encerra_em']?.toString() ?? '');
    return fim != null && !fim.isAfter(DateTime.now());
  }

  /// "Encerra em dd/mm/aaaa às hh:mm" (ou "Encerrou em ..."); nulo quando a
  /// enquete não tem data de encerramento.
  String? get _textoFim {
    final fim =
        DateTime.tryParse(widget.enquete['encerra_em']?.toString() ?? '')
            ?.toLocal();
    if (fim == null) return null;
    String d2(int n) => n.toString().padLeft(2, '0');
    final data =
        '${d2(fim.day)}/${d2(fim.month)}/${fim.year} às ${d2(fim.hour)}:${d2(fim.minute)}';
    return fim.isAfter(DateTime.now()) ? 'Encerra em $data' : 'Encerrou em $data';
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final ops = await _sb
          .from('enquete_opcoes')
          .select()
          .eq('enquete_id', _id)
          .order('ordem')
          .order('id');
      _opcoes = (ops as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (widget.meuId != null) {
        final meus = await _sb
            .from('enquete_votos')
            .select('id')
            .eq('enquete_id', _id)
            .eq('colaborador_id', widget.meuId!)
            .limit(1);
        _jaVotou = (meus as List).isNotEmpty;
      }
      if (_jaVotou || _encerrada) await _carregarResultado();
    } catch (_) {
      _falhou = true;
    }
    if (mounted) setState(() => _carregando = false);
  }

  Future<void> _carregarResultado() async {
    try {
      final r =
          await _sb.rpc('resultado_enquete', params: {'p_enquete_id': _id});
      final m = Map<String, dynamic>.from(r as Map);
      _totalVotantes = (m['total_votantes'] as num?)?.toInt() ?? 0;
      _votos = {
        for (final o in (m['opcoes'] as List? ?? []))
          ((o as Map)['id'] as num).toInt(): (o['votos'] as num?)?.toInt() ?? 0
      };
    } catch (_) {}
  }

  Future<void> _votar() async {
    if (_selecionadas.isEmpty || widget.meuId == null || _enviando) return;
    setState(() => _enviando = true);
    String? erro;
    try {
      final r = await _sb.rpc('votar_enquete', params: {
        'p_enquete_id': _id,
        'p_opcao_ids': _selecionadas.toList(),
        'p_colaborador_id': widget.meuId,
      });
      final m = Map<String, dynamic>.from(r as Map);
      if (m['ok'] != true) {
        erro = m['motivo']?.toString() ?? 'Não foi possível votar.';
      }
      if (m['ok'] == true || (erro ?? '').contains('já votou')) {
        _jaVotou = true;
        await _carregarResultado();
      }
    } catch (_) {
      erro = 'Não foi possível registrar o voto agora.';
    }
    if (!mounted) return;
    setState(() => _enviando = false);
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const SizedBox.shrink();
    if (_falhou || _opcoes.isEmpty) return const SizedBox.shrink();

    final mostrarResultado = _jaVotou || _encerrada;
    final total = _votos.values.fold<int>(0, (a, b) => a + b);

    return Container(
      margin: widget.embutido
          ? EdgeInsets.zero
          : const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cinzaClaro, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.poll_outlined, size: 18, color: AppColors.magenta),
            const SizedBox(width: 6),
            Text('Enquete',
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.magenta)),
            if (_encerrada) ...[
              const SizedBox(width: 8),
              Text('Encerrada',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppColors.cinzaTexto)),
            ],
          ]),
          if (_textoFim != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.schedule_rounded,
                  size: 13, color: AppColors.cinzaTexto),
              const SizedBox(width: 4),
              Text(_textoFim!,
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppColors.cinzaTexto)),
            ]),
          ],
          const SizedBox(height: 8),
          Text(widget.enquete['pergunta']?.toString() ?? '',
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.dark)),
          const SizedBox(height: 12),
          for (final o in _opcoes)
            mostrarResultado ? _barra(o, total) : _opcao(o),
          if (!mostrarResultado) ...[
            const SizedBox(height: 6),
            if (_multipla)
              Text('Você pode marcar mais de uma opção.',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppColors.cinzaTexto)),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _selecionadas.isEmpty || _enviando ? null : _votar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.magenta,
                  foregroundColor: Colors.white,
                ),
                child: _enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('Votar', style: GoogleFonts.poppins()),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  '$_totalVotantes ${_totalVotantes == 1 ? "voto" : "votos"}',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppColors.cinzaTexto)),
            ),
        ],
      ),
    );
  }

  Widget _opcao(Map<String, dynamic> o) {
    final id = (o['id'] as num).toInt();
    final sel = _selecionadas.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          if (_multipla) {
            sel ? _selecionadas.remove(id) : _selecionadas.add(id);
          } else {
            _selecionadas = {id};
          }
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: sel ? AppColors.magentaOp15 : AppColors.cinzaClaro,
            border: Border.all(
                color: sel ? AppColors.magenta : Colors.transparent,
                width: 1.5),
          ),
          child: Row(children: [
            Icon(
              _multipla
                  ? (sel ? Icons.check_box : Icons.check_box_outline_blank)
                  : (sel
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
              size: 20,
              color: sel ? AppColors.magenta : AppColors.cinzaTexto,
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(o['texto']?.toString() ?? '',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.dark))),
          ]),
        ),
      ),
    );
  }

  Widget _barra(Map<String, dynamic> o, int total) {
    final id = (o['id'] as num).toInt();
    final v = _votos[id] ?? 0;
    final pct = total == 0 ? 0.0 : v / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(o['texto']?.toString() ?? '',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppColors.dark))),
          Text('${(pct * 100).round()}%  ($v)',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.cinzaTexto)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: AppColors.cinzaClaro,
            color: AppColors.magenta,
          ),
        ),
      ]),
    );
  }
}
