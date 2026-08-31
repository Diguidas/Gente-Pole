import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';

/// Tela "Elogiar" — reconhecimento livre entre colegas (sem notas), pedido
/// de feedback ao próprio gestor, e tudo que o colaborador já recebeu
/// (elogios de colegas + feedback formal do gestor).
class ElogiarScreen extends StatefulWidget {
  const ElogiarScreen({super.key});

  @override
  State<ElogiarScreen> createState() => _ElogiarScreenState();
}

class _ElogiarScreenState extends State<ElogiarScreen> {
  final _api = ApiService();
  final _buscaCtrl = TextEditingController();
  final _textoCtrl = TextEditingController();

  bool _loading = true;
  bool _enviando = false;
  bool _pedindoFeedback = false;
  bool _anonimo = false;

  List<Map<String, dynamic>> _todosColaboradores = [];
  List<Map<String, dynamic>> _filtrados = [];
  Map<String, dynamic>? _colaboradorSelecionado;

  List<Map<String, dynamic>> _recebidos = [];
  List<Map<String, dynamic>> _solicitacoesEnviadas = [];
  ColaboradorModel? _meuGestor;

  @override
  void initState() {
    super.initState();
    _carregar();
    _buscaCtrl.addListener(_filtrar);
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    _textoCtrl.dispose();
    super.dispose();
  }

  int get _meuId => _api.colaboradorAtual!.id;

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final eu = _api.colaboradorAtual;
    final resultados = await Future.wait([
      _api.buscarTodosColaboradores(),
      _api.listarElogiosRecebidos(_meuId),
      _api.listarFeedbacksAvaliacao(_meuId),
      _api.listarSolicitacoesFeedbackEnviadas(_meuId),
      if (eu?.setor != null && eu?.empresa != null)
        _api.buscarGestorDoSetor(eu!.setor!, eu.empresa!)
      else
        Future.value(null),
    ]);
    if (!mounted) return;

    final elogios = (resultados[1] as List<Map<String, dynamic>>)
        .map((e) => {...e, '_tipo': 'elogio'})
        .toList();
    final feedbacks = (resultados[2] as List<Map<String, dynamic>>)
        .map((f) => {...f, '_tipo': 'feedback'})
        .toList();
    final combinados = [...elogios, ...feedbacks];
    combinados.sort((a, b) {
      final da = a['criado_em'] as String? ?? '';
      final db = b['criado_em'] as String? ?? '';
      return db.compareTo(da);
    });

    setState(() {
      _todosColaboradores = resultados[0] as List<Map<String, dynamic>>;
      _filtrados = _todosColaboradores;
      _recebidos = combinados;
      _solicitacoesEnviadas = resultados[3] as List<Map<String, dynamic>>;
      _meuGestor = resultados[4] as ColaboradorModel?;
      _loading = false;
    });

