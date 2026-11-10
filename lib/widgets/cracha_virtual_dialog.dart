import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_theme.dart';
import '../services/documentos_cadastrais_service.dart';

/// Abre o crachá virtual do colaborador: mostra a frente e, ao tocar na
/// imagem, vira para o verso (e de novo para a frente).
Future<void> abrirCrachaVirtual(BuildContext context,
    {required int colaboradorId}) {
  return showDialog(
    context: context,
    builder: (_) => _CrachaVirtualDialog(colaboradorId: colaboradorId),
  );
}

class _CrachaVirtualDialog extends StatefulWidget {
  final int colaboradorId;
  const _CrachaVirtualDialog({required this.colaboradorId});

  @override
  State<_CrachaVirtualDialog> createState() => _CrachaVirtualDialogState();
}

class _CrachaVirtualDialogState extends State<_CrachaVirtualDialog> {
  bool _carregando = true;
  ({String? frente, String? verso})? _cracha;

  @override
  void initState() {
    super.initState();
    DocumentosCadastraisService.instance
        .buscarCracha(widget.colaboradorId)
        .then((c) {
      if (!mounted) return;
      setState(() {
        _cracha = c;
        _carregando = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _cracha;
    final temImagem = c != null &&
        ((c.frente ?? '').isNotEmpty || (c.verso ?? '').isNotEmpty);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Icon(Icons.badge_outlined, color: AppColors.laranja),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Crachá virtual',
                      style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ]),
              const SizedBox(height: 8),
              if (_carregando)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: AppColors.laranja),
                )
              else if (!temImagem)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(children: [
                    const Icon(Icons.hourglass_empty_rounded,
                        size: 40, color: AppColors.cinzaTexto),
                    const SizedBox(height: 12),
                    Text('Seu crachá virtual ainda não foi cadastrado.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: AppColors.cinzaTexto)),
                    const SizedBox(height: 4),
                    Text('O DP envia a imagem assim que estiver disponível.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            fontSize: 11.5, color: AppColors.cinzaTexto)),
                  ]),
                )
              else
                Flexible(
                  child: _CrachaGiratorio(frente: c.frente, verso: c.verso),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Imagem do crachá que vira (animação de giro) entre frente e verso.
class _CrachaGiratorio extends StatefulWidget {
  final String? frente;
  final String? verso;
  const _CrachaGiratorio({this.frente, this.verso});

  @override
  State<_CrachaGiratorio> createState() => _CrachaGiratorioState();
}

class _CrachaGiratorioState extends State<_CrachaGiratorio> {
  bool _verso = false;

  bool get _temFrente => (widget.frente ?? '').isNotEmpty;
  bool get _temVerso => (widget.verso ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Se só existe o verso, já abre nele.
    if (!_temFrente && _temVerso) _verso = true;
  }

  Widget _imagem(String? url, {required bool verso}) {
    return ClipRRect(
      key: ValueKey(verso),
      borderRadius: BorderRadius.circular(14),
      child: (url ?? '').isEmpty
          ? Container(
              height: 300,
              color: AppColors.cinzaClaro,
              alignment: Alignment.center,
              child: Text(
                  verso ? 'Verso não cadastrado' : 'Frente não cadastrada',
                  style: GoogleFonts.poppins(color: AppColors.cinzaTexto)),
            )
          : Image.network(
              url!,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progresso) => progresso == null
                  ? child
                  : const SizedBox(
                      height: 300,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.laranja)),
                    ),
              errorBuilder: (_, __, ___) => Container(
                height: 300,
                color: AppColors.cinzaClaro,
                alignment: Alignment.center,
                child: Text('Não foi possível carregar a imagem',
                    style: GoogleFonts.poppins(color: AppColors.cinzaTexto)),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final podeVirar = _temFrente && _temVerso;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: GestureDetector(
            onTap: podeVirar ? () => setState(() => _verso = !_verso) : null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut.flipped,
              transitionBuilder: (child, anim) {
                // Giro em torno do eixo vertical: a imagem que sai gira até
                // 90° e a que entra completa o giro a partir de 90°.
                final rotacao = Tween(begin: math.pi, end: 0.0).animate(anim);
                return AnimatedBuilder(
                  animation: rotacao,
                  child: child,
                  builder: (context, child) {
                    final saindo = child!.key != ValueKey(_verso);
                    var inclinacao = ((anim.value - 0.5).abs() - 0.5) * 0.003;
                    inclinacao *= saindo ? -1.0 : 1.0;
                    final valor =
                        saindo ? math.min(rotacao.value, math.pi / 2) : rotacao.value;
                    return Transform(
                      transform: Matrix4.rotationY(valor)
                        ..setEntry(3, 0, inclinacao),
                      alignment: Alignment.center,
                      child: child,
                    );
                  },
                );
              },
              layoutBuilder: (atual, anteriores) => Stack(
                alignment: Alignment.center,
                children: [...anteriores, if (atual != null) atual],
              ),
              child: _imagem(_verso ? widget.verso : widget.frente,
                  verso: _verso),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (podeVirar)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.touch_app_outlined,
                size: 15, color: AppColors.cinzaTexto),
            const SizedBox(width: 6),
            Text(
                _verso
                    ? 'Verso · toque para ver a frente'
                    : 'Frente · toque para ver o verso',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.cinzaTexto)),
          ])
        else
          Text(_verso ? 'Verso' : 'Frente',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.cinzaTexto)),
      ],
    );
  }
}
