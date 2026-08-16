import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const _labelsNivel = ['Baixo', 'Médio', 'Alto'];
const _dimensoes = {'desempenho': 'Desempenho', 'potencial': 'Potencial'};

/// "Avaliar Colegas" — quem foi convidado a avaliar um colega como "equipe"
/// num ciclo 360 responde aqui. Porta a tela
/// `avaliar_colegas_colab_screen.dart` do app admin.
class AvaliarColegasScreen extends StatefulWidget {
  const AvaliarColegasScreen({super.key});

  @override
  State<AvaliarColegasScreen> createState() => _AvaliarColegasScreenState();
}

class _AvaliarColegasScreenState extends State<AvaliarColegasScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _erro;
  List<Map<String, dynamic>> _pendentes = [];

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
      final pendentes = await _api.listarAvaliacoesEquipeParaAvaliar(col.id);
      if (!mounted) return;
      setState(() {
        _pendentes = pendentes;
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

  Widget _seletorNivel(int valor, ValueChanged<int> onChanged) {
    return Row(
      children: List.generate(3, (i) {
        final n = i + 1;
        final sel = valor == n;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(n),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? AppColors.laranja : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_labelsNivel[i],
                  style: AppTextStyles.corpoMinimo.copyWith(
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : AppColors.dark)),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _abrirAvaliacao(Map<String, dynamic> item) async {
    final avaliacao = item['avaliacoes'] as Map;
    final colab = avaliacao['colaboradores'] as Map?;
    final funcao = colab?['cargo'] as String? ?? '';
    final perguntas = await _api.listarPerguntasFuncao(funcao);
    if (!mounted) return;
    if (perguntas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nenhuma pergunta cadastrada para a função "$funcao".'),
      ));
      return;
    }

    final notas = <int, int>{};
    final comentarioCtrls = <int, TextEditingController>{};
    for (final p in perguntas) {
      final pid = p['id'] as int;
      notas[pid] = 2;
      comentarioCtrls[pid] = TextEditingController();
    }

    final salvou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setStateDialog) {
        return AlertDialog(
          title: Text('Avaliar ${colab?['nome'] as String? ?? ''}',
              style: AppTextStyles.tituloPequeno),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: perguntas.map((p) {
                  final pid = p['id'] as int;
                  final dimensao = p['dimensao'] as String? ?? 'desempenho';
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
                                  style: AppTextStyles.corpoMedio
                                      .copyWith(fontWeight: FontWeight.w600)),
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
                        const SizedBox(height: 8),
                        _seletorNivel(notas[pid]!, (v) => setStateDialog(() => notas[pid] = v)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: comentarioCtrls[pid],
                          maxLines: 2,
                          decoration: const InputDecoration(hintText: 'Comentário (opcional)'),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.laranja),
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
          origem: 'equipe',
          respostas: respostasParaSalvar,
          avaliadorId: col.id,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Avaliação enviada!'),
          backgroundColor: AppColors.sucesso,
          behavior: SnackBarBehavior.floating,
        ));
        _carregar();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao salvar: $e'),
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
                          Text('🤝 Avaliar Colegas',
                              style: AppTextStyles.tituloGrande.copyWith(color: Colors.white)),
                          Text('Avaliações de ciclo 360 pendentes',
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
    if (_pendentes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nenhuma avaliação de colega pendente no momento.',
            textAlign: TextAlign.center,
            style: AppTextStyles.corpoCinza,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _carregar,
      color: AppColors.laranja,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: _pendentes.map((item) {
          final avaliacao = item['avaliacoes'] as Map;
          final colab = avaliacao['colaboradores'] as Map?;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
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
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                onTap: () => _abrirAvaliacao(item),
                leading: CircleAvatar(
                  backgroundColor: AppColors.laranja.withOpacity(0.12),
                  backgroundImage: (colab?['foto_url'] as String?)?.isNotEmpty == true
                      ? NetworkImage(colab!['foto_url'] as String)
                      : null,
                  child: (colab?['foto_url'] as String?)?.isNotEmpty != true
                      ? Text(
                          ((colab?['nome'] as String?)?.isNotEmpty == true)
                              ? colab!['nome'].toString()[0]
                              : '?',
                          style: const TextStyle(color: AppColors.laranja))
                      : null,
                ),
                title: Text(colab?['nome'] as String? ?? '',
                    style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text(colab?['cargo'] as String? ?? '', style: AppTextStyles.corpoMinimo),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.laranja.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Avaliar',
                      style: AppTextStyles.corpoMinimo
                          .copyWith(fontWeight: FontWeight.w600, color: AppColors.laranja)),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
