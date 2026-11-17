import 'package:flutter/material.dart';
import '../services/lojinha_fila_service.dart';

/// Cartão flutuante: mostra que o pedido da Lojinha está sendo integrado ao SAP,
/// o resultado quando termina, e o aviso se algo falhou (o DP reenvia).
class LojinhaFilaCard extends StatelessWidget {
  const LojinhaFilaCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = LojinhaFilaService.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (!s.visivel) return const SizedBox.shrink();
        final erro = !s.ativo && s.temErro && !s.mostrarConfirmado;
        final ok = !s.ativo && s.mostrarConfirmado;
        final cor = erro
            ? const Color(0xFFEA580C)
            : ok
                ? const Color(0xFF16A34A)
                : const Color(0xFF7C3AED);
        final titulo = erro
            ? 'Não foi possível integrar o pedido'
            : ok
                ? 'Pedido confirmado'
                : 'Pedido sendo integrado';
        final texto = erro
            ? 'O DP já foi avisado e vai reenviar. Você não precisa pedir de novo.'
            : ok
                ? ((s.numerosConfirmados ?? '').isNotEmpty
                    ? 'Pedido nº ${s.numerosConfirmados} confirmado no SAP.'
                    : 'Seu pedido foi confirmado no SAP.')
                : 'Estamos enviando seu pedido ao SAP. Pode continuar usando o app.';
        return Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cor.withOpacity(0.35)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 4)),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: erro
                      ? Icon(Icons.error_outline_rounded, color: cor, size: 22)
                      : ok
                          ? Icon(Icons.check_circle_rounded, color: cor, size: 22)
                          : SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: cor)),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(titulo,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(texto,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF64748B), height: 1.35)),
                    ],
                  ),
                ),
                if (erro)
                  InkWell(
                    onTap: s.dispensarErro,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
