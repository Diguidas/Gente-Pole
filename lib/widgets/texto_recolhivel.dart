import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Limita a altura de um texto longo (legenda/comunicado) no card e mostra
/// "Ver mais..." / "Ver menos". Textos curtos passam direto, sem alteração.
///
/// [texto] é só usado para decidir se precisa recolher (tamanho/linhas); quem
/// desenha é o [child] já montado (com menções, hashtags etc.).
class TextoRecolhivel extends StatefulWidget {
  final String texto;
  final Widget child;
  final Color corLink;
  final double alturaMax;
  final int limiteChars;
  final int limiteQuebras;

  const TextoRecolhivel({
    super.key,
    required this.texto,
    required this.child,
    required this.corLink,
    this.alturaMax = 92,
    this.limiteChars = 180,
    this.limiteQuebras = 4,
  });

  @override
  State<TextoRecolhivel> createState() => _TextoRecolhivelState();
}

class _TextoRecolhivelState extends State<TextoRecolhivel> {
  bool _aberto = false;

  bool get _longo =>
      widget.texto.length > widget.limiteChars ||
      '\n'.allMatches(widget.texto).length >= widget.limiteQuebras;

  @override
  Widget build(BuildContext context) {
    if (!_longo) return widget.child;

    final link = TextButton(
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.centerLeft,
      ),
      onPressed: () => setState(() => _aberto = !_aberto),
      child: Text(_aberto ? 'Ver menos' : 'Ver mais...',
          style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w600, color: widget.corLink)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_aberto)
          widget.child
        else
          // O texto é montado inteiro e só o que passa da altura é cortado,
          // com um esmaecido no fim para indicar que continua.
          SizedBox(
            height: widget.alturaMax,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.7, 1],
              ).createShader(r),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: widget.child,
                ),
              ),
            ),
          ),
        link,
      ],
    );
  }
}
