import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../core/app_theme.dart';
import 'seletor_nota_widget.dart';

const indigo9Box = Color(0xFF6366F1);

/// Nota final de uma dimensão (desempenho/potencial): combina a
/// autoavaliação do colaborador, a nota do gestor e — em ciclos 360 — a
/// média da equipe, quando existirem. Se a avaliação tem um template com
/// pesos configurados (ex: gestor 70% / colaborador 30%), usa essa
/// proporção; sem template, cai na média simples de sempre.
///
/// Compartilhado entre a Matriz 9Box do RH (ciclo_detalhe_screen.dart) e a
/// do gestor (dentro de avaliar_equipe_gestor_screen.dart).
int? resultado9Box(Map<String, dynamic> a, String dimensao,
    [Map<int, Map<String, int>>? pesosPorTemplate]) {
  final v = nota9BoxDecimal(a, dimensao, pesosPorTemplate);
  return v == null ? null : v.round().clamp(1, 5);
}

/// Mesma nota de [resultado9Box], mas sem arredondar (ex.: 3,45) — é ela que
/// a régua de faixas ([Faixas9Box]) usa para classificar em Baixo/Médio/Alto.
double? nota9BoxDecimal(Map<String, dynamic> a, String dimensao,
    [Map<int, Map<String, int>>? pesosPorTemplate]) {
  final gestor = a['gestor_$dimensao'] as int?;
  if (gestor == null) return null; // gestor ainda não avaliou
  final auto = a['autoavaliacao_$dimensao'] as int?;
  final equipe = a['equipe_$dimensao'] as int?;

  // Pesos do ciclo têm prioridade; ciclos antigos (sem pesos) e avaliações
  // sem ciclo (período de experiência) usam os do template — igual ao web.
  final cicloId = a['ciclo_id'] as int?;
  final templateId = a['template_id'] as int?;
  Map<String, int>? pesos;
  if (pesosPorTemplate != null) {
    if (cicloId != null) pesos = pesosPorTemplate[chavePesoCiclo(cicloId)];
    if (pesos == null && templateId != null) pesos = pesosPorTemplate[templateId];
  }
  if (pesos == null) {
    final notas = [gestor, if (auto != null) auto, if (equipe != null) equipe];
    return notas.reduce((x, y) => x + y) / notas.length;
  }

  var somaPesos = 0;
  var somaValores = 0;
  void aplicar(int? valor, int peso) {
    if (valor == null || peso <= 0) return;
    somaValores += valor * peso;
    somaPesos += peso;
  }

  aplicar(gestor, pesos['gestor'] ?? 0);
  aplicar(auto, pesos['colaborador'] ?? 0);
  aplicar(equipe, pesos['equipe'] ?? 0);
  if (somaPesos == 0) return gestor.toDouble();
  return somaValores / somaPesos;
}

/// Régua que transforma a nota decimal em faixa: Baixo (≤ [baixoMax]),
/// Alto (≥ [altoMin]) e Médio no meio. Configurável na tela de legendas da
/// Matriz 9Box (admin); guardada na mesma tabela das legendas, com as chaves
/// [chaveBaixoMax] e [chaveAltoMin].
class Faixas9Box {
  static const chaveBaixoMax = 'cfg_faixa_baixo_max';
  static const chaveAltoMin = 'cfg_faixa_alto_min';

  final double baixoMax;
  final double altoMin;
  const Faixas9Box({this.baixoMax = 1.80, this.altoMin = 3.30});

  factory Faixas9Box.dasLegendas(Map<String, String> legendas) {
    double? ler(String chave) =>
        double.tryParse((legendas[chave] ?? '').replaceAll(',', '.'));
    return Faixas9Box(
        baixoMax: ler(chaveBaixoMax) ?? 1.80, altoMin: ler(chaveAltoMin) ?? 3.30);
  }

  /// 0 = baixo, 1 = médio, 2 = alto.
  int faixa(double nota) {
    if (nota <= baixoMax) return 0;
    if (nota >= altoMin) return 2;
    return 1;
  }

  String rotulo(double nota) => const ['Baixo', 'Médio', 'Alto'][faixa(nota)];

  String get descricao =>
      'Baixo ≤ ${fmtNota(baixoMax)} · Médio entre ${fmtNota(baixoMax)} e ${fmtNota(altoMin)} · Alto ≥ ${fmtNota(altoMin)}';
}

String fmtNota(double n) => n.toStringAsFixed(2).replaceAll('.', ',');

