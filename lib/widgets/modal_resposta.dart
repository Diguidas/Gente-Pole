import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Bottom sheet de resposta curta (mesmo padrão visual do modal de resposta
/// aos parabéns). [onEnviar] devolve true se salvou; só então o sheet fecha.
Future<void> mostrarModalResposta(
  BuildContext context, {
  required String titulo,
  required String subtitulo,
  required String hint,
  required Future<bool> Function(String resposta) onEnviar,
  Color cor = AppColors.magenta,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ModalResposta(
      titulo: titulo,
      subtitulo: subtitulo,
      hint: hint,
      cor: cor,
      onEnviar: onEnviar,
    ),
  );
}

class _ModalResposta extends StatefulWidget {
  final String titulo;
  final String subtitulo;
  final String hint;
  final Color cor;
  final Future<bool> Function(String resposta) onEnviar;

  const _ModalResposta({
    required this.titulo,
    required this.subtitulo,
    required this.hint,
    required this.cor,
    required this.onEnviar,
  });

  @override
  State<_ModalResposta> createState() => _ModalRespostaState();
}

class _ModalRespostaState extends State<_ModalResposta> {
  final _controller = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final msg = _controller.text.trim();
    if (msg.isEmpty) return;
    setState(() => _enviando = true);
    final ok = await widget.onEnviar(msg);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cinzaTextoOp30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(widget.titulo,
                style: AppTextStyles.tituloMedio.copyWith(fontSize: 17)),
            const SizedBox(height: 4),
            Text(widget.subtitulo, style: AppTextStyles.corpoMenor),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 3,
              maxLength: 280,
              style: AppTextStyles.corpoNormal,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: AppTextStyles.corpoCinza,
                filled: true,
                fillColor: AppColors.cinzaClaro,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _enviando ? null : _enviar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.cor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                child: _enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text('Enviar resposta', style: AppTextStyles.botaoPrimario),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
