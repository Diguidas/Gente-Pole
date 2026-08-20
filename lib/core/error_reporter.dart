import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Registrada no `MaterialApp` (scaffoldMessengerKey) para permitir mostrar
/// avisos de erro de qualquer lugar, mesmo sem BuildContext (ex.: dentro do ApiService).
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Configura a captura de erros não tratados (fora de try/catch) para que
/// também apareçam na tela em vez de só derrubar a UI ou sumir no console.
/// Chamar uma única vez, dentro do runZonedGuarded que envolve o runApp.
void configurarCapturaGlobalDeErros() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (_ehRuidoBenignoDeFoco(details)) return;
    ErrorReporter.report(
      details.exception,
      details.stack,
      contexto: 'Erro de interface',
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorReporter.report(error, stack, contexto: 'Erro não tratado');
    return true;
  };
}

/// Corrida interna e inofensiva do Flutter Web: ao a aba ganhar foco, o
/// framework tenta calcular o próximo elemento focável (`focus_traversal`)
/// antes do primeiro layout terminar, e dispara `hasSize`. Não é bug da
/// aplicação — só evita mostrar ruído de framework como se fosse erro real.
///
/// Em build de produção (minificado) os nomes de símbolo na stack trace são
/// ofuscados, então não dá pra confiar em achar 'focus_traversal' nela — por
/// isso o filtro é só pela mensagem, que não é afetada pela minificação.
bool _ehRuidoBenignoDeFoco(FlutterErrorDetails details) {
  final mensagem = details.exception.toString();
  return mensagem.contains('RenderBox was not laid out');
}

/// Centraliza a exibição de erros de chamadas ao Supabase (e outros) na tela,
/// para que o usuário possa copiar os detalhes e enviar para o TI.
class ErrorReporter {
  ErrorReporter._();

  static String _mensagemAmigavel(Object error) {
    if (error is PostgrestException) {
      return 'Erro no banco de dados${error.code != null ? ' (${error.code})' : ''}: ${error.message}';
    }
    if (error is AuthException) {
      return 'Erro de autenticação: ${error.message}';
    }
    if (error is FunctionException) {
      return 'Erro numa função do servidor (status ${error.status}).';
    }
    if (error is StorageException) {
      return 'Erro no armazenamento de arquivos: ${error.message}';
    }
    return 'Erro inesperado. Tente novamente.';
  }

  static bool _exibindo = false;

  /// Mostra um SnackBar de erro com botão para copiar os detalhes técnicos.
  /// [contexto] é uma descrição curta de qual ação falhou (ex.: "Enviar parabéns").
  ///
  /// Sempre agenda a exibição para depois do frame atual (`addPostFrameCallback`)
  /// e ignora chamadas reentrantes enquanto já há um snackbar sendo exibido —
  /// sem isso, um erro que acontece durante o build tenta abrir o SnackBar
  /// durante o build (proibido pelo Flutter), o que gera um novo erro, que
  /// chama `report` de novo, entrando num loop infinito que trava a tela e
  /// enche o console.
  static void report(
    Object error,
    StackTrace? stackTrace, {
    String? contexto,
  }) {
    debugPrint('[ErrorReporter] ${contexto ?? "erro"}: $error\n$stackTrace');

    if (_exibindo) return;
    _exibindo = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _exibindo = false;
      final messenger = scaffoldMessengerKey.currentState;
      if (messenger == null) return;

      final mensagemUsuario = _mensagemAmigavel(error);
      final detalhesTecnicos = [
        if (contexto != null) 'Ação: $contexto',
        'Erro: $error',
        if (stackTrace != null) 'Stack:\n$stackTrace',
      ].join('\n');

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 8),
          content: Text(
            contexto != null ? '$contexto: $mensagemUsuario' : mensagemUsuario,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          action: SnackBarAction(
            label: 'COPIAR',
            textColor: Colors.white,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: detalhesTecnicos));
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Detalhes do erro copiados. Envie para o TI.'),
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
        ),
      );
    });
  }
}
