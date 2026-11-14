import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../widgets/campo_texto_formatado.dart';
import '../../widgets/markdown_texto.dart';
import '../../widgets/modal_resposta.dart';
import '../../services/api_service.dart';

/// Tela "Elogiar" — reconhecimento livre entre colegas, elogios recebidos (com
/// resposta) e respostas aos elogios enviados. Feedback fica em Performance.
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

  List<Map<String, dynamic>> _todosColaboradores = [];
  List<Map<String, dynamic>> _filtrados = [];
  Map<String, dynamic>? _colaboradorSelecionado;

  List<Map<String, dynamic>> _recebidos = [];
  List<Map<String, dynamic>> _respostas = [];

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
    final resultados = await Future.wait([
      _api.buscarTodosColaboradores(),
      _api.listarElogiosRecebidos(_meuId),
      _api.listarRespostasAosMeusElogios(_meuId),
    ]);
    if (!mounted) return;

    setState(() {
      _todosColaboradores = resultados[0];
      // Não dá para elogiar a si mesmo.
      _filtrados =
          _todosColaboradores.where((c) => c['id'] != _meuId).toList();
      _recebidos = resultados[1];
      _respostas = resultados[2];
      _loading = false;
    });
  }

  void _filtrar() {
    final q = _buscaCtrl.text.toLowerCase().trim();
    setState(() {
      _filtrados = _todosColaboradores.where((c) {
        if (c['id'] == _meuId) return false;
        if (q.isEmpty) return true;
        final nome = (c['nome'] as String? ?? '').toLowerCase();
        final setor = (c['setor'] as String? ?? '').toLowerCase();
        return nome.contains(q) || setor.contains(q);
      }).toList();
    });
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
        anonimo: false,
      );
      if (!mounted) return;
      _textoCtrl.clear();
      _buscaCtrl.clear();
      setState(() {
        _colaboradorSelecionado = null;
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
                          Text('Elogiar',
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
                    clipBehavior: Clip.antiAlias,
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
                                CampoTextoFormatado(
                                  controller: _textoCtrl,
                                  hintText: 'Escreva o elogio...',
                                  maxLines: 4,
                                  onChanged: () => setState(() {}),
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

                                Text('Elogios que você recebeu',
                                    style: AppTextStyles.labelSecao),
                                const SizedBox(height: 10),
                                if (_recebidos.isEmpty)
                                  Text('Você ainda não recebeu nenhum elogio.',
                                      style: AppTextStyles.corpoCinza)
                                else
                                  ..._recebidos.map(_cardRecebido),
                                if (_respostas.isNotEmpty) ...[
                                  const SizedBox(height: 24),
                                  Text('Respostas aos meus elogios',
                                      style: AppTextStyles.labelSecao),
                                  const SizedBox(height: 10),
                                  ..._respostas.map(_cardResposta),
                                ],
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

  void _responder(Map<String, dynamic> item) {
    final anonimo = item['anonimo'] == true;
    final nome = anonimo ? 'Anônimo' : _nomeColaborador(item['autor_id']);
    mostrarModalResposta(
      context,
      titulo: anonimo ? 'Responder ao elogio' : 'Responder a $nome',
      subtitulo: anonimo
          ? 'Sua resposta chega a quem elogiou, sem revelar quem é.'
          : 'Sua resposta chega a $nome.',
      hint: 'Escreva seu agradecimento...',
      onEnviar: (resposta) async {
        final ok = await _api.responderElogio(
            elogioId: item['id'] as int, resposta: resposta);
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? 'Resposta enviada!' : 'Não foi possível enviar a resposta.',
              style: AppTextStyles.corpoNormal.copyWith(color: Colors.white)),
          backgroundColor: ok ? AppColors.sucesso : AppColors.erro,
          behavior: SnackBarBehavior.floating,
        ));
        if (ok) _carregar();
        return ok;
      },
    );
  }

  Widget _cardRecebido(Map<String, dynamic> item) {
    final anonimo = item['anonimo'] == true;
    final nomeAutor = anonimo ? 'Anônimo' : _nomeColaborador(item['autor_id']);
    final resposta = (item['resposta'] as String?)?.trim() ?? '';

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
              const _Selo(texto: 'Elogio', cor: AppColors.sucesso),
            ],
          ),
          const SizedBox(height: 6),
          MarkdownTexto(item['texto'] as String? ?? '', style: AppTextStyles.corpoNormal),
          const SizedBox(height: 8),
          if (resposta.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.magentaOp15,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Você respondeu: $resposta',
                  style: AppTextStyles.corpoMenor),
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _responder(item),
                icon: const Icon(Icons.reply_rounded, size: 16),
                label: Text('Responder',
                    style: AppTextStyles.corpoMenor
                        .copyWith(color: AppColors.magenta, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cardResposta(Map<String, dynamic> item) {
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
          Text('${_nomeColaborador(item['colaborador_id'])} respondeu ao seu elogio',
              style: AppTextStyles.corpoMedio
                  .copyWith(color: AppColors.magenta, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          MarkdownTexto(item['resposta'] as String? ?? '', style: AppTextStyles.corpoNormal),
          const SizedBox(height: 6),
          Text('Seu elogio: ${item['texto'] ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.corpoCinza),
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
