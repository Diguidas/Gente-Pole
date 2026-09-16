import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/seletor_nota_widget.dart';

const _indigo = Color(0xFF6366F1);
const _dimensoes = {'desempenho': 'Desempenho', 'potencial': 'Potencial'};

/// "Avaliar Período de Experiência" (gestor) — contrapartida de
/// [PeriodoExperienciaScreen] (colaborador). Porta
/// `avaliar_periodo_experiencia_gestor_screen.dart` do app admin: lista as
/// avaliações de período de experiência pendentes da equipe do gestor e
/// abre um formulário de avaliação por colaborador.
///
/// Usa a mesma escala de 1 a 5 do web ([SeletorNota1a5]), unificada com o
/// restante do módulo de Performance.
class AvaliarPeriodoExperienciaGestorScreen extends StatefulWidget {
  const AvaliarPeriodoExperienciaGestorScreen({super.key});

  @override
  State<AvaliarPeriodoExperienciaGestorScreen> createState() =>
      _AvaliarPeriodoExperienciaGestorScreenState();
}

class _AvaliarPeriodoExperienciaGestorScreenState
    extends State<AvaliarPeriodoExperienciaGestorScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _erro;
  List<Map<String, dynamic>> _avaliacoes = [];

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
      final col = _api.colaboradorAtual;
      if (col == null) {
        setState(() {
          _erro = 'Perfil não encontrado.';
          _loading = false;
        });
        return;
      }
      final setores = await _api.buscarSetoresEfetivosDoGestor();
      final todas = await _api.listarPeriodoExperienciaGestor(setores);
      if (!mounted) return;
      setState(() {
        _avaliacoes = todas.where((a) => a['gestor_em'] == null).toList();
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

  Future<void> _abrirAvaliacao(Map<String, dynamic> avaliacao) async {
    final colab = avaliacao['colaboradores'] as Map?;
    final funcao = colab?['cargo'] as String? ?? '';
    final setor = colab?['setor'] as String?;
    final perguntas =
        await _api.perguntasDaAvaliacao(avaliacao, funcao: funcao, setor: setor);
    if (!mounted) return;
    if (perguntas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Esse template ainda não tem perguntas cadastradas.'),
      ));
      return;
    }
    final respostas =
        await _api.listarRespostasAvaliacao(avaliacao['id'] as int);
    if (!mounted) return;
    final respostasColab = {
      for (final r in respostas.where((r) => r['origem'] == 'colaborador'))
        r['pergunta_id'] as int: r
    };
    final respostasGestor = {
      for (final r in respostas.where((r) => r['origem'] == 'gestor'))
        r['pergunta_id'] as int: r
    };

    final notas = <int, int>{};
    final comentarioCtrls = <int, TextEditingController>{};
    for (final p in perguntas) {
      final pid = p['id'] as int;
      notas[pid] =
          ((respostasGestor[pid]?['nota'] as int?) ?? 3).clamp(1, 5);
      comentarioCtrls[pid] = TextEditingController(
          text: respostasGestor[pid]?['comentario'] as String? ?? '');
    }
    String? erroDialog;

    final salvou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setStateDialog) {
        return AlertDialog(
          title: Text(
              '${colab?['nome'] as String? ?? ''} · Período de Experiência',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...perguntas.map((p) {
                    final pid = p['id'] as int;
                    final dimensao = p['dimensao'] as String? ?? 'desempenho';
                    final respColab = respostasColab[pid];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(p['pergunta'] as String? ?? '',
                                    style: GoogleFonts.poppins(
                                        fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _indigo.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(_dimensoes[dimensao] ?? dimensao,
                                    style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: _indigo)),
                              ),
                            ],
                          ),
                          if (respColab != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FC),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'Autoavaliação: ${labelNota1a5(((respColab['nota'] as int?) ?? 3).clamp(1, 5))}',
                                      style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.cinzaTexto)),
                                  if ((respColab['comentario'] as String? ?? '')
                                      .isNotEmpty)
                                    Text(respColab['comentario'] as String,
                                        style: GoogleFonts.poppins(
                                            fontSize: 11, color: AppColors.cinzaTexto)),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          SeletorNota1a5(
                              valor: notas[pid]!,
                              corSelecionada: _indigo,
                              onChanged: (v) => setStateDialog(() => notas[pid] = v)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: comentarioCtrls[pid],
                            maxLines: 2,
                            decoration:
                                const InputDecoration(hintText: 'Comentário (obrigatório)'),
                            style: GoogleFonts.poppins(fontSize: 12.5),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (erroDialog != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(erroDialog!,
                          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.erro)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                final semComentario = perguntas.any(
                    (p) => comentarioCtrls[p['id'] as int]!.text.trim().isEmpty);
                if (semComentario) {
                  setStateDialog(() =>
                      erroDialog = 'Preencha o comentário de todas as perguntas.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _indigo),
              child: const Text('Salvar', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );

    if (salvou == true) {
      final col = _api.colaboradorAtual;
      if (col == null) return;
      final respostasParaSalvar = perguntas
          .map((p) => {
                'perguntaId': p['id'],
                'dimensao': p['dimensao'],
                'nota': notas[p['id'] as int],
                'comentario': comentarioCtrls[p['id'] as int]!.text.trim().isEmpty
                    ? null
                    : comentarioCtrls[p['id'] as int]!.text.trim(),
              })
          .toList();
      try {
        await _api.salvarRespostasAvaliacao(
          avaliacaoId: avaliacao['id'] as int,
          origem: 'gestor',
          respostas: respostasParaSalvar,
          avaliadorId: col.id,
          gestorId: col.id,
        );
        final notaFinal =
            await _api.calcularNotaFinalPeriodoExperiencia(avaliacao['id'] as int);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(notaFinal != null
              ? 'Avaliação salva! Nota final: $notaFinal/5'
              : 'Avaliação salva!'),
          backgroundColor: AppColors.sucesso,
          behavior: SnackBarBehavior.floating,
        ));
        _carregar();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao salvar avaliação: $e'),
          backgroundColor: AppColors.erro,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 200,
            decoration:
                const BoxDecoration(gradient: AppColors.gradientePrincipal),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('🧭 Período de Experiência',
                              style: AppTextStyles.tituloGrande
                                  .copyWith(color: Colors.white)),
                          Text('Avalie a equipe em período de experiência',
                              style: AppTextStyles.corpoBranco
                                  .copyWith(color: AppColors.brancoOp80)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _indigo));
    }
    if (_erro != null) {
      return Center(child: Text(_erro!, style: AppTextStyles.corpoCinza));
    }
    if (_avaliacoes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
              'Nenhuma avaliação de período de experiência pendente no momento.',
              textAlign: TextAlign.center,
              style: AppTextStyles.corpoCinza),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _carregar,
      color: _indigo,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: _avaliacoes.map((avaliacao) {
          final colab = avaliacao['colaboradores'] as Map?;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _indigo.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                onTap: () => _abrirAvaliacao(avaliacao),
                leading: CircleAvatar(
                  backgroundColor: _indigo.withOpacity(0.12),
                  backgroundImage: (colab?['foto_url'] as String?)?.isNotEmpty == true
                      ? NetworkImage(colab!['foto_url'] as String)
                      : null,
                  child: (colab?['foto_url'] as String?)?.isNotEmpty != true
                      ? Text(
                          ((colab?['nome'] as String?)?.isNotEmpty == true)
                              ? colab!['nome'].toString()[0]
                              : '?',
                          style: const TextStyle(color: _indigo))
                      : null,
                ),
                title: Text(colab?['nome'] as String? ?? '',
                    style:
                        AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w600)),
                subtitle:
                    Text(colab?['cargo'] as String? ?? '', style: AppTextStyles.corpoMinimo),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _indigo.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Avaliar',
                      style: AppTextStyles.corpoMinimo
                          .copyWith(fontWeight: FontWeight.w600, color: _indigo)),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
