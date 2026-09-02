import 'package:flutter/foundation.dart';

/// Avisa telas que exibem o saldo de Polecoin (chip do feed, tela de
/// gamificação) para recarregar sempre que uma ação pontuável acontece em
/// qualquer lugar do app — sem isso, cada tela só buscava o saldo uma vez no
/// initState e ficava com o valor desatualizado até o usuário sair e voltar
/// (ou o app reiniciar).
class PontosBus {
  PontosBus._();

  /// Incrementado a cada ação que pode ter gerado pontos. Quem exibe saldo
  /// escuta esse notifier e recarrega do banco quando ele muda.
  static final ValueNotifier<int> versao = ValueNotifier(0);

  static void notificarGanho() => versao.value++;
}
