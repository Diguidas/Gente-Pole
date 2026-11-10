import 'package:flutter/material.dart';

/// Nome de exibição curto: o apelido ("nome que gosta de ser chamado") quando
/// existe; senão o primeiro nome. Capitaliza porque os nomes vêm em maiúsculas.
String nomeCurto(String? nome, [String? apelido]) {
  final base = (apelido != null && apelido.trim().isNotEmpty)
      ? apelido.trim()
      : (nome ?? '').trim().split(' ').first;
  if (base.isEmpty) return base;
  if (base != base.toUpperCase()) return base; // já tem caixa mista (apelido digitado)
  return base[0] + base.substring(1).toLowerCase();
}

/// Abre a foto de perfil em tamanho grande (como no feed). Sem foto, não faz nada.
void abrirFotoPerfil(BuildContext context, String? url, [String? nome]) {
  if (url == null || url.isEmpty) return;
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(alignment: Alignment.topRight, children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
              child: InteractiveViewer(
                child: Image.network(url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(
                        width: 200,
                        height: 200,
                        child: Icon(Icons.broken_image_outlined, color: Colors.white))),
              ),
            ),
          ),
          if (nome != null && nome.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(nome,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ]),
        IconButton(
          onPressed: () => Navigator.pop(ctx),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          style: IconButton.styleFrom(backgroundColor: Colors.black54),
        ),
      ]),
    ),
  );
}

/// Envolve um avatar: tocar abre a foto grande (se a pessoa tiver foto).
class FotoClicavel extends StatelessWidget {
  final String? url;
  final String? nome;
  final Widget child;
  const FotoClicavel({super.key, required this.url, this.nome, required this.child});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return child;
    return GestureDetector(onTap: () => abrirFotoPerfil(context, url, nome), child: child);
  }
}
