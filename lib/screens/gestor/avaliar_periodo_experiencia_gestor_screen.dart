import 'package:gentepole/core/nome_foto.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/grid_9box.dart';
import '../../widgets/seletor_nota_widget.dart';
import '../../widgets/titulo_setor.dart';
import 'acompanhamento_experiencia_gestor.dart';

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
  Map<int, Map<String, int>> _pesos = {};
  Map<String, String> _legendas = {};
  // 0 = tela inicial (dois botões), 1 = Matriz 9Box, 2 = Acompanhamento.
  int _tela = 0;
  // Toda a hierarquia do gestor (alimenta o 9Box e o acompanhamento) e filtros
  // de mês/setor/líder compartilhados pelas duas telas.
  List<Map<String, dynamic>> _acomp = [];
  Map<int, Map<String, dynamic>> _porColab = {};
  int _meuId = 0;
  final _filtro = FiltroExperiencia();

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
      var todas = await _api.listarPeriodoExperienciaGestor(setores,
          responsavelId: col.id);
      // O sino avisa pela data de admissão, mas a avaliação só existe depois
      // que alguém a inicia. Se o RH ainda não iniciou, inicia aqui pra quem
      // já está na janela dos 45/90 dias, senão o líder vê o aviso e a tela
      // vazia.
      final idsComAvaliacao =
          todas.map((a) => a['colaborador_id'].toString()).toSet();
      final semAvaliacao = <String>{};
      for (final checkpoint in [45, 90]) {
        final devidos = await _api.listarColaboradoresFimExperiencia(
            setores: setores, checkpointDias: checkpoint, paraGestor: true);
        for (final c in devidos) {
          final id = c['id'].toString();
          if (!idsComAvaliacao.contains(id)) semAvaliacao.add(id);
        }
      }
      if (semAvaliacao.isNotEmpty) {
        var criou = false;
        for (final id in semAvaliacao) {
          try {
            criou = await _api.criarAvaliacaoPeriodoExperiencia(int.parse(id)) ||
                criou;
          } catch (_) {}
        }
        if (criou) {
          todas = await _api.listarPeriodoExperienciaGestor(setores,
              responsavelId: col.id);
        }
      }
      // Toda a hierarquia abaixo do gestor (não só a equipe direta): vale para a
      // Matriz 9Box e para o acompanhamento. Pendente só dentro da janela;
      // avaliado (concluído) entra sempre.
      final acomp = await _api.buscarAcompanhamentoExperiencia(
          setores: setores, responsavelId: col.id);
      final itens = acomp
          .where((a) =>
              a['status'] == 'concluida' ||
              _temAvaliacaoConcluida(a) ||
              _naJanelaData('${a['data_admissao'] ?? ''}'))
          .toList();
      final avaliadas = [
        for (final a in itens)
          if (_temAvaliacaoConcluida(a))
            Map<String, dynamic>.from(a['avaliacao'] as Map)
      ];
      final templateIds = avaliadas
          .map((a) => a['template_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();
      final extras = await Future.wait([
        _api.buscarPesosTemplates(templateIds),
        _api.listarNineBoxLegendas(),
      ]);
      if (!mounted) return;
      setState(() {
        _avaliacoes = todas
            .where((a) => a['gestor_em'] == null && _naJanela(a))
            .toList();
        _acomp = itens;
        _porColab = {for (final a in itens) a['id'] as int: a};
        _meuId = col.id;
        _pesos = extras[0] as Map<int, Map<String, int>>;
        _legendas = extras[1] as Map<String, String>;
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

    final notas = <int, int?>{};
    final comentarioCtrls = <int, TextEditingController>{};
    for (final p in perguntas) {
      final pid = p['id'] as int;
      notas[pid] = (respostasGestor[pid]?['nota'] as int?)?.clamp(1, 5);
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
                              valor: notas[pid],
                              corSelecionada: _indigo,
                              onChanged: (v) => setStateDialog(() => notas[pid] = v),
                              legendaBaixa: p['legenda_nota_1'] as String?,
                              legendaAlta: p['legenda_nota_5'] as String?,
                      legendaMeio: [p['legenda_nota_2'] as String?, p['legenda_nota_3'] as String?, p['legenda_nota_4'] as String?]),
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
                if (perguntas.any((p) => notas[p['id'] as int] == null)) {
                  setStateDialog(() =>
                      erroDialog = 'Escolha uma nota de 1 a 5 em todas as perguntas.');
                  return;
                }
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
    // Voltar (botão do sistema) numa das duas telas leva à tela inicial.
    return PopScope(
      canPop: _tela == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tela = 0);
      },
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
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
                          Text('Período de Experiência',
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
                    clipBehavior: Clip.antiAlias,
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
    return RefreshIndicator(
      onRefresh: _carregar,
      color: _indigo,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: switch (_tela) {
          1 => _telaNineBox(),
          2 => _telaAcompanhamento(),
          _ => _telaInicial(),
        },
      ),
    );
  }

  // ── Tela inicial: dois botões ───────────────────────────────────────────

  List<Widget> _telaInicial() {
    final avaliados = _acomp.where(_temAvaliacaoConcluida).length;
    final paraFazer = _avaliacoes.length;
    final pendentes = _acomp.where((a) => a['status'] != 'concluida').length;
    return [
      Text('Escolha o que você quer ver',
          style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      _botaoTela(
        icone: Icons.grid_view_rounded,
        titulo: 'Matriz 9Box',
        descricao:
            '$avaliados ${avaliados == 1 ? 'pessoa avaliada' : 'pessoas avaliadas'} na sua hierarquia',
        onTap: () => setState(() => _tela = 1),
      ),
      const SizedBox(height: 14),
      _botaoTela(
        icone: Icons.fact_check_outlined,
        titulo: 'Acompanhamento e pendências',
        descricao: '$paraFazer para você avaliar · $pendentes pendentes na hierarquia',
        destaque: paraFazer > 0,
        onTap: () => setState(() => _tela = 2),
      ),
    ];
  }

  Widget _botaoTela({
    required IconData icone,
    required String titulo,
    required String descricao,
    required VoidCallback onTap,
    bool destaque = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: destaque ? _indigo : const Color(0xFFE2E8F0),
              width: destaque ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
              color: _indigo.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _indigo.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icone, color: _indigo),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo,
                  style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(descricao, style: AppTextStyles.corpoMinimo),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.cinzaTexto),
        ]),
      ),
    );
  }

  Widget _cabecalhoTela(String titulo) => Row(children: [
        InkWell(
          onTap: () => setState(() => _tela = 0),
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.arrow_back_rounded, size: 22),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(titulo,
              style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w700)),
        ),
      ]);

  // ── Tela 1: Matriz 9Box (toda a hierarquia, com filtros) ───────────────

  bool _temAvaliacaoConcluida(Map<String, dynamic> a) =>
      (a['avaliacao'] as Map?)?['gestor_em'] != null;

  List<Widget> _telaNineBox() {
    final base = _acomp.where(_temAvaliacaoConcluida).toList();
    final avaliadas = [
      for (final a in base)
        if (_filtro.aplica(a)) Map<String, dynamic>.from(a['avaliacao'] as Map)
    ];
    return [
      _cabecalhoTela('Matriz 9Box · Período de Experiência'),
      const SizedBox(height: 14),
      BarraFiltrosExperiencia(
          itens: base,
          meuId: _meuId,
          filtro: _filtro,
          onMudou: () => setState(() {})),
      const SizedBox(height: 16),
      _quadroFixo(avaliadas),
    ];
  }

  // ── Tela 2: o que fazer + quem falta (toda a hierarquia, com filtros) ──

  /// Aplica o filtro de mês/setor/líder também à avaliação da lista "para você
  /// fazer" (usa os dados da hierarquia dessa pessoa).
  bool _passaFiltro(Map<String, dynamic> avaliacao) {
    final id = (avaliacao['colaborador_id'] as num).toInt();
    final colab = avaliacao['colaboradores'] as Map?;
    final item = _porColab[id] ??
        {
          'data_admissao': colab?['data_admissao'],
          'setor': colab?['setor'],
          'lideres': const [],
        };
    return _filtro.aplica(item);
  }

  List<Widget> _telaAcompanhamento() {
    final paraFazer = _avaliacoes.where(_passaFiltro).toList();
    return [
      _cabecalhoTela('Acompanhamento e pendências'),
      const SizedBox(height: 14),
      BarraFiltrosExperiencia(
          itens: _acomp,
          meuId: _meuId,
          filtro: _filtro,
          onMudou: () => setState(() {})),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
            paraFazer.isEmpty
                ? 'Nenhuma avaliação para você fazer no momento'
                : '${paraFazer.length} ${paraFazer.length == 1 ? 'avaliação para você fazer' : 'avaliações para você fazer'}',
            style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w600)),
      ),
      ..._listaParaFazer(paraFazer),
      const SizedBox(height: 20),
      AcompanhamentoExperienciaGestor(
          itens: _acomp, meuId: _meuId, filtro: _filtro),
    ];
  }

  /// Só vale avaliar dentro da janela da experiência: de 10 dias antes dos 45
  /// até o dia 91, sem buraco. Avaliação antiga em aberto fora disso (ex.: 106
  /// dias de casa) não aparece mais.
  bool _naJanelaData(String? admissao) {
    final adm = DateTime.tryParse(admissao ?? '');
    if (adm == null) return true;
    final dias = DateTime.now().difference(adm).inDays;
    return ApiService.dentroDaJanelaExperiencia(45, dias) ||
        ApiService.dentroDaJanelaExperiencia(90, dias);
  }

  bool _naJanela(Map<String, dynamic> a) => _naJanelaData(
      '${(a['colaboradores'] as Map?)?['data_admissao'] ?? ''}');

  /// Lista "para você fazer" (agrupada por setor), já filtrada.
  List<Widget> _listaParaFazer(List<Map<String, dynamic>> avaliacoes) {
    return [
          ...intercalarSetores<Map<String, dynamic>>(
                  avaliacoes,
                  (a) => (a['colaboradores'] as Map?)?['setor'] as String?)
              .map((item) {
          if (item is CabecalhoSetorItem) {
            return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TituloSetor(item));
          }
          final avaliacao = item as Map<String, dynamic>;
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
                leading: FotoClicavel(url: colab?['foto_url'] as String?, nome: colab?['nome'] as String?, child: CircleAvatar(
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
                )),
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
          }),
    ];
  }

  void _abrirDetalhe(Map<String, dynamic> avaliacao) {
    showDialog(
      context: context,
      builder: (_) => DetalheColaboradorAvaliacaoDialog(
          avaliacao: avaliacao, pesos: _pesos, legendas: _legendas),
    );
  }

  /// Matriz 9Box fixa no topo (igual à Matriz 9Box e à Avaliação de
  /// Desempenho) com quem o gestor já avaliou no período de experiência.
  Widget _quadroFixo(List<Map<String, dynamic>> avaliadas) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Matriz 9Box · Período de Experiência',
              style: AppTextStyles.corpoMedio
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              avaliadas.isEmpty
                  ? 'Nenhuma avaliação concluída nesta seleção. Quando houver, os colaboradores aparecem na matriz.'
                  : 'Toque num quadrante para ver a descrição e as pessoas.',
              style: AppTextStyles.corpoMinimo),
          const SizedBox(height: 14),
          Grid9Box(
            avaliacoes: avaliadas,
            pesos: _pesos,
            legendas: _legendas,
            onTapColaborador: _abrirDetalhe,
          ),
        ],
      ),
    );
  }
}
