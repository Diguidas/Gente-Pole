import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

class PesquisaRespostaScreen extends StatefulWidget {
  final int pesquisaId;
  final String titulo;
  final bool anonima;
  final bool pedirOptIn;

  const PesquisaRespostaScreen({
    super.key,
    required this.pesquisaId,
    required this.titulo,
    required this.anonima,
    this.pedirOptIn = false,
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

  // Guarda as respostas: pergunta_id → valor (String | int | bool | Set<String> | Map<String,String>)
  final Map<int, dynamic> _respostas = {};

  // ── Gate de opt-in ────────────────────────────────────────────────
  bool? _optInRespondeu;
  bool _enviandoRecusa = false;
  final _motivoRecusaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarPerguntas();
  }

  @override
  void dispose() {
    _motivoRecusaCtrl.dispose();
    super.dispose();
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

  Future<void> _recusar() async {
    final colaboradorId = _api.colaboradorAtual?.id;
    if (colaboradorId == null) return;
    setState(() => _enviandoRecusa = true);
    final ok = await _api.recusarPesquisaColab(
      pesquisaId: widget.pesquisaId,
      colaboradorId: colaboradorId,
      motivo: _motivoRecusaCtrl.text,
    );
    if (!mounted) return;
    setState(() => _enviandoRecusa = false);
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tudo bem, obrigado pelo retorno!',
            style: AppTextStyles.corpoNormal.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.magenta,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível registrar. Tente novamente.',
            style: AppTextStyles.corpoNormal.copyWith(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool _validarObrigatorias() {
    for (final p in _perguntas) {
      final obrigatoria = p['obrigatoria'] as bool? ?? true;
      if (!obrigatoria) continue;
      final id = p['id'] as int;
      final tipo = p['tipo'] as String? ?? 'texto_livre';
      final valor = _respostas[id];

      if (tipo == 'escala_matriz') {
        final linhas = (p['escala_linhas'] as List?)?.cast<String>() ?? [];
        final mapa = (valor as Map?) ?? {};
        if (mapa.length < linhas.length) return false;
        continue;
      }

      if (valor == null ||
          (valor is String && valor.trim().isEmpty) ||
          (valor is Iterable && valor.isEmpty)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _enviar() async {
    // Valida obrigatórias
    if (!_validarObrigatorias()) {
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
                        : (widget.pedirOptIn && _optInRespondeu != true)
                        ? _buildOptInGate()
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

  // ── Gate de opt-in (aceitar/recusar responder) ────────────────────
  Widget _buildOptInGate() {
    if (_optInRespondeu == false) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tudo bem! Pode nos contar o motivo?',
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSecao,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _motivoRecusaCtrl,
              maxLines: 3,
              style: AppTextStyles.corpoNormal,
              decoration: InputDecoration(
                hintText: 'Por que você não quer responder agora?',
                hintStyle: AppTextStyles.corpoCinza,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _enviandoRecusa ? null : _recusar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.magenta,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: _enviandoRecusa
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text('Enviar e encerrar',
                        style: AppTextStyles.botaoPrimario),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Quer responder essa pesquisa?',
            textAlign: TextAlign.center,
            style: AppTextStyles.labelSecao,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _optInRespondeu = true),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.green),
                  ),
                  child: Text(
                    'Sim',
                    style: AppTextStyles.corpoNormal.copyWith(
                      color: Colors.green[700],
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _optInRespondeu = false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: Text(
                    'Não',
                    style: AppTextStyles.corpoNormal.copyWith(
                      color: Colors.red[700],
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
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
    final escalaLinhas = (p['escala_linhas'] as List?)?.cast<String>() ?? [];
    final escalaColunas = (p['escala_colunas'] as List?)?.cast<String>() ?? [];

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
          if (tipo == 'texto' || tipo == 'texto_livre') _respostaTexto(id),
          if (tipo == 'multipla_escolha') _respostaMultipla(id, opcoes),
          if (tipo == 'checkbox') _respostaCheckbox(id, opcoes),
          if (tipo == 'escala') _respostaEscala(id, escalaMin, escalaMax),
          if (tipo == 'escala_matriz')
            _respostaEscalaMatriz(
              id,
              escalaMin,
              escalaMax,
              escalaLinhas,
              escalaColunas,
            ),
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

  // ── Checkbox (múltipla escolha real) ──────────────────────────────
  Widget _respostaCheckbox(int id, List<String> opcoes) {
    final selecionadas = (_respostas[id] as Set<String>?) ?? <String>{};
    _respostas[id] ??= selecionadas;
    return Column(
      children: opcoes.map((op) {
        final selecionado = selecionadas.contains(op);
        return GestureDetector(
          onTap: () => setState(() {
            if (selecionado) {
              selecionadas.remove(op);
            } else {
              selecionadas.add(op);
            }
            _respostas[id] = selecionadas;
          }),
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
                Checkbox(
                  value: selecionado,
                  activeColor: AppColors.magenta,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      selecionadas.add(op);
                    } else {
                      selecionadas.remove(op);
                    }
                    _respostas[id] = selecionadas;
                  }),
                ),
                const SizedBox(width: 2),
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

  // ── Escala matriz (linhas × colunas) ──────────────────────────────
  Widget _respostaEscalaMatriz(
    int id,
    int min,
    int max,
    List<String> linhas,
    List<String> colunas,
  ) {
    final niveis = List.generate(max - min + 1, (i) => min + i);
    final valores = (_respostas[id] as Map<String, String>?) ?? <String, String>{};
    _respostas[id] ??= valores;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: linhas.map((linha) {
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                linha,
                style: AppTextStyles.corpoNormal
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Row(
                children: List.generate(niveis.length, (i) {
                  final n = niveis[i];
                  final sel = valores[linha] == '$n';
                  final legenda = i < colunas.length ? colunas[i] : '';
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => valores[linha] = '$n'),
                      child: Column(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: sel ? AppColors.magenta : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: sel
                                    ? AppColors.magenta
                                    : Colors.grey[300]!,
                              ),
                            ),
                            child: Text(
                              '$n',
                              style: AppTextStyles.corpoMenor.copyWith(
                                fontWeight: FontWeight.w700,
                                color: sel ? Colors.white : AppColors.dark,
                              ),
                            ),
                          ),
                          if (legenda.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              legenda,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.corpoMinimo
                                  .copyWith(color: AppColors.cinzaTexto),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
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