/// Nome, cor e ícone de cada célula da matriz 9box clássica — cruza
/// Potencial (linha) x Desempenho (coluna), cada um reduzido de 1-5 pra 3
/// faixas (baixo/médio/alto). Segue o modelo de competências padrão de
/// mercado (ex: softwareavaliacao.com.br).
class _InfoQuadrante {
  final String titulo;
  final Color cor;
  final IconData icone;
  const _InfoQuadrante(this.titulo, this.cor, this.icone);
}

// Índice [potencial 0=baixo..2=alto][desempenho 0=abaixo..2=acima].
const List<List<_InfoQuadrante>> _quadrantes = [
  [
    _InfoQuadrante('Insuficiente', Color(0xFFE53935), Icons.sentiment_very_dissatisfied_rounded),
    _InfoQuadrante('Eficaz', Color(0xFFFFA726), Icons.sentiment_satisfied_rounded),
    _InfoQuadrante('Comprometido', Color(0xFF29B6F6), Icons.sentiment_satisfied_rounded),
  ],
  [
    _InfoQuadrante('Questionável', Color(0xFFFFA726), Icons.sentiment_dissatisfied_rounded),
    _InfoQuadrante('Mantenedor', Color(0xFF29B6F6), Icons.sentiment_satisfied_rounded),
    _InfoQuadrante('Forte Desempenho', Color(0xFF8BC34A), Icons.sentiment_satisfied_rounded),
  ],
  [
    _InfoQuadrante('Enigma', Color(0xFF29B6F6), Icons.sentiment_neutral_rounded),
    _InfoQuadrante('Forte Desempenho', Color(0xFF8BC34A), Icons.sentiment_satisfied_rounded),
    _InfoQuadrante('Alto Potencial', Color(0xFF43A047), Icons.auto_awesome_rounded),
  ],
];

const _labelsFaixaPotencial = ['BAIXO', 'MÉDIO', 'ALTO'];
const _labelsFaixaDesempenho = ['ABAIXO DO\nESPERADO', 'ESPERADO', 'ACIMA DO\nESPERADO'];

class Grid9Box extends StatelessWidget {
  final List<Map<String, dynamic>> avaliacoes;
  final Map<int, Map<String, int>> pesos;
  final Map<String, String> legendas;
  final void Function(Map<String, dynamic> avaliacao) onTapColaborador;

  const Grid9Box(
      {super.key,
      required this.avaliacoes,
      required this.pesos,
      required this.legendas,
      required this.onTapColaborador});

  static const double _alturaCelula = 104;
  // Largura da coluna do rótulo vertical + rótulos Baixo/Médio/Alto.
  static const double _larguraEixo = 22 + 4 + 40 + 4;

