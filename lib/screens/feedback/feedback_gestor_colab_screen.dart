import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';
import '../../widgets/markdown_texto.dart';

/// Feedback formal do gestor para o colaborador (avaliacao_feedbacks) e
/// "Pedir feedback ao meu gestor". Antes ficava na tela Elogiar; agora é
/// acessado por Performance > Feedback.
class FeedbackGestorColabScreen extends StatefulWidget {
  const FeedbackGestorColabScreen({super.key});

  @override
  State<FeedbackGestorColabScreen> createState() =>
      _FeedbackGestorColabScreenState();
}

class _FeedbackGestorColabScreenState extends State<FeedbackGestorColabScreen> {
  final _api = ApiService();

  bool _loading = true;
  bool _pedindoFeedback = false;
  List<Map<String, dynamic>> _recebidos = [];
  List<Map<String, dynamic>> _solicitacoesEnviadas = [];
  List<Map<String, dynamic>> _itensEmpresa = [];
  ColaboradorModel? _meuGestor;

  int get _meuId => _api.colaboradorAtual!.id;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final eu = _api.colaboradorAtual;
    final resultados = await Future.wait([
      _api.listarFeedbacksAvaliacao(_meuId),
      _api.listarSolicitacoesFeedbackEnviadas(_meuId),
      _api.listarItensEmpresaFeedback().catchError((_) => <Map<String, dynamic>>[]),
      if (eu?.setor != null && eu?.empresa != null)
        _api.buscarGestorDoSetor(eu!.setor!, eu.empresa!, colaboradorId: eu.id)
      else
        Future.value(null),
    ]);
    if (!mounted) return;
    setState(() {
      _recebidos = resultados[0] as List<Map<String, dynamic>>;
      _solicitacoesEnviadas = resultados[1] as List<Map<String, dynamic>>;
      _itensEmpresa = resultados[2] as List<Map<String, dynamic>>;
      _meuGestor = resultados[3] as ColaboradorModel?;
      _loading = false;
    });
    // Marca como vistos os feedbacks formais que o colaborador acabou de ver.
    _api.marcarFeedbacksRecebidosComoVistos(_meuId);
  }

  bool get _jaTemPedidoAoGestorPendente =>
      _meuGestor != null &&
      _solicitacoesEnviadas.any((s) =>
          s['destinatario_id'].toString() == _meuGestor!.id.toString() &&
          s['status'] == 'pendente');

  String _nomeItem(int slot) {
    final item = _itensEmpresa.where((i) => i['slot'] == slot).toList();
    if (item.isEmpty) return 'Item $slot';
    return item.first['nome'] as String? ?? 'Item $slot';
  }

  /// Selos das notas (estrelas) dos itens da empresa: formato antigo
  /// (item1_nota/item2_nota, por slot) e o atual (itens_notas: id -> nota).
  List<Widget> _selosItens(Map<String, dynamic> f) {
    final selos = <Widget>[];
    final item1 = f['item1_nota'] as int?;
    final item2 = f['item2_nota'] as int?;
    if (item1 != null) {
      selos.add(_Selo(texto: '${_nomeItem(1)}: $item1★', cor: AppColors.magenta));
    }
    if (item2 != null) {
      selos.add(_Selo(texto: '${_nomeItem(2)}: $item2★', cor: AppColors.magenta));
    }
    final notas = (f['itens_notas'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final e in notas.entries) {
      final item = _itensEmpresa.where((i) => i['id'].toString() == e.key).toList();
      if (item.isEmpty) continue;
      selos.add(_Selo(
          texto: '${item.first['nome']}: ${e.value}★', cor: AppColors.magenta));
    }
    return selos;
  }

  void _snack(String msg, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: AppTextStyles.corpoNormal.copyWith(color: Colors.white)),
      backgroundColor: cor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _pedirFeedbackAoGestor() async {
    if (_meuGestor == null) return;
    setState(() => _pedindoFeedback = true);
    try {
      await _api.criarSolicitacaoFeedback(
        solicitanteId: _meuId,
        destinatarioId: _meuGestor!.id,
      );
      if (!mounted) return;
      _snack('Pedido enviado ao seu gestor!', AppColors.sucesso);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      _snack('Erro ao enviar pedido: $e', AppColors.erro);
    } finally {
      if (mounted) setState(() => _pedindoFeedback = false);
    }
  }

  Future<void> _confirmarPresencial(int feedbackId, bool confirmado) async {
    try {
      await _api.confirmarFeedbackPresencial(feedbackId, confirmado);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      _snack('Erro ao responder: $e', AppColors.erro);
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
                          Text('Feedback do gestor',
                              style: AppTextStyles.tituloGrande
                                  .copyWith(color: Colors.white)),
                          Text('O que seu gestor tem a dizer',
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
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.magenta))
                        : RefreshIndicator(
                            color: AppColors.magenta,
                            onRefresh: _carregar,
                            child: ListView(
                              padding: const EdgeInsets.all(20),
                              children: [
                                _cardPedirFeedback(),
                                const SizedBox(height: 24),
                                Text('Feedbacks que você recebeu',
                                    style: AppTextStyles.labelSecao),
                                const SizedBox(height: 10),
                                if (_recebidos.isEmpty)
                                  Text(
                                      'Você ainda não recebeu nenhum feedback do seu gestor.',
                                      style: AppTextStyles.corpoCinza)
                                else
                                  ..._recebidos.map(_cardRecebido),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardPedirFeedback() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.magentaOp15,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.magentaOp18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.mail_outline_rounded,
              color: AppColors.magenta, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pedir feedback ao meu gestor',
                    style: AppTextStyles.corpoNormal
                        .copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  _meuGestor == null
                      ? 'Não encontramos um gestor cadastrado para o seu setor.'
                      : 'Peça pra ${_meuGestor!.nome} te dar um retorno sobre seu trabalho.',
                  style: AppTextStyles.corpoMenor,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (_meuGestor != null)
            ElevatedButton(
              onPressed: (_jaTemPedidoAoGestorPendente || _pedindoFeedback)
                  ? null
                  : _pedirFeedbackAoGestor,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.magenta,
                foregroundColor: Colors.white,
              ),
              child: Text(
                _jaTemPedidoAoGestorPendente ? 'Pedido enviado' : 'Pedir',
                style: AppTextStyles.corpoMenor.copyWith(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cardRecebido(Map<String, dynamic> item) {
    final autor = item['autor'] as Map?;
    final nomeAutor = item['anonimo'] == true
        ? 'Anônimo'
        : (autor?['nome'] as String? ?? '—');
    final presencial = item['presencial'] as bool?;
    final presencialConfirmado = item['presencial_confirmado'] as bool?;
    final aguardandoConfirmacao =
        presencial == true && presencialConfirmado == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(nomeAutor,
                    style: AppTextStyles.corpoMedio.copyWith(
                        color: AppColors.magenta, fontWeight: FontWeight.w700)),
              ),
              if (presencial == true) ...[
                if (presencialConfirmado == true)
                  const _Selo(
                      texto: 'Presencial confirmado', cor: AppColors.sucesso)
                else if (presencialConfirmado == false)
                  const _Selo(texto: 'Presencial negado', cor: AppColors.erro)
                else
                  const _Selo(
                      texto: 'Presencial · aguardando',
                      cor: Color(0xFFF59E0B)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          MarkdownTexto(item['texto'] as String? ?? '',
              style: AppTextStyles.corpoNormal),
          if (_selosItens(item).isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: _selosItens(item)),
          ],
          if (aguardandoConfirmacao) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Essa conversa aconteceu presencialmente?',
                      style: AppTextStyles.corpoMenor
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () =>
                            _confirmarPresencial(item['id'] as int, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.sucesso,
                            foregroundColor: Colors.white),
                        child: Text('Sim, foi presencial',
                            style: AppTextStyles.corpoMinimo
                                .copyWith(color: Colors.white)),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () =>
                            _confirmarPresencial(item['id'] as int, false),
                        child: Text('Não foi', style: AppTextStyles.corpoMinimo),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  final String texto;
  final Color cor;
  const _Selo({required this.texto, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(texto,
          style: AppTextStyles.corpoMinimo
              .copyWith(color: cor, fontWeight: FontWeight.w600)),
    );
  }
}
