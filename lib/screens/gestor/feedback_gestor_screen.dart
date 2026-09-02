import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';
import 'dar_feedback_screen.dart';

const _labelsEstrela = ['1', '2', '3', '4', '5'];

/// Tela "Feedback" do módulo Gestor: solicitações de feedback recebidas da
/// equipe (Atender/Recusar), botão para dar um novo feedback estruturado e
/// o histórico do que o gestor já deu. Diferente da tela "Elogiar" (módulo
/// "Para Você"), que é reconhecimento livre entre colegas sem notas.
class FeedbackGestorScreen extends StatefulWidget {
  const FeedbackGestorScreen({super.key});

  @override
  State<FeedbackGestorScreen> createState() => _FeedbackGestorScreenState();
}

class _FeedbackGestorScreenState extends State<FeedbackGestorScreen> {
  final _api = ApiService();
  bool _carregando = true;

  Map<int, Map<String, dynamic>> _colaboradoresPorId = {};
  List<Map<String, dynamic>> _pendentes = [];
  List<Map<String, dynamic>> _dados = [];
  List<Map<String, dynamic>> _itensEmpresa = [];

  int get _meuId => _api.colaboradorAtual!.id;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final meuId = _meuId;
    final resultados = await Future.wait([
      _api.buscarTodosColaboradores(),
      _api.listarSolicitacoesFeedbackRecebidas(meuId, apenasPendentes: true),
      _api.listarFeedbacksDadosPor(meuId),
      _api.listarItensEmpresaFeedback(),
    ]);
    if (!mounted) return;
    final colaboradores = resultados[0] as List<Map<String, dynamic>>;
    setState(() {
      _colaboradoresPorId = {
        for (final c in colaboradores) c['id'] as int: c,
      };
      // Adiciona o próprio gestor (não vem em buscarTodosColaboradores, que
      // exclui o usuário logado) pra resolver nomes no histórico se preciso.
      final eu = _api.colaboradorAtual;
      if (eu != null) {
        _colaboradoresPorId[eu.id] = {
          'id': eu.id,
          'nome': eu.nome,
          'setor': eu.setor,
          'cargo': eu.cargo,
        };
      }
      _pendentes = resultados[1] as List<Map<String, dynamic>>;
      _dados = resultados[2] as List<Map<String, dynamic>>;
      _itensEmpresa = resultados[3] as List<Map<String, dynamic>>;
      _carregando = false;
    });
  }

  Future<void> _abrirDarFeedback({
    Map<String, dynamic>? colaborador,
    int? solicitacaoId,
  }) async {
    ColaboradorModel? preSelecionado;
    if (colaborador != null) {
      preSelecionado = ColaboradorModel(
        id: colaborador['id'] as int,
        matricula: colaborador['matricula'] as String? ?? '',
        nome: colaborador['nome'] as String? ?? '',
        setor: colaborador['setor'] as String?,
        cargo: colaborador['cargo'] as String?,
      );
    }
    final enviado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DarFeedbackScreen(
          colaboradorPreSelecionado: preSelecionado,
          solicitacaoId: solicitacaoId,
        ),
      ),
    );
    if (enviado == true) {
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Feedback enviado!',
            style: AppTextStyles.corpoNormal.copyWith(color: Colors.white)),
        backgroundColor: AppColors.sucesso,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _recusarSolicitacao(int id) async {
    await _api.recusarSolicitacaoFeedback(id);
    await _carregar();
  }

  String _nomeItem(int slot) {
    final item = _itensEmpresa.where((i) => i['slot'] == slot).toList();
    if (item.isEmpty) return 'Item $slot';
    return item.first['nome'] as String? ?? 'Item $slot';
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
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('📝 Feedback',
                                style: AppTextStyles.tituloGrande.copyWith(color: Colors.white)),
                            Text('Avalie sua equipe e responda pedidos',
                                style: AppTextStyles.corpoBranco
                                    .copyWith(color: AppColors.brancoOp80)),
                          ],
                        ),
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
                    child: _carregando
                        ? const Center(
                            child: CircularProgressIndicator(color: AppColors.magenta))
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _abrirDarFeedback(),
                                    icon: const Icon(Icons.rate_review_outlined, size: 16),
                                    label: Text('Dar Feedback',
                                        style: AppTextStyles.corpoNormal
                                            .copyWith(color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.magenta,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                if (_pendentes.isNotEmpty) ...[
                                  Text('Solicitações pendentes (${_pendentes.length})',
                                      style: AppTextStyles.labelSecao),
                                  const SizedBox(height: 10),
                                  ..._pendentes.map(_cardPendente),
                                  const SizedBox(height: 24),
                                ],

                                Text('Feedbacks que você deu (${_dados.length})',
                                    style: AppTextStyles.labelSecao),
                                const SizedBox(height: 10),
                                if (_dados.isEmpty)
                                  Text('Você ainda não deu feedback pra ninguém da equipe.',
                                      style: AppTextStyles.corpoCinza)
                                else
                                  ..._dados.map(_cardDado),
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

  Widget _cardPendente(Map<String, dynamic> s) {
    // feedback_solicitacoes.solicitante_id é text no banco (guarda o id do
    // colaborador como string), não integer — 'as int' direto quebra.
    final solicitante =
        _colaboradoresPorId[int.parse(s['solicitante_id'].toString())];
    final mensagem = s['mensagem'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.magentaOp18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${solicitante?['nome'] ?? 'Alguém'} pediu um feedback seu',
              style: AppTextStyles.corpoNormal.copyWith(fontWeight: FontWeight.w600)),
          if (mensagem != null && mensagem.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(mensagem, style: AppTextStyles.corpoMenor),
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                // feedback_solicitacoes.id é bigint — o PostgREST/Supabase
                // serializa como string, então 'as int' quebra.
                onPressed: () =>
                    _recusarSolicitacao(int.parse(s['id'].toString())),
                child: Text('Recusar', style: AppTextStyles.corpoMenor),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: () => _abrirDarFeedback(
                  colaborador: solicitante,
                  solicitacaoId: int.parse(s['id'].toString()),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.magenta,
                  foregroundColor: Colors.white,
                ),
                child: Text('Atender',
                    style: AppTextStyles.corpoMenor.copyWith(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardDado(Map<String, dynamic> f) {
    final colab = _colaboradoresPorId[f['colaborador_id'] as int];
    final presencial = f['presencial'] as bool?;
    final item1 = f['item1_nota'] as int?;
    final item2 = f['item2_nota'] as int?;
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
                child: Text('Para ${colab?['nome'] ?? 'colaborador removido'}',
                    style: AppTextStyles.corpoMedio
                        .copyWith(color: AppColors.magenta, fontWeight: FontWeight.w700)),
              ),
              if (presencial == true) _Selo(texto: 'Presencial', cor: AppColors.sucesso),
            ],
          ),
          const SizedBox(height: 6),
          Text(f['texto'] as String? ?? '', style: AppTextStyles.corpoNormal),
          if (item1 != null || item2 != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (item1 != null)
                  _Selo(texto: '${_nomeItem(1)}: ${_labelsEstrela[item1 - 1]}★', cor: AppColors.magenta),
                if (item2 != null)
                  _Selo(texto: '${_nomeItem(2)}: ${_labelsEstrela[item2 - 1]}★', cor: AppColors.magenta),
              ],
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
      decoration: BoxDecoration(color: cor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(texto,
          style: AppTextStyles.corpoMinimo.copyWith(color: cor, fontWeight: FontWeight.w600)),
    );
  }
}