  @override
  Widget build(BuildContext context) {
    final faixas = Faixas9Box.dasLegendas(legendas);
    // célula[potencial 0..2][desempenho 0..2], potencial alto (2) no topo
    final celulas = List.generate(3, (_) => List.generate(3, (_) => <Map<String, dynamic>>[]));
    for (final a in avaliacoes) {
      final d = nota9BoxDecimal(a, 'desempenho', pesos);
      final p = nota9BoxDecimal(a, 'potencial', pesos);
      if (d == null || p == null) continue;
      celulas[faixas.faixa(p)][faixas.faixa(d)].add(a);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Rótulo vertical "POTENCIAL" ─────────────────────────────
            SizedBox(
              width: 22,
              height: _alturaCelula * 3,
              child: RotatedBox(
                quarterTurns: 3,
                child: Center(
                  child: Text('POTENCIAL',
                      style: GoogleFonts.poppins(
                          fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.dark)),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  for (var p = 2; p >= 0; p--)
                    SizedBox(
                      height: _alturaCelula,
                      child: Center(
                        child: Text(_labelsFaixaPotencial[p],
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.cinzaTexto)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                children: [
                  for (var p = 2; p >= 0; p--)
                    SizedBox(
                      height: _alturaCelula,
                      child: Row(
                        children: [
                          for (var d = 0; d < 3; d++)
                            Expanded(
                              child: _CelulaQuadrante(
                                info: _quadrantes[p][d],
                                legenda: legendas['p${p}_d$d'] ?? '',
                                colaboradores: celulas[p][d],
                                pesos: pesos,
                                onTapColaborador: onTapColaborador,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const SizedBox(width: _larguraEixo),
            for (var d = 0; d < 3; d++)
              Expanded(
                child: Center(
                  child: Text(_labelsFaixaDesempenho[d],
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.cinzaTexto)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('DESEMPENHO',
              style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.dark)),
        ),
        const SizedBox(height: 10),
        Text('Régua das notas: ${faixas.descricao}',
            style: GoogleFonts.poppins(fontSize: 10.5, color: AppColors.cinzaTexto)),
      ],
    );
  }
}

/// Célula compacta: só o nome, a cor e quantas pessoas caíram ali. Ao tocar,
/// abre uma folha com a descrição completa do quadrante e a lista de pessoas.
class _CelulaQuadrante extends StatelessWidget {
  final _InfoQuadrante info;
  final String legenda;
  final List<Map<String, dynamic>> colaboradores;
  final Map<int, Map<String, int>> pesos;
  final void Function(Map<String, dynamic> avaliacao) onTapColaborador;

  const _CelulaQuadrante({
    required this.info,
    required this.legenda,
    required this.colaboradores,
    required this.pesos,
    required this.onTapColaborador,
  });

  @override
  Widget build(BuildContext context) {
    final qtd = colaboradores.length;
    final vazio = qtd == 0;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: vazio ? info.cor.withValues(alpha: 0.45) : info.cor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _abrirFolha(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(info.icone, size: 16, color: Colors.white),
                  const Spacer(),
                  const Icon(Icons.info_outline_rounded, size: 13, color: Colors.white70),
                ]),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(info.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 10.5,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$qtd',
                        style: GoogleFonts.poppins(
                            fontSize: 22,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(qtd == 1 ? 'pessoa' : 'pessoas',
                          style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.white70)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _abrirFolha(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: info.cor, shape: BoxShape.circle),
                child: Icon(info.icone, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(info.titulo,
                    style: GoogleFonts.poppins(
                        fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark)),
              ),
            ]),
            if (legenda.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(legenda,
                  style: GoogleFonts.poppins(
                      fontSize: 13, height: 1.5, color: AppColors.cinzaTexto)),
            ],
            const SizedBox(height: 18),
            Text(
                colaboradores.isEmpty
                    ? 'Ninguém neste quadrante.'
                    : '${colaboradores.length} ${colaboradores.length == 1 ? 'pessoa' : 'pessoas'} neste quadrante',
                style: GoogleFonts.poppins(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.dark)),
            const SizedBox(height: 8),
            for (final a in colaboradores) _linhaColaborador(ctx, a),
          ],
        ),
      ),
    );
  }

  Widget _linhaColaborador(BuildContext ctx, Map<String, dynamic> a) {
    final colab = a['colaboradores'] as Map?;
    final nome = colab?['nome'] as String? ?? '?';
    final cargo = colab?['cargo'] as String?;
    final d = nota9BoxDecimal(a, 'desempenho', pesos);
    final p = nota9BoxDecimal(a, 'potencial', pesos);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.pop(ctx);
            onTapColaborador(a);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nome,
                        style: GoogleFonts.poppins(
                            fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.dark)),
                    if (cargo != null && cargo.isNotEmpty)
                      Text(cargo,
                          style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.cinzaTexto)),
                    if (d != null && p != null)
                      Text('Desempenho ${fmtNota(d)} · Potencial ${fmtNota(p)}',
                          style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.cinzaTexto),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Detalhe exclusivo de um colaborador ──────────────────────────────────────

class DetalheColaboradorAvaliacaoDialog extends StatelessWidget {
  final Map<String, dynamic> avaliacao;
  final Map<int, Map<String, int>> pesos;
  final Map<String, String> legendas;

  const DetalheColaboradorAvaliacaoDialog(
      {super.key,
      required this.avaliacao,
      required this.pesos,
      this.legendas = const {}});

  @override
  Widget build(BuildContext context) {
    final colab = avaliacao['colaboradores'] as Map?;
    final nome = colab?['nome'] as String? ?? '—';
    final cargoSetor = [colab?['cargo'], colab?['setor']]
        .whereType<String>()
        .where((s) => s.isNotEmpty && s != '—')
        .join(' · ');
    final d = nota9BoxDecimal(avaliacao, 'desempenho', pesos);
    final p = nota9BoxDecimal(avaliacao, 'potencial', pesos);
    final faixas = Faixas9Box.dasLegendas(legendas);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nome,
                            style: GoogleFonts.poppins(
                                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.dark)),
                        if (cargoSetor.isNotEmpty)
                          Text(cargoSetor,
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: AppColors.cinzaTexto)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              if (d != null && p != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _Badge(
                        label:
                            'Desempenho: ${fmtNota(d)} (${faixas.rotulo(d)})'),
                    _Badge(
                        label:
                            'Potencial: ${fmtNota(p)} (${faixas.rotulo(p)})'),
                  ],
                ),
              ],
              const Divider(height: 28),
              Flexible(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: ApiService()
                      .listarRespostasAvaliacaoComPergunta(avaliacao['id'] as int),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: CircularProgressIndicator(color: indigo9Box)),
                      );
                    }
                    final respostas = snap.data ?? [];
                    if (respostas.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                            'Sem respostas por pergunta registradas (avaliação antiga ou lançada sem perguntas cadastradas).',
                            style: GoogleFonts.poppins(
                                fontSize: 12.5, color: AppColors.cinzaTexto)),
                      );
                    }

                    // Agrupa por pergunta_id, juntando a resposta do
                    // colaborador e a do gestor lado a lado.
                    final porPergunta = <int, Map<String, dynamic>>{};
                    for (final r in respostas) {
                      final perguntaId = r['pergunta_id'] as int;
                      final pergunta = r['avaliacao_perguntas'] as Map?;
                      final entry = porPergunta.putIfAbsent(perguntaId, () => {
                            'texto': pergunta?['pergunta'] as String? ?? '—',
                            'dimensao': pergunta?['dimensao'] as String? ?? '',
                            'ordem': pergunta?['ordem'] as int? ?? 0,
                          });
                      if (r['origem'] == 'colaborador') {
                        entry['notaAuto'] = r['nota'] as int?;
                        entry['comentarioAuto'] = r['comentario'] as String?;
                      } else if (r['origem'] == 'equipe') {
                        // Pode ter várias respostas por pergunta — uma por
                        // colega avaliador — diferente de colaborador/gestor.
                        final lista = (entry['respostasEquipe'] ??=
                            <Map<String, dynamic>>[]) as List<Map<String, dynamic>>;
                        lista.add({
                          'nota': r['nota'] as int?,
                          'comentario': r['comentario'] as String?,
                        });
                      } else {
                        entry['notaGestor'] = r['nota'] as int?;
                        entry['comentarioGestor'] = r['comentario'] as String?;
                      }
                    }
                    final lista = porPergunta.values.toList()
                      ..sort((a, b) => (a['ordem'] as int).compareTo(b['ordem'] as int));

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: lista.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final r = lista[i];
                        final notaAuto = r['notaAuto'] as int?;
                        final notaGestor = r['notaGestor'] as int?;
                        final respostasEquipe =
                            (r['respostasEquipe'] as List<Map<String, dynamic>>?) ?? [];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r['texto'] as String,
                                  style: GoogleFonts.poppins(
                                      fontSize: 12.5, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              if (notaAuto != null)
                                _LinhaResposta(
                                    origem: 'Colaborador',
                                    nota: notaAuto,
                                    comentario: r['comentarioAuto'] as String?),
                              if (notaGestor != null)
                                _LinhaResposta(
                                    origem: 'Gestor',
                                    nota: notaGestor,
                                    comentario: r['comentarioGestor'] as String?),
                              for (var e = 0; e < respostasEquipe.length; e++)
                                if (respostasEquipe[e]['nota'] != null)
                                  _LinhaResposta(
                                      origem: respostasEquipe.length > 1
                                          ? 'Equipe (colega ${e + 1})'
                                          : 'Equipe',
                                      nota: respostasEquipe[e]['nota'] as int,
                                      comentario: respostasEquipe[e]['comentario'] as String?),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: indigo9Box.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w600, color: indigo9Box)),
    );
  }
}

class _LinhaResposta extends StatelessWidget {
  final String origem;
  final int nota;
  final String? comentario;

  const _LinhaResposta({required this.origem, required this.nota, this.comentario});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 86,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            margin: const EdgeInsets.only(top: 1, right: 8),
            decoration: BoxDecoration(
              color: origem == 'Gestor'
                  ? indigo9Box.withValues(alpha: 0.1)
                  : AppColors.cinzaClaro,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$origem: ${labelNota1a5(nota)}',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: origem == 'Gestor' ? indigo9Box : AppColors.cinzaTexto)),
          ),
          if (comentario != null && comentario!.trim().isNotEmpty)
            Expanded(
              child: Text(comentario!,
                  style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.dark)),
            ),
        ],
      ),
    );
  }
}
