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
  final gestor = a['gestor_$dimensao'] as int?;
  if (gestor == null) return null; // gestor ainda não avaliou
  final auto = a['autoavaliacao_$dimensao'] as int?;
  final equipe = a['equipe_$dimensao'] as int?;

  final templateId = a['template_id'] as int?;
  Map<String, int>? pesos;
  if (templateId != null && pesosPorTemplate != null) {
    pesos = pesosPorTemplate[templateId];
  }
  if (pesos == null) {
    final notas = [gestor, if (auto != null) auto, if (equipe != null) equipe];
    return (notas.reduce((x, y) => x + y) / notas.length).round().clamp(1, 5);
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
  if (somaPesos == 0) return gestor;
  return (somaValores / somaPesos).round().clamp(1, 5);
}

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

/// Reduz a nota 1-5 pra faixa 0 (baixo, 1-2) / 1 (médio, 3) / 2 (alto, 4-5).
int _faixa3(int nota1a5) {
  if (nota1a5 <= 2) return 0;
  if (nota1a5 == 3) return 1;
  return 2;
}

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

  @override
  Widget build(BuildContext context) {
    // célula[potencial 0..2][desempenho 0..2], potencial alto (2) no topo
    final celulas = List.generate(3, (_) => List.generate(3, (_) => <Map<String, dynamic>>[]));
    for (final a in avaliacoes) {
      final d = resultado9Box(a, 'desempenho', pesos);
      final p = resultado9Box(a, 'potencial', pesos);
      if (d == null || p == null) continue;
      celulas[_faixa3(p)][_faixa3(d)].add(a);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Rótulo vertical "POTENCIAL" ─────────────────────────────
              SizedBox(
                width: 26,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Center(
                    child: Text('POTENCIAL',
                        style: GoogleFonts.poppins(
                            fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dark)),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 46,
                child: Column(
                  children: [
                    for (var p = 2; p >= 0; p--)
                      Expanded(
                        child: Center(
                          child: Text(_labelsFaixaPotencial[p],
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                  fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.cinzaTexto)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  children: [
                    for (var p = 2; p >= 0; p--)
                      Expanded(
                        child: Row(
                          children: [
                            for (var d = 0; d < 3; d++)
                              Expanded(
                                child: _CelulaQuadrante(
                                  info: _quadrantes[p][d],
                                  legenda: legendas['p${p}_d$d'] ?? '',
                                  colaboradores: celulas[p][d],
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
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const SizedBox(width: 76),
            for (var d = 0; d < 3; d++)
              Expanded(
                child: Center(
                  child: Text(_labelsFaixaDesempenho[d],
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.cinzaTexto)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 76),
          child: Text('DESEMPENHO',
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dark)),
        ),
      ],
    );
  }
}

class _CelulaQuadrante extends StatelessWidget {
  final _InfoQuadrante info;
  final String legenda;
  final List<Map<String, dynamic>> colaboradores;
  final void Function(Map<String, dynamic> avaliacao) onTapColaborador;

  const _CelulaQuadrante({
    required this.info,
    required this.legenda,
    required this.colaboradores,
    required this.onTapColaborador,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 60),
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: info.cor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(info.icone, size: 15, color: Colors.white),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(info.titulo,
                          maxLines: 2,
                          style: GoogleFonts.poppins(
                              fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ],
                ),
                if (colaboradores.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: colaboradores
                        .map((a) => _ChipColaborador(
                              avaliacao: a,
                              onTap: () => onTapColaborador(a),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          if (legenda.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(legenda,
                style: GoogleFonts.poppins(
                    fontSize: 9.5, color: AppColors.cinzaTexto, height: 1.3)),
          ],
        ],
      ),
    );
  }
}

class _ChipColaborador extends StatelessWidget {
  final Map<String, dynamic> avaliacao;
  final VoidCallback onTap;

  const _ChipColaborador({required this.avaliacao, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nome =
        (avaliacao['colaboradores'] as Map?)?['nome'] as String? ?? '?';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(nome.split(' ').first,
              style: GoogleFonts.poppins(fontSize: 10)),
        ),
      ),
    );
  }
}

// ─── Detalhe exclusivo de um colaborador ──────────────────────────────────────

class DetalheColaboradorAvaliacaoDialog extends StatelessWidget {
  final Map<String, dynamic> avaliacao;
  final Map<int, Map<String, int>> pesos;

  const DetalheColaboradorAvaliacaoDialog(
      {super.key, required this.avaliacao, required this.pesos});

  @override
  Widget build(BuildContext context) {
    final colab = avaliacao['colaboradores'] as Map?;
    final nome = colab?['nome'] as String? ?? '—';
    final cargoSetor = [colab?['cargo'], colab?['setor']]
        .whereType<String>()
        .where((s) => s.isNotEmpty && s != '—')
        .join(' · ');
    final d = resultado9Box(avaliacao, 'desempenho', pesos);
    final p = resultado9Box(avaliacao, 'potencial', pesos);

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
                    _Badge(label: 'Desempenho: ${labelNota1a5(d)}'),
                    _Badge(label: 'Potencial: ${labelNota1a5(p)}'),
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
