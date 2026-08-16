import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';

/// Tela "Dar Feedback" do módulo Gestor — feedback estruturado e avaliado
/// por estrelas que o gestor dá a um colaborador da equipe. Diferente da
/// tela "Elogiar" (reconhecimento livre, sem notas, entre quaisquer
/// colegas): aqui sempre há itens da empresa avaliados de 1 a 5 estrelas,
/// modelo de texto opcional, marcação de presencial e anotações internas
/// visíveis só para o autor.
///
/// Pode ser aberta em duas situações:
/// - Standalone, a partir do botão "Dar Feedback" — [colaboradorPreSelecionado]
///   e [solicitacaoId] nulos, o gestor escolhe o colaborador na busca.
/// - Atendendo uma solicitação pendente da equipe — ambos os parâmetros
///   preenchidos, o colaborador já vem travado e ao enviar a solicitação é
///   marcada como atendida.
class DarFeedbackScreen extends StatefulWidget {
  final ColaboradorModel? colaboradorPreSelecionado;
  final int? solicitacaoId;

  const DarFeedbackScreen({
    super.key,
    this.colaboradorPreSelecionado,
    this.solicitacaoId,
  });

  @override
  State<DarFeedbackScreen> createState() => _DarFeedbackScreenState();
}

class _DarFeedbackScreenState extends State<DarFeedbackScreen> {
  final _api = ApiService();
  final _buscaCtrl = TextEditingController();
  final _textoCtrl = TextEditingController();
  final _notasInternasCtrl = TextEditingController();

  bool _carregando = true;
  bool _enviando = false;

  List<Map<String, dynamic>> _todosColaboradores = [];
  List<Map<String, dynamic>> _filtrados = [];
  Map<String, dynamic>? _colaboradorSelecionado;

  List<Map<String, dynamic>> _itensEmpresa = [];
  List<Map<String, dynamic>> _modelos = [];
  int? _modeloSelecionadoId;
  final Map<int, int> _notasPorSlot = {}; // slot -> nota 1-5

  bool _anonimo = false;
  bool _presencial = false;

