import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

class PesquisaRespostaScreen extends StatefulWidget {
  final int pesquisaId;
  final String titulo;
  final bool anonima;

  const PesquisaRespostaScreen({
    super.key,
    required this.pesquisaId,
    required this.titulo,
    required this.anonima,
  });

  @override
  State<PesquisaRespostaScreen> createState() =>
      _PesquisaRespostaScreenState();
}

class _PesquisaRespostaScreenState extends State<PesquisaRespostaScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _perguntas = [];
  bool _loading = true;
  bool _enviando = false;

  // Guarda as respostas: pergunta_id → valor (String | int | bool)
  final Map<int, dynamic> _respostas = {};

  @override
  void initState() {
    super.initState();
    _carregarPerguntas();
  }

  Future<void> _carregarPerguntas() async {
    final lista = await _api.buscarPerguntasPesquisa(widget.pesquisaId);
    if (mounted) {
      setState(() {
        _perguntas = lista;
        _loading = false;
      });
    }
  }

  Future<void> _enviar() async {
    // Valida obrigatórias
    for (final p in _perguntas) {
      final obrigatoria = p['obrigatoria'] as bool? ?? true;
      final id = p['id'] as int;
      if (obrigatoria && !_respostas.containsKey(id)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Responda todas as perguntas obrigatórias.',
              style: AppTextStyles.corpoNormal.copyWith(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() => _enviando = true);

    final ok = await _api.responderPesquisa(
      pesquisaId: widget.pesquisaId,
      anonima: widget.anonima,
      respostas: _respostas,
    );

    if (!mounted) return;
    setState(() => _enviando = false);

    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Respostas enviadas com sucesso! 🎉',
            style: AppTextStyles.corpoNormal.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.magenta,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao enviar. Tente novamente.',
            style: AppTextStyles.corpoNormal.copyWith(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 200,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
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
                            Text(
                              widget.titulo,
                              style: AppTextStyles.tituloGrande
                                  .copyWith(color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.anonima)
                              Text(
                                '🛡️ Pesquisa anônima',
                                style: AppTextStyles.corpoBranco
                                    .copyWith(color: AppColors.brancoOp80),
                              ),
                          ],
                        ),
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
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.magenta,
                            ),
                          )
                        : Column(
                            children: [
                              Expanded(
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 24, 16, 16),
                                  itemCount: _perguntas.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 16),
                                  itemBuilder: (context, i) =>
                                      _cardPergunta(_perguntas[i], i),
                                ),
                              ),
                              // Botão enviar
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 8, 16, 24),
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: _enviando ? null : _enviar,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.magenta,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                    ),
                                    child: _enviando
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(
                                            'Enviar respostas',
                                            style:
                                                AppTextStyles.botaoPrimario,
                                          ),
                                  ),
                                ),
                              ),
                            ],
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

  Widget _cardPergunta(Map<String, dynamic> p, int index) {
    final id = p['id'] as int;
    final texto = p['texto'] as String? ?? '';
    final tipo = p['tipo'] as String? ?? 'texto_livre';
    final obrigatoria = p['obrigatoria'] as bool? ?? true;
    final opcoes = (p['opcoes'] as List?)?.cast<String>() ?? [];
    final escalaMin = p['escala_min'] as int? ?? 1;
    final escalaMax = p['escala_max'] as int? ?? 5;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Número + enunciado
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.magenta.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: AppTextStyles.corpoMenor.copyWith(
                      color: AppColors.magenta,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texto + (obrigatoria ? ' *' : ''),
                  style: AppTextStyles.corpoNormal.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Resposta conforme o tipo
          if (tipo == 'texto_livre') _respostaTexto(id),
          if (tipo == 'multipla_escolha') _respostaMultipla(id, opcoes),
          if (tipo == 'escala') _respostaEscala(id, escalaMin, escalaMax),
          if (tipo == 'sim_nao') _respostaSimNao(id),
        ],
      ),
    );
  }

  // ── Texto livre ────────────────────────────────────────────────────
  Widget _respostaTexto(int id) {
    return TextField(
      maxLines: 3,
      maxLength: 500,
      style: AppTextStyles.corpoNormal,
      onChanged: (v) => _respostas[id] = v,
      decoration: InputDecoration(
        hintText: 'Digite sua resposta...',
        hintStyle: AppTextStyles.corpoCinza,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.magenta),
        ),
        contentPadding: const EdgeInsets.all(12),
      ),
    );
  }

  // ── Múltipla escolha ───────────────────────────────────────────────
  Widget _respostaMultipla(int id, List<String> opcoes) {
    return Column(
      children: opcoes.map((op) {
        final selecionado = _respostas[id] == op;
        return GestureDetector(
          onTap: () => setState(() => _respostas[id] = op),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selecionado
                  ? AppColors.magenta.withOpacity(0.08)
                  : const Color(0xFFF8F9FC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selecionado ? AppColors.magenta : Colors.grey[300]!,
                width: selecionado ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selecionado
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selecionado ? AppColors.magenta : AppColors.cinzaTexto,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(op, style: AppTextStyles.corpoNormal),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Escala ─────────────────────────────────────────────────────────
  Widget _respostaEscala(int id, int min, int max) {
    final atual = _respostas[id] as int?;
    return Column(
      children: [
        Row(
          children: List.generate(max - min + 1, (i) {
            final valor = min + i;
            final selecionado = atual == valor;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _respostas[id] = valor),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 44,
                  decoration: BoxDecoration(
                    color: selecionado
                        ? AppColors.magenta
                        : AppColors.magenta.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '$valor',
                      style: AppTextStyles.corpoNormal.copyWith(
                        color:
                            selecionado ? Colors.white : AppColors.cinzaTexto,
                        fontWeight: selecionado
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$min = Mín.', style: AppTextStyles.corpoMinimo),
            Text('$max = Máx.', style: AppTextStyles.corpoMinimo),
          ],
        ),
      ],
    );
  }

  // ── Sim / Não ──────────────────────────────────────────────────────
  Widget _respostaSimNao(int id) {
    final atual = _respostas[id] as bool?;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _respostas[id] = true),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: atual == true
                    ? Colors.green
                    : Colors.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: atual == true
                      ? Colors.green
                      : Colors.green.withOpacity(0.3),
                ),
              ),
              child: Center(
                child: Text(
                  '✓  Sim',
                  style: AppTextStyles.corpoNormal.copyWith(
                    color: atual == true ? Colors.white : Colors.green[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _respostas[id] = false),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: atual == false
                    ? Colors.red
                    : Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: atual == false
                      ? Colors.red
                      : Colors.red.withOpacity(0.3),
                ),
              ),
              child: Center(
                child: Text(
                  '✕  Não',
                  style: AppTextStyles.corpoNormal.copyWith(
                    color: atual == false ? Colors.white : Colors.red[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
