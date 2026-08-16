import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const _labelsNivel = ['Baixo', 'Médio', 'Alto'];
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
  Map<String, dynamic>? _cicloAberto;
  Map<String, dynamic>? _avaliacao;
  String _tipoAvaliacao = 'gestor';
  List<Map<String, dynamic>> _perguntas = [];

  final Map<int, int> _notas = {};
  final Map<int, TextEditingController> _comentarioCtrls = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
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
      if (col.setor == null || col.setor!.isEmpty) {
        setState(() {
          _cicloAberto = null;
          _loading = false;
        });
        return;
      }
      final ciclo = await _api.buscarCicloAbertoParaSetor(col.setor!);
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
      final perguntas = await _api.listarPerguntasFuncao(col.cargo ?? '');
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
        _notas[pid] = ((respostasColab[pid]?['nota'] as int?) ?? 2).clamp(1, 3);
        _comentarioCtrls[pid] = TextEditingController(
            text: respostasColab[pid]?['comentario'] as String? ?? '');
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

  Future<void> _salvar() async {
    if (_avaliacao == null) return;
    setState(() => _salvando = true);
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

  Widget _seletorNivel(int valor, ValueChanged<int> onChanged) {
    return Row(
      children: List.generate(3, (i) {
        final n = i + 1;
        final sel = valor == n;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(n),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? AppColors.laranja : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: sel ? AppColors.laranja : const Color(0xFFE2E8F0)),
              ),
              child: Text(_labelsNivel[i],
                  style: AppTextStyles.corpoMedio.copyWith(
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : AppColors.dark)),
            ),
          ),
        );
      }),
    );
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
                          Text('📊 Minha Avaliação',
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Ainda não há perguntas cadastradas para a sua função.',
              textAlign: TextAlign.center, style: AppTextStyles.corpoCinza),
        ),
      );
    }

    final jaEnviada = _avaliacao?['autoavaliacao_em'] != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Autoavaliação · ${_cicloAberto!['nome']}', style: AppTextStyles.tituloPequeno),
          const SizedBox(height: 4),
          Text(
            jaEnviada
                ? 'Você já enviou sua autoavaliação. Pode ajustar até o gestor avaliar.'
                : 'Responda as perguntas abaixo sobre seu desempenho e potencial neste ciclo.',
            style: AppTextStyles.corpoCinza,
          ),
          const SizedBox(height: 20),
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
                  _seletorNivel(_notas[pid]!, (v) => setState(() => _notas[pid] = v)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _comentarioCtrls[pid],
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'Comentário (opcional)'),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
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
      ),
    );
  }
}