  @override
  void initState() {
    super.initState();
    if (widget.colaboradorPreSelecionado != null) {
      final c = widget.colaboradorPreSelecionado!;
      _colaboradorSelecionado = {
        'id': c.id,
        'nome': c.nome,
        'setor': c.setor,
        'cargo': c.cargo,
      };
    }
    _carregar();
    _buscaCtrl.addListener(_filtrar);
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    _textoCtrl.dispose();
    _notasInternasCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final resultados = await Future.wait([
      _api.buscarTodosColaboradores(),
      _api.listarItensEmpresaFeedback(),
      _api.listarModelosFeedback(apenasAtivos: true),
    ]);
    if (!mounted) return;
    setState(() {
      _todosColaboradores = resultados[0] as List<Map<String, dynamic>>;
      _filtrados = _todosColaboradores;
      _itensEmpresa = resultados[1] as List<Map<String, dynamic>>;
      _modelos = resultados[2] as List<Map<String, dynamic>>;
      _carregando = false;
    });
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

  void _selecionarModelo(int? modeloId) {
    setState(() {
      _modeloSelecionadoId = modeloId;
      if (modeloId == null) {
        _textoCtrl.clear();
      } else {
        final modelo = _modelos.firstWhere((m) => m['id'] == modeloId);
        _textoCtrl.text = modelo['texto'] as String? ?? '';
      }
    });
  }

  bool get _podeEnviar =>
      _colaboradorSelecionado != null &&
      _textoCtrl.text.trim().isNotEmpty &&
      _itensEmpresa.every((item) => _notasPorSlot[item['slot'] as int] != null);

  Future<void> _enviar() async {
    if (!_podeEnviar || _enviando) return;
    final autorId = _api.colaboradorAtual?.id;
    if (autorId == null) return;
    setState(() => _enviando = true);

    try {
      final slots = _itensEmpresa.map((i) => i['slot'] as int).toList();
      final feedbackId = await _api.criarFeedbackAvaliacao(
        colaboradorId: _colaboradorSelecionado!['id'] as int,
        autorId: autorId,
        texto: _textoCtrl.text.trim(),
        anonimo: _anonimo,
        presencial: _presencial,
        anotacoesInternas: _notasInternasCtrl.text.trim().isEmpty
            ? null
            : _notasInternasCtrl.text.trim(),
        modeloId: _modeloSelecionadoId,
        item1Nota: slots.isNotEmpty ? _notasPorSlot[slots[0]] : null,
        item2Nota: slots.length > 1 ? _notasPorSlot[slots[1]] : null,
      );

      if (widget.solicitacaoId != null) {
        await _api.marcarSolicitacaoFeedbackAtendida(
            widget.solicitacaoId!, feedbackId);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao enviar feedback: $e',
            style: AppTextStyles.corpoNormal.copyWith(color: Colors.white)),
        backgroundColor: AppColors.erro,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _enviando = false);
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
                          Text('📝 Dar Feedback',
                              style: AppTextStyles.tituloGrande.copyWith(color: Colors.white)),
                          Text('Avalie e oriente um colaborador da sua equipe',
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
                    child: _carregando
                        ? const Center(
                            child: CircularProgressIndicator(color: AppColors.magenta))
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Colaborador', style: AppTextStyles.labelSecao),
                                const SizedBox(height: 8),
                                if (widget.solicitacaoId != null)
                                  _cardColaboradorTravado()
                                else
                                  _buscaColaborador(),
                                const SizedBox(height: 18),

                                _switchCard(
                                  label: 'Feedback anônimo',
                                  descricao: 'Seu nome não será exibido junto do feedback.',
                                  valor: _anonimo,
                                  onChanged: (v) => setState(() => _anonimo = v),
                                ),
                                const SizedBox(height: 18),

                                if (_itensEmpresa.isNotEmpty) ...[
                                  ..._itensEmpresa.map((item) {
                                    final slot = item['slot'] as int;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _CardItemEmpresa(
                                        nome: item['nome'] as String? ?? 'Item $slot',
                                        legenda: item['legenda'] as String? ?? '',
                                        nota: _notasPorSlot[slot] ?? 0,
                                        onChanged: (n) => setState(() => _notasPorSlot[slot] = n),
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 6),
                                ],

                                Text('Modelo de feedback (opcional)',
                                    style: AppTextStyles.labelSecao),
                                const SizedBox(height: 8),
                                if (_modelos.isEmpty)
                                  Text('Nenhum modelo cadastrado ainda.',
                                      style: AppTextStyles.corpoCinza)
                                else
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<int?>(
                                        value: _modeloSelecionadoId,
                                        isExpanded: true,
                                        hint: Text('Escrever livremente',
                                            style: AppTextStyles.corpoNormal),
                                        onChanged: _selecionarModelo,
                                        items: [
                                          DropdownMenuItem<int?>(
                                            value: null,
                                            child: Text('Escrever livremente',
                                                style: AppTextStyles.corpoNormal),
                                          ),
                                          ..._modelos.map((m) => DropdownMenuItem<int?>(
                                                value: m['id'] as int,
                                                child: Text(m['titulo'] as String? ?? '',
                                                    style: AppTextStyles.corpoNormal),
                                              )),
                                        ],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 14),

                                TextField(
                                  controller: _textoCtrl,
                                  maxLines: 5,
                                  maxLength: 1000,
                                  style: AppTextStyles.corpoNormal,
                                  decoration: InputDecoration(
                                    hintText: 'Escreva o feedback...',
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
                                const SizedBox(height: 14),

                                _switchCard(
                                  label: 'Feedback presencial',
                                  descricao: 'Marque se essa conversa aconteceu pessoalmente.',
                                  valor: _presencial,
                                  onChanged: (v) => setState(() => _presencial = v),
                                ),
                                const SizedBox(height: 18),

                                Text('Anotações internas', style: AppTextStyles.labelSecao),
                                const SizedBox(height: 4),
                                Text(
                                  'Só você vê essas anotações — não aparecem para o colaborador nem para mais ninguém.',
                                  style: AppTextStyles.corpoMenor,
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _notasInternasCtrl,
                                  maxLines: 3,
                                  style: AppTextStyles.corpoNormal,
                                  decoration: InputDecoration(
                                    hintText: 'Anotações pessoais sobre essa conversa (opcional)...',
                                    hintStyle: AppTextStyles.corpoCinza,
                                    filled: true,
                                    fillColor: AppColors.cinzaClaro,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton.icon(
                                    onPressed: (_podeEnviar && !_enviando) ? _enviar : null,
                                    icon: _enviando
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.send_rounded, size: 16),
                                    label: Text('Enviar feedback',
                                        style: AppTextStyles.corpoNormal
                                            .copyWith(color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.magenta,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
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

  Widget _cardColaboradorTravado() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.cinzaTexto),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_colaboradorSelecionado?['nome'] as String? ?? '—',
                style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w600)),
          ),
          Text('atendendo solicitação', style: AppTextStyles.corpoMenor),
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
        if (_colaboradorSelecionado != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  onTap: () => setState(() => _colaboradorSelecionado = null),
                  child: const Icon(Icons.close_rounded, size: 18, color: AppColors.cinzaTexto),
                ),
              ],
            ),
          ),
        ],
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
                    child: Text('Nenhum colaborador encontrado', style: AppTextStyles.corpoCinza),
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

  Widget _switchCard({
    required String label,
    required String descricao,
    required bool valor,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                Text(label, style: AppTextStyles.corpoNormal.copyWith(fontWeight: FontWeight.w600)),
                Text(descricao, style: AppTextStyles.corpoMenor),
              ],
            ),
          ),
          Switch(value: valor, onChanged: onChanged, activeColor: AppColors.magenta),
        ],
      ),
    );
  }
}

class _CardItemEmpresa extends StatelessWidget {
  final String nome;
  final String legenda;
  final int nota;
  final ValueChanged<int> onChanged;

  const _CardItemEmpresa(
      {required this.nome, required this.legenda, required this.nota, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nome, style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w700)),
          if (legenda.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(legenda, style: AppTextStyles.corpoMenor),
            ),
          const SizedBox(height: 10),
          _Estrelas(nota: nota, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Estrelas extends StatelessWidget {
  final int nota;
  final ValueChanged<int> onChanged;

  const _Estrelas({required this.nota, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final valor = i + 1;
        final preenchida = valor <= nota;
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => onChanged(valor),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              preenchida ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 28,
              color: preenchida ? const Color(0xFFF59E0B) : AppColors.cinzaTexto.withOpacity(0.5),
            ),
          ),
        );
      }),
    );
  }
}
