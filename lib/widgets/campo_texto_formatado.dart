import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';
import 'markdown_texto.dart';

/// Campo de texto com toolbar de formatação markdown simples (negrito,
/// itálico, marcadores, indentar) e uma pré-visualização abaixo — mesmo
/// comportamento usado em "Dar Feedback", extraído aqui pra reaproveitar em
/// outras telas de texto livre (ex: Elogiar).
class CampoTextoFormatado extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final int maxLines;

  /// Chamado a cada mudança de texto — necessário porque o `setState` interno
  /// só reconstrói este widget (pra atualizar sua própria toolbar/preview),
  /// nunca a tela que o contém. Sem isso, uma tela pai que decide habilitar
  /// um botão com base no texto digitado aqui só percebe a mudança quando
  /// algum outro `setState` seu é disparado por acaso (ex: marcar um switch).
  final VoidCallback? onChanged;

  const CampoTextoFormatado({
    super.key,
    required this.controller,
    this.hintText = 'Escreva aqui...',
    this.maxLines = 5,
    this.onChanged,
  });

  @override
  State<CampoTextoFormatado> createState() => _CampoTextoFormatadoState();
}

class _CampoTextoFormatadoState extends State<CampoTextoFormatado> {
  bool _mostrarPreview = false;

  void _envolverSelecao(String marcador) {
    final ctrl = widget.controller;
    final texto = ctrl.text;
    final selecao = ctrl.selection;
    if (!selecao.isValid || selecao.isCollapsed) {
      final novoTexto = texto.replaceRange(selecao.start, selecao.start, '$marcador$marcador');
      ctrl.value = ctrl.value.copyWith(
        text: novoTexto,
        selection: TextSelection.collapsed(offset: selecao.start + marcador.length),
      );
      setState(() {});
      widget.onChanged?.call();
      return;
    }
    final selecionado = texto.substring(selecao.start, selecao.end);
    final novoTexto = texto.replaceRange(selecao.start, selecao.end, '$marcador$selecionado$marcador');
    ctrl.value = ctrl.value.copyWith(
      text: novoTexto,
      selection: TextSelection.collapsed(offset: selecao.end + marcador.length * 2),
    );
    setState(() {});
    widget.onChanged?.call();
  }

  void _aplicarPrefixoNasLinhas(String Function(String linha) transformar) {
    final ctrl = widget.controller;
    final texto = ctrl.text;
    final selecao = ctrl.selection;
    final inicio = selecao.isValid ? selecao.start : texto.length;
    final fim = selecao.isValid ? selecao.end : texto.length;
    var inicioLinha = texto.lastIndexOf('\n', inicio - 1) + 1;
    if (inicioLinha < 0) inicioLinha = 0;
    var fimLinha = texto.indexOf('\n', fim);
    if (fimLinha == -1) fimLinha = texto.length;

    final trecho = texto.substring(inicioLinha, fimLinha);
    final linhasTransformadas = trecho.split('\n').map(transformar).join('\n');
    final novoTexto = texto.replaceRange(inicioLinha, fimLinha, linhasTransformadas);
    ctrl.value = ctrl.value.copyWith(
      text: novoTexto,
      selection: TextSelection.collapsed(offset: inicioLinha + linhasTransformadas.length),
    );
    setState(() {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _BotaoFormatacao(
                icone: Icons.format_bold_rounded, tooltip: 'Negrito', onTap: () => _envolverSelecao('**')),
            _BotaoFormatacao(
                icone: Icons.format_italic_rounded, tooltip: 'Itálico', onTap: () => _envolverSelecao('*')),
            _BotaoFormatacao(
              icone: Icons.format_list_bulleted_rounded,
              tooltip: 'Marcadores',
              onTap: () => _aplicarPrefixoNasLinhas(
                  (linha) => linha.trimLeft().startsWith('- ') ? linha : '- $linha'),
            ),
            _BotaoFormatacao(
              icone: Icons.format_indent_increase_rounded,
              tooltip: 'Indentar',
              onTap: () => _aplicarPrefixoNasLinhas((linha) => '  $linha'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: widget.controller,
          maxLines: widget.maxLines,
          onChanged: (_) {
            setState(() {});
            widget.onChanged?.call();
          },
          style: GoogleFonts.poppins(fontSize: 13),
          decoration: InputDecoration(
            hintText: widget.hintText,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          ),
        ),
        if (widget.controller.text.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          InkWell(
            onTap: () => setState(() => _mostrarPreview = !_mostrarPreview),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _mostrarPreview
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 14,
                    color: AppColors.cinzaTexto,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _mostrarPreview ? 'Ocultar pré-visualização' : 'Ver como vai ficar',
                    style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.cinzaTexto),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_mostrarPreview && widget.controller.text.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: MarkdownTexto(widget.controller.text,
                style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.dark)),
          ),
        ],
      ],
    );
  }
}

class _BotaoFormatacao extends StatelessWidget {
  final IconData icone;
  final String tooltip;
  final VoidCallback onTap;

  const _BotaoFormatacao({required this.icone, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(icone, size: 16, color: AppColors.dark),
          ),
        ),
      ),
    );
  }
}
