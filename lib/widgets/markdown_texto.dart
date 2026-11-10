import 'package:flutter/material.dart';

/// Renderiza um texto com marcação markdown simples (o suficiente pro editor
/// de feedback): **negrito**, *itálico*, linhas começando com "- " como
/// marcador de lista, e espaços à esquerda preservados como indentação.
/// Não é um parser markdown completo — só cobre o que o toolbar em
/// dar_feedback_screen.dart insere.
class MarkdownTexto extends StatelessWidget {
  final String texto;
  final TextStyle? style;

  const MarkdownTexto(this.texto, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final linhas = texto.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: linhas.map((linha) {
        final ehMarcador = linha.trimLeft().startsWith('- ');
        final semMarcador = ehMarcador
            ? linha.replaceFirst(RegExp(r'^\s*-\s'), '')
            : linha;
        final texto = ehMarcador ? semMarcador : linha;
        final spans = _parseInline(texto, baseStyle);
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: ehMarcador
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: baseStyle),
                    Expanded(child: RichText(text: TextSpan(children: spans))),
                  ],
                )
              : RichText(text: TextSpan(children: spans)),
        );
      }).toList(),
    );
  }

  List<InlineSpan> _parseInline(String texto, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');
    var ultimo = 0;
    for (final match in regex.allMatches(texto)) {
      if (match.start > ultimo) {
        spans.add(TextSpan(text: texto.substring(ultimo, match.start), style: baseStyle));
      }
      if (match.group(1) != null) {
        spans.add(TextSpan(
            text: match.group(1),
            style: baseStyle.copyWith(fontWeight: FontWeight.w700)));
      } else if (match.group(2) != null) {
        spans.add(TextSpan(
            text: match.group(2), style: baseStyle.copyWith(fontStyle: FontStyle.italic)));
      }
      ultimo = match.end;
    }
    if (ultimo < texto.length) {
      spans.add(TextSpan(text: texto.substring(ultimo), style: baseStyle));
    }
    if (spans.isEmpty) spans.add(TextSpan(text: texto, style: baseStyle));
    return spans;
  }
}
