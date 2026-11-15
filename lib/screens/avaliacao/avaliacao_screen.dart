import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/seletor_nota_widget.dart';

const _dimensoes = {'desempenho': 'Desempenho', 'potencial': 'Potencial'};

/// "Minha Avaliação" — autoavaliação 9-box do colaborador logado.
/// Porta a tela `avaliacao_colab_screen.dart` do app admin.
class AvaliacaoScreen extends StatefulWidget {
  const AvaliacaoScreen({super.key});

  @override
  State<AvaliacaoScreen> createState() => _AvaliacaoScreenState();
}

class _AvaliacaoScreenState extends State<AvaliacaoScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _salvando = false;
  String? _erro;
  String? _erroValidacao;
  Map<String, dynamic>? _cicloAberto;
  Map<String, dynamic>? _avaliacao;
  String _tipoAvaliacao = 'gestor';
  List<Map<String, dynamic>> _perguntas = [];

  bool _rascunhoRestaurado = false;
  final Map<int, int?> _notas = {};
  final Map<int, TextEditingController> _comentarioCtrls = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      final av = _avaliacao;
      if (av != null && av['autoavaliacao_em'] == null) {
        _api.salvarRascunho(_tipoRascunho, '${av['id']}', _dadosRascunho());
      }
    }
    for (final c in _comentarioCtrls.values) {
      c.dispose();
    }
    super.dispose();
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
      // Sem setor também busca o ciclo (geral ou por participantes), como no web.
      final ciclo = await _api.buscarCicloAbertoParaColaborador(
          colaboradorId: col.id, setor: col.setor);
      if (!mounted) return;
      if (ciclo == null) {
        setState(() {
          _cicloAberto = null;
          _loading = false;
        });
        return;
      }
      final avaliacao = await _api.buscarOuCriarAvaliacao(
        cicloId: ciclo['id'] as int,
        colaboradorId: col.id,
      );
      final perguntasLiberadas =
          avaliacao?['perguntas_liberadas'] as bool? ?? false;
      // Só busca as perguntas depois que o gestor definir (template ou
      // padrão) — antes disso não há o que responder ainda.
      final perguntas = (avaliacao == null || !perguntasLiberadas)
          ? <Map<String, dynamic>>[]
          : await _api.perguntasDaAvaliacao(avaliacao,
              funcao: col.cargo ?? '', setor: col.setor);
      final respostas = avaliacao == null
          ? <Map<String, dynamic>>[]
          : await _api.listarRespostasAvaliacao(avaliacao['id'] as int);
      final respostasColab = {
        for (final r in respostas.where((r) => r['origem'] == 'colaborador'))
          r['pergunta_id'] as int: r
      };

      for (final c in _comentarioCtrls.values) {
        c.dispose();
      }
      _notas.clear();
      _comentarioCtrls.clear();
      for (final p in perguntas) {
        final pid = p['id'] as int;
        _notas[pid] = (respostasColab[pid]?['nota'] as int?)?.clamp(1, 5);
        _comentarioCtrls[pid] = TextEditingController(
            text: respostasColab[pid]?['comentario'] as String? ?? '');
      }

      if (avaliacao != null && avaliacao['autoavaliacao_em'] == null) {
        await _restaurarRascunho(avaliacao['id'] as int);
      }

      if (!mounted) return;
      setState(() {
        _cicloAberto = ciclo;
        _avaliacao = avaliacao;
        _tipoAvaliacao = ciclo['tipo_avaliacao'] as String? ?? 'gestor';
        _perguntas = perguntas;
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

  // ── Rascunho no servidor: vale também em outro aparelho e no web ──────
  static const _tipoRascunho = 'autoavaliacao';
  Timer? _debounce;

  Future<void> _restaurarRascunho(int avaliacaoId) async {
    final m = await _api.buscarRascunho(_tipoRascunho, '$avaliacaoId');
    if (m == null) return;
    final notas = (m['notas'] as Map?) ?? {};
    final coment = (m['coment'] as Map?) ?? {};
    var restaurou = false;
    for (final pid in _notas.keys) {
      final n = notas['$pid'];
      if (n is int && _notas[pid] == null) {
        _notas[pid] = n.clamp(1, 5);
        restaurou = true;
      }
      final c = coment['$pid'];
      final ctrl = _comentarioCtrls[pid];
      if (c is String && c.isNotEmpty && ctrl != null && ctrl.text.isEmpty) {
        ctrl.text = c;
        restaurou = true;
      }
    }
    _rascunhoRestaurado = restaurou;
  }

  Map<String, dynamic> _dadosRascunho() => {
        'notas': {
          for (final e in _notas.entries)
            if (e.value != null) '${e.key}': e.value
        },
        'coment': {
          for (final e in _comentarioCtrls.entries)
            if (e.value.text.trim().isNotEmpty) '${e.key}': e.value.text
        },
      };

  /// Salva com debounce para não bater no servidor a cada tecla.
  void _guardarRascunho() {
    final av = _avaliacao;
    if (av == null || av['autoavaliacao_em'] != null) return;
    _debounce?.cancel();
    final id = '${av['id']}';
    _debounce = Timer(const Duration(milliseconds: 1500),
        () => _api.salvarRascunho(_tipoRascunho, id, _dadosRascunho()));
  }

  Future<void> _limparRascunho(int avaliacaoId) async {
    _debounce?.cancel();
    await _api.apagarRascunho(_tipoRascunho, '$avaliacaoId');
  }

  /// Prazo do ciclo (`data_fim`): dias restantes; null se não definido.
  int? get _diasRestantes {
    final fim = DateTime.tryParse(_cicloAberto?['data_fim'] as String? ?? '');
    if (fim == null) return null;
    final hoje = DateTime.now();
    return DateTime(fim.year, fim.month, fim.day)
        .difference(DateTime(hoje.year, hoje.month, hoje.day))
        .inDays;
  }

  Widget _bannerPrazo() {
    final fim = DateTime.tryParse(_cicloAberto?['data_fim'] as String? ?? '');
    final dias = _diasRestantes;
    if (fim == null || dias == null) return const SizedBox.shrink();
    final data =
        '${fim.day.toString().padLeft(2, '0')}/${fim.month.toString().padLeft(2, '0')}/${fim.year}';
    final String texto;
    if (dias < 0) {
      texto = 'Prazo encerrado em $data. Não é mais possível responder.';
    } else if (dias == 0) {
      texto = 'Último dia! O prazo termina hoje ($data).';
    } else {
      texto =
          'Prazo para responder: até $data (faltam $dias ${dias == 1 ? 'dia' : 'dias'}). Depois disso não será possível responder.';
    }
    final urgente = dias <= 3;
    final cor = urgente ? AppColors.erro : AppColors.laranja;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(0.4)),
      ),
      child: Row(children: [
        Icon(Icons.schedule_rounded, color: cor, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(texto,
              style: AppTextStyles.corpoMinimo
                  .copyWith(color: cor, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Future<void> _salvar() async {
    if (_avaliacao == null) return;
    if ((_diasRestantes ?? 0) < 0) {
      setState(() => _erroValidacao = 'O prazo desta avaliação já encerrou.');
      return;
    }
    if (_perguntas.any((p) => _notas[p['id'] as int] == null)) {
      setState(() =>
          _erroValidacao = 'Escolha uma nota de 1 a 5 em todas as perguntas.');
      return;
    }
    final semComentario = _perguntas
        .any((p) => _comentarioCtrls[p['id'] as int]!.text.trim().isEmpty);
    if (semComentario) {
      setState(() => _erroValidacao = 'Preencha o comentário de todas as perguntas.');
      return;
    }
    setState(() {
      _erroValidacao = null;
      _salvando = true;
    });
    final respostasParaSalvar = _perguntas
        .map((p) => {
              'perguntaId': p['id'],
              'dimensao': p['dimensao'],
              'nota': _notas[p['id'] as int],
              'comentario':
                  _comentarioCtrls[p['id'] as int]!.text.trim().isEmpty
                      ? null
                      : _comentarioCtrls[p['id'] as int]!.text.trim(),
            })
        .toList();
    try {
      await _api.salvarRespostasAvaliacao(
        avaliacaoId: _avaliacao!['id'] as int,
        origem: 'colaborador',
        respostas: respostasParaSalvar,
        avaliadorId: _avaliacao!['colaborador_id'] as int,
      );
      await _limparRascunho(_avaliacao!['id'] as int);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Autoavaliação enviada!'),
        backgroundColor: AppColors.sucesso,
        behavior: SnackBarBehavior.floating,
      ));
      _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao enviar autoavaliação: $e'),
        backgroundColor: AppColors.erro,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 200,
            decoration: const BoxDecoration(gradient: AppColors.gradientePrincipal),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                          Text('Minha Avaliação',
                              style: AppTextStyles.tituloGrande.copyWith(color: Colors.white)),
                          Text('Sua autoavaliação de desempenho',
                              style: AppTextStyles.corpoBranco.copyWith(color: AppColors.brancoOp80)),
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
      return const Center(child: CircularProgressIndicator(color: AppColors.laranja));
    }
    if (_erro != null) {
      return Center(child: Text(_erro!, style: AppTextStyles.corpoCinza));
    }
    if (_cicloAberto == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Nenhum ciclo de avaliação ativo no momento.',
              textAlign: TextAlign.center, style: AppTextStyles.corpoCinza),
        ),
      );
    }

    if (_tipoAvaliacao == 'gestor') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
              'Sua função é avaliada apenas pelo gestor neste ciclo. '
              'Não é necessário preencher uma autoavaliação.',
              textAlign: TextAlign.center,
              style: AppTextStyles.corpoCinza),
        ),
      );
    }

    if (_perguntas.isEmpty) {
      final aindaNaoLiberada =
          (_avaliacao?['perguntas_liberadas'] as bool? ?? false) == false;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
              aindaNaoLiberada
                  ? 'Seu gestor ainda não liberou as perguntas desta avaliação.'
                  : 'Ainda não há perguntas cadastradas para a sua função.',
              textAlign: TextAlign.center, style: AppTextStyles.corpoCinza),
        ),
      );
    }

    final jaEnviada = _avaliacao?['autoavaliacao_em'] != null;

    if (jaEnviada) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 64, color: AppColors.sucesso),
              const SizedBox(height: 16),
              Text('Você já respondeu a esta avaliação',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.tituloPequeno),
              const SizedBox(height: 8),
              Text(
                  'Ciclo: ${_cicloAberto!['nome']}. Sua autoavaliação foi enviada e não pode ser alterada — uma nova só abre quando o ciclo liberar outra.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.corpoCinza),
            ],
          ),
        ),
      );
    }

    final prazoEncerrado = (_diasRestantes ?? 0) < 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: AbsorbPointer(
        absorbing: prazoEncerrado,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Autoavaliação · ${_cicloAberto!['nome']}', style: AppTextStyles.tituloPequeno),
          const SizedBox(height: 4),
          Text(
            'Responda as perguntas abaixo sobre seu desempenho e potencial neste ciclo.',
            style: AppTextStyles.corpoCinza,
          ),
          const SizedBox(height: 12),
          _bannerPrazo(),
          if (_rascunhoRestaurado && !prazoEncerrado)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                  'Retomamos de onde você parou. Suas respostas são salvas automaticamente (também no web e em outro aparelho) até você enviar.',
                  style: AppTextStyles.corpoMinimo
                      .copyWith(color: AppColors.cinzaTexto)),
            ),
          const SizedBox(height: 8),
          ..._perguntas.map((p) {
            final pid = p['id'] as int;
            final dimensao = p['dimensao'] as String? ?? 'desempenho';
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.laranja.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(p['pergunta'] as String? ?? '',
                            style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.laranja.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_dimensoes[dimensao] ?? dimensao,
                            style: AppTextStyles.corpoMinimo.copyWith(
                                fontWeight: FontWeight.w600, color: AppColors.laranja)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SeletorNota1a5(
                      valor: _notas[pid],
                      onChanged: (v) {
                        setState(() => _notas[pid] = v);
                        _guardarRascunho();
                      },
                      legendaBaixa: p['legenda_nota_1'] as String?,
                      legendaAlta: p['legenda_nota_5'] as String?,
                      legendaMeio: [p['legenda_nota_2'] as String?, p['legenda_nota_3'] as String?, p['legenda_nota_4'] as String?]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _comentarioCtrls[pid],
                    maxLines: 2,
                    onChanged: (_) => _guardarRascunho(),
                    decoration: const InputDecoration(hintText: 'Comentário (obrigatório)'),
                  ),
                ],
              ),
            );
          }),
          if (_erroValidacao != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_erroValidacao!,
                  style: AppTextStyles.corpoMinimo.copyWith(color: AppColors.erro)),
            ),
          ],
          const SizedBox(height: 8),
          if (!prazoEncerrado)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _salvando ? null : _salvar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.laranja,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _salvando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      jaEnviada ? 'Atualizar autoavaliação' : 'Enviar autoavaliação',
                      style: AppTextStyles.botaoPrimario),
            ),
          ),
        ],
      )),
    );
  }
}
