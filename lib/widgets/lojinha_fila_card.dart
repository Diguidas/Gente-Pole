import 'package:flutter/material.dart';
import '../core/app_navigator.dart';
import '../screens/lojinha/lojinha_home_screen.dart';
import '../services/lojinha_fila_service.dart';

/// Cartão flutuante: mostra que o pedido da Lojinha está sendo integrado ao SAP,
/// o resultado quando termina, e o aviso se algo falhou (o DP reenvia).
class LojinhaFilaCard extends StatelessWidget {
  const LojinhaFilaCard({super.key});

  /// Pedido(s) que o DP reenviou e foram integrados: fica no cartão, com um
  /// check por pedido, até a pessoa marcar "Entendi" (aí abre Meus Pedidos).
  Widget _avisoReenvio(LojinhaFilaService s) {
    const verde = Color(0xFF16A34A);
    final pedidos = s.paraEntender;
    final plural = pedidos.length > 1;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: verde.withOpacity(0.35)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(plural ? 'Pedidos integrados' : 'Pedido integrado',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
                'Pedimos desculpas pelo erro. O DP reenviou e '
                '${plural ? 'seus pedidos foram integrados' : 'seu pedido foi integrado'} '
                'ao SAP:',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF64748B), height: 1.35)),
            const SizedBox(height: 6),
            for (final p in pedidos)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: verde, size: 18),
                  const SizedBox(width: 6),
                  Text(
                      ((p['numero_pedido'] ?? '').toString().isNotEmpty)
                          ? 'Pedido nº ${p['numero_pedido'].toString().replaceFirst(RegExp(r'^0+'), '')}'
                          : 'Pedido integrado',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: verde,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8)),
                onPressed: () {
                  s.entendi();
                  AppNavigator.navigatorKey.currentState?.push(
                    MaterialPageRoute(
                        builder: (_) =>
                            const LojinhaHomeScreen(abrirPedidos: true)),
                  );
                },
                child: const Text('Entendi'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = LojinhaFilaService.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (!s.visivel) return const SizedBox.shrink();
        if (s.temAvisoReenvio && !s.ativoVisivel) return _avisoReenvio(s);
        final erro = !s.ativoVisivel && s.temErro && !s.mostrarConfirmado;
        final ok = !s.ativoVisivel && s.mostrarConfirmado;
        final comCortes = ok && s.cortesConfirmados != null;
        final cor = erro
            ? const Color(0xFFEA580C)
            : ok
                ? (comCortes ? const Color(0xFFD97706) : const Color(0xFF16A34A))
                : const Color(0xFF7C3AED);
        final parcial = erro ? s.numerosParciais : null;
        final titulo = erro
            ? (parcial != null ? 'Parte do pedido foi realizada' : s.tituloFalha)
            : ok
                ? (comCortes ? 'Pedido realizado com ajustes' : 'Pedido realizado com sucesso')
                : 'Pedido sendo integrado';
        final texto = erro
            ? (parcial != null
                ? 'O pedido nº ${parcial.replaceAll(' / ', ' e ')} foi realizado com sucesso, mas parte do seu pedido não foi realizada. O DP já foi avisado: entre em contato com o DP. Novos pedidos ficam bloqueados até o DP resolver.'
                : s.mensagemFalha)
            : ok
                ? ((s.numerosConfirmados ?? '').isNotEmpty
                    ? ((s.numerosConfirmados!.contains(' / ')
                            ? 'Pedidos nº ${s.numerosConfirmados!.replaceAll(' / ', ' e ')} confirmados no SAP.'
                            : 'Pedido nº ${s.numerosConfirmados} confirmado no SAP.')) +
                        ' Toque para ver em Meus Pedidos.'
                    : 'Seu pedido foi confirmado no SAP. Toque para ver em Meus Pedidos.') +
                    (comCortes ? '\nFaltou estoque: ${s.cortesConfirmados}.' : '')
                : 'Estamos enviando seu pedido ao SAP. Pode continuar usando o app.';
        void abrirPedidos() {
          s.dispensarConfirmado();
          AppNavigator.navigatorKey.currentState?.push(
            MaterialPageRoute(
                builder: (_) => const LojinhaHomeScreen(abrirPedidos: true)),
          );
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
           borderRadius: BorderRadius.circular(16),
           onTap: ok ? abrirPedidos : null,
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
                if (erro || ok)
                  InkWell(
                    onTap: erro ? s.dispensarErro : s.dispensarConfirmado,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                    ),
                  ),
              ],
            ),
           ),
          ),
        );
      },
    );
  }
}