    // Marca como vistos os feedbacks formais que o colaborador acabou de ver.
    _api.marcarFeedbacksRecebidosComoVistos(_meuId);
  }

  void _filtrar() {
    final q = _buscaCtrl.text.toLowerCase().trim();
    setState(() {
      _filtrados = q.isEmpty
          ? _todosColaboradores
          : _todosColaboradores.where((c) {
              final nome = (c['nome'] as String? ?? '').toLowerCase();
              final setor = (c['setor'] as String? ?? '').toLowerCase();
              return nome.contains(q) || setor.contains(q);
            }).toList();
    });
  }

  bool get _jaTemPedidoAoGestorPendente =>
      _meuGestor != null &&
      _solicitacoesEnviadas.any((s) =>
          s['destinatario_id'].toString() == _meuGestor!.id.toString() &&
          s['status'] == 'pendente');

  Future<void> _pedirFeedbackAoGestor() async {
    if (_meuGestor == null) return;
    setState(() => _pedindoFeedback = true);
    try {
      await _api.criarSolicitacaoFeedback(
        solicitanteId: _meuId,
        destinatarioId: _meuGestor!.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Pedido enviado ao seu gestor!',
            style: AppTextStyles.corpoNormal.copyWith(color: Colors.white)),
        backgroundColor: AppColors.sucesso,
        behavior: SnackBarBehavior.floating,
      ));
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao enviar pedido: $e',
            style: AppTextStyles.corpoNormal.copyWith(color: Colors.white)),
        backgroundColor: AppColors.erro,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _pedindoFeedback = false);
    }
  }

  Future<void> _enviarElogio() async {
    final texto = _textoCtrl.text.trim();
    if (_colaboradorSelecionado == null || texto.isEmpty) return;
    setState(() => _enviando = true);
    try {
      await _api.criarElogio(
        autorId: _meuId,
        colaboradorId: _colaboradorSelecionado!['id'] as int,
        texto: texto,
        anonimo: _anonimo,
      );
      if (!mounted) return;
      _textoCtrl.clear();
      _buscaCtrl.clear();
      setState(() {
        _colaboradorSelecionado = null;
        _anonimo = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Elogio enviado!',
            style: AppTextStyles.corpoNormal.copyWith(color: Colors.white)),
        backgroundColor: AppColors.sucesso,
        behavior: SnackBarBehavior.floating,
      ));
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao enviar elogio: $e',
            style: AppTextStyles.corpoNormal.copyWith(color: Colors.white)),
        backgroundColor: AppColors.erro,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String _nomeColaborador(dynamic id) {
    if (id == null) return '—';
    final match = _todosColaboradores.where((c) => c['id'].toString() == id.toString());
    if (match.isEmpty) return '—';
    return match.first['nome'] as String? ?? '—';
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
                // Header
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('💛 Elogiar',
                              style: AppTextStyles.tituloGrande.copyWith(color: Colors.white)),
                          Text('Reconheça e seja reconhecido por colegas',
                              style: AppTextStyles.corpoBranco
                                  .copyWith(color: AppColors.brancoOp80)),
                        ],
                      ),
                    ],
                  ),
                ),

                // Corpo
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(color: AppColors.magenta))
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _cardPedirFeedback(),
                                const SizedBox(height: 24),

                                Text('Elogiar um colega', style: AppTextStyles.labelSecao),
                                const SizedBox(height: 10),
                                _buscaColaborador(),
                                if (_colaboradorSelecionado != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.magentaOp15,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Selecionado: ${_colaboradorSelecionado!['nome']}',
                                            style: AppTextStyles.corpoMedio,
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () =>
                                              setState(() => _colaboradorSelecionado = null),
                                          child: const Icon(Icons.close_rounded,
                                              size: 18, color: AppColors.cinzaTexto),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),

                                // Campo de texto
                                TextField(
                                  controller: _textoCtrl,
                                  maxLines: 4,
                                  maxLength: 1000,
                                  style: AppTextStyles.corpoNormal,
                                  decoration: InputDecoration(
                                    hintText: 'Escreva o elogio...',
                                    hintStyle: AppTextStyles.corpoCinza,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: AppColors.magenta),
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 10),

                                // Toggle anônimo
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Elogio anônimo',
                                                style: AppTextStyles.corpoNormal
                                                    .copyWith(fontWeight: FontWeight.w600)),
                                            Text(
                                              _anonimo
                                                  ? 'Seu nome não será exibido junto do elogio.'
                                                  : 'Seu nome será exibido junto do elogio.',
                                              style: AppTextStyles.corpoMenor,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Switch(
                                        value: _anonimo,
                                        activeColor: AppColors.magenta,
                                        onChanged: (v) => setState(() => _anonimo = v),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),

                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton.icon(
                                    onPressed: (_colaboradorSelecionado != null &&
                                            _textoCtrl.text.trim().isNotEmpty &&
                                            !_enviando)
                                        ? _enviarElogio
                                        : null,
                                    icon: _enviando
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.favorite_outline_rounded, size: 16),
                                    label: Text('Enviar elogio',
                                        style: AppTextStyles.corpoNormal
                                            .copyWith(color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.magenta,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 28),

                                Text('Feedback que você já recebeu',
                                    style: AppTextStyles.labelSecao),
                                const SizedBox(height: 10),
                                if (_recebidos.isEmpty)
                                  Text('Você ainda não recebeu nenhum elogio ou feedback.',
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
          const Icon(Icons.mail_outline_rounded, color: AppColors.magenta, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pedir feedback ao meu gestor',
                    style: AppTextStyles.corpoNormal.copyWith(fontWeight: FontWeight.w700)),
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
              onPressed:
                  (_jaTemPedidoAoGestorPendente || _pedindoFeedback) ? null : _pedirFeedbackAoGestor,
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

  Widget _buscaColaborador() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _buscaCtrl,
          style: AppTextStyles.corpoNormal,
          decoration: InputDecoration(
            hintText: 'Buscar colaborador...',
            hintStyle: AppTextStyles.corpoCinza,
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
        ),
        if (_buscaCtrl.text.isNotEmpty && _colaboradorSelecionado == null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: _filtrados.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text('Nenhum colaborador encontrado',
                        style: AppTextStyles.corpoCinza),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _filtrados.length,
                    itemBuilder: (context, i) {
                      final c = _filtrados[i];
                      return ListTile(
                        dense: true,
                        title: Text(c['nome'] as String? ?? '', style: AppTextStyles.corpoNormal),
                        subtitle: Text(c['setor'] as String? ?? '', style: AppTextStyles.corpoMenor),
                        onTap: () {
                          setState(() {
                            _colaboradorSelecionado = c;
                            _buscaCtrl.clear();
                          });
                        },
                      );
                    },
                  ),
          ),
      ],
    );
  }

  Widget _cardRecebido(Map<String, dynamic> item) {
    final anonimo = item['anonimo'] == true;
    final ehElogio = item['_tipo'] == 'elogio';
    final autor = item['autor'] as Map?;
    final nomeAutor = anonimo
        ? 'Anônimo'
        : (ehElogio ? _nomeColaborador(item['autor_id']) : (autor?['nome'] as String? ?? '—'));

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
                    style: AppTextStyles.corpoMedio
                        .copyWith(color: AppColors.magenta, fontWeight: FontWeight.w700)),
              ),
              _Selo(
                texto: ehElogio ? 'Elogio' : 'Feedback do gestor',
                cor: ehElogio ? AppColors.sucesso : AppColors.magenta,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(item['texto'] as String? ?? '', style: AppTextStyles.corpoNormal),
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
          style: AppTextStyles.corpoMinimo.copyWith(color: cor, fontWeight: FontWeight.w600)),
    );
  }
}
