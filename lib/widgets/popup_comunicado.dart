import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';

/// Pop-up de comunicado do endomkt, mostrado ao abrir o app durante o
/// período definido, até o colaborador marcar "não mostrar novamente".
/// Vários ativos aparecem um por vez, em sequência.
class PopupComunicado {
  PopupComunicado._();

  static Future<void> verificar(BuildContext context) async {
    final api = ApiService();
    List<Map<String, dynamic>> pendentes;
    try {
      pendentes = await api.buscarPopupsComunicado();
    } catch (_) {
      return; // pop-up é opcional: falha não atrapalha a abertura do app
    }
    for (final c in pendentes) {
      if (!context.mounted) return;
      final naoMostrar = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PopupComunicadoDialog(comunicado: c),
      );
      if (naoMostrar == true) {
        try {
          await api.dispensarPopupComunicado((c['id'] as num).toInt());
        } catch (_) {}
      }
    }
  }
}

class _PopupComunicadoDialog extends StatefulWidget {
  final Map<String, dynamic> comunicado;
  const _PopupComunicadoDialog({required this.comunicado});

  @override
  State<_PopupComunicadoDialog> createState() => _PopupComunicadoDialogState();
}

class _PopupComunicadoDialogState extends State<_PopupComunicadoDialog> {
  bool _naoMostrar = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.comunicado;
    final titulo = (c['titulo'] as String?)?.trim() ?? '';
    final descricao = (c['descricao'] as String?)?.trim() ?? '';
    final foto = (c['foto_url'] as String?) ?? (c['imagem_url'] as String?) ?? '';
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (foto.isNotEmpty)
                      Image.network(
                        foto,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        loadingBuilder: (_, child, p) => p == null
                            ? child
                            : const SizedBox(
                                height: 180,
                                child: Center(
                                    child: CircularProgressIndicator(
                                        color: AppColors.magenta)),
                              ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (titulo.isNotEmpty)
                            Text(titulo, style: AppTextStyles.tituloMedio),
                          if (descricao.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(descricao, style: AppTextStyles.corpoNormal),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 18, 14),
              child: Row(children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _naoMostrar = !_naoMostrar),
                    child: Row(children: [
                      Checkbox(
                        value: _naoMostrar,
                        activeColor: AppColors.magenta,
                        onChanged: (v) =>
                            setState(() => _naoMostrar = v ?? false),
                      ),
                      Flexible(
                        child: Text('Não mostrar novamente',
                            style: AppTextStyles.corpoMenor),
                      ),
                    ]),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _naoMostrar),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.magenta,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Fechar'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
