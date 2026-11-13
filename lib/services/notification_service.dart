import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_navigator.dart';
import '../core/error_reporter.dart';
import '../screens/ti/chamados_ti_screen.dart';
import '../screens/pesquisa/pesquisa_list_screen.dart';
import '../screens/gestor/vagas_gestor_screen.dart';
import '../screens/massoterapia/massoterapia_screen.dart';
import '../screens/nutricionista/nutricionista_screen.dart';
import '../screens/fisioterapia/fisioterapia_screen.dart';
import '../screens/consulta_medica/consulta_medica_screen.dart';
import '../screens/gestor/candidatura_chat_sheet.dart';
import '../screens/performance/performance_colab_screen.dart';
import '../screens/performance/performance_gestor_screen.dart';
import 'api_service.dart';

// Handler de background — deve ser função top-level (fora de qualquer classe)
@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  // Firebase já inicializado no main.dart; nada a fazer aqui além de receber.
}

class NotificationService {
  NotificationService._();

  static final _fcm = FirebaseMessaging.instance;
  static final _local = FlutterLocalNotificationsPlugin();

  static const _channelId = 'gentepole_default';
  static const _channelName = 'Gente Pole';

  // Diagnóstico temporário (iOS): mostra na tela até onde o init chegou.
  static void _mostrarTrace(List<String> trace, String titulo) {
    // Faixa na tela desligada (era só para o diagnóstico). Para reativar,
    // troque este return pelo bloco abaixo.
    debugPrint('$titulo\n${trace.join('\n')}');
    return;
    // ignore: dead_code
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    final texto = '$titulo\n${trace.join('\n')}';
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      backgroundColor: Colors.blueGrey.shade800,
      duration: const Duration(seconds: 40),
      content: Text(texto),
      action: SnackBarAction(
        label: 'COPIAR',
        textColor: Colors.white,
        onPressed: () => Clipboard.setData(ClipboardData(text: texto)),
      ),
    ));
  }

  static Future<void> init() async {
    final trace = <String>[];
    var terminou = false;
    trace.add('0 init chamado');
    _mostrarTrace(trace, 'Notificações iOS: init chamado');
    if (Platform.isIOS) {
      Future.delayed(const Duration(seconds: 25), () {
        if (!terminou) _mostrarTrace(trace, 'Notificações iOS: TRAVOU em');
      });
    }
    try {
      await _initInterno(trace);
    } catch (e) {
      trace.add('ERRO: $e');
    }
    terminou = true;
    _mostrarTrace(trace, 'Notificações iOS (diagnóstico)');
  }

  static Future<void> _initInterno(List<String> trace) async {
    trace.add('1 iniciou');
    // Registra handler de background
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

    // Pede permissão ao usuário
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    trace.add('2 permissão: ${settings.authorizationStatus.name}');
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      // Usuário negou: não mostra erro, o app só fica sem push.
      return;
    }

    await _salvarToken(settings, trace);

    // Cria canal Android (obrigatório Android 8+)
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        importance: Importance.high,
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    // Inicializa flutter_local_notifications
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) => _navigate(_decodePayload(r.payload)),
    ).timeout(const Duration(seconds: 10), onTimeout: () => null);

    trace.add('3 notificação local ok');
    // Notificação em foreground → exibe local
    FirebaseMessaging.onMessage.listen(_showLocal);

    // Toque em notificação com app em background (não fechado)
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _navigate(m.data));

    // Toque com app fechado
    final initial = await _fcm
        .getInitialMessage()
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (initial != null) _navigate(initial.data);
    trace.add('4 mensagem inicial ok');

  }

  /// Pega o token FCM e grava no banco. Roda logo depois da permissão, antes
  /// dos passos que podem demorar, para o token ser salvo mesmo se eles travarem.
  static Future<void> _salvarToken(
      NotificationSettings settings, List<String> trace) async {
    // No iOS o token FCM só existe depois que a Apple entrega o token APNs
    // (pode levar alguns segundos após a permissão). Espera até ~15s.
    if (Platform.isIOS) {
      String? apns;
      for (var i = 0; i < 15 && apns == null; i++) {
        apns = await _fcm.getAPNSToken();
        if (apns == null) await Future.delayed(const Duration(seconds: 1));
      }
      trace.add('5 token APNs: ${apns == null ? "NULO" : "ok"}');
      if (apns == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          trace.add('5b iOS nativo: '
              '${prefs.getString('apns_status') ?? "nenhum retorno do iOS"}');
        } catch (e) {
          trace.add('5b iOS nativo: erro ao ler ($e)');
        }
      }
    }
    try {
      final token =
          await _fcm.getToken().timeout(const Duration(seconds: 20));
      trace.add('6 token FCM: ${token == null ? "NULO" : "${token.substring(0, 8)}..."}');
      if (token != null) {
        trace.add('7 gravou no banco: ${await ApiService().salvarFcmToken(token)}');
      }
    } catch (e, s) {
      trace.add('6 ERRO token: $e');
      // onTokenRefresh abaixo salva quando o token ficar disponível.
      debugPrint('Notificações: falha ao obter token FCM: $e\n$s');
    }
    _fcm.onTokenRefresh.listen(ApiService().salvarFcmToken);
  }

  static Future<void> _showLocal(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    await _local.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      // Notificação em foreground: guarda todo o 'data' (não só a rota)
      // como JSON no payload, senão o toque nela (pela bandeja) perde o
      // workItemId na hora de abrir o app.
      payload: jsonEncode(message.data),
    );
  }

  static Map<String, dynamic>? _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // Mapeia a rota da notificação para uma aba do app
  // 0 = Feed | 1 = Aniversariantes | 2 = Serviços | 3 = Perfil
  static void _navigate(Map<String, dynamic>? data) {
    final route = data?['route'] as String?;
    switch (route) {
      case 'aniversario':
      case 'parabens':
        AppNavigator.goToTab(1);
      case 'gestor_exames':
      case 'gestor_feedback':
      case 'gestor_equipe':
        AppNavigator.goToTab(2);
      case 'perfil':
        AppNavigator.goToTab(3);
      case 'chamado_ti_novo':
      case 'chamado_ti_comentario':
      case 'chamado_ti_comentario_resposta':
      case 'chamado_ti_atualizado':
        AppNavigator.goToTab(2);
        AppNavigator.navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ChamadosTiScreen(workItemIdParaAbrir: _itemId(data)),
          ),
        );
      case 'consulta_medica':
        AppNavigator.goToTab(2);
        AppNavigator.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const ConsultaMedicaScreen()),
        );
      case 'pesquisas':
        AppNavigator.goToTab(2);
        AppNavigator.navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => PesquisaListScreen(pesquisaIdParaAbrir: _itemId(data)),
          ),
        );
      case 'gestor_vagas':
        AppNavigator.goToTab(2);
        AppNavigator.navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => VagasGestorScreen(vagaIdParaAbrir: _itemId(data)),
          ),
        );
      case 'candidato_chat':
        AppNavigator.goToTab(2);
        final ctxChat = AppNavigator.navigatorKey.currentContext;
        final idChat = _itemId(data);
        if (ctxChat != null && idChat != null) {
          abrirCandidaturaChatDaNotificacao(ctxChat, idChat);
        }
      case 'servicos_massoterapia':
        AppNavigator.goToTab(2);
        AppNavigator.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const MassoterapiaScreen()),
        );
      case 'servicos_nutricionista':
        AppNavigator.goToTab(2);
        AppNavigator.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const NutricionistaScreen()),
        );
      case 'servicos_fisioterapia':
        AppNavigator.goToTab(2);
        AppNavigator.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const FisioterapiaScreen()),
        );
      case 'performance': // autoavaliação / avaliação de colega liberada
        AppNavigator.goToTab(2);
        AppNavigator.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const PerformanceColabScreen()),
        );
      case 'performance_gestor': // ciclo aberto: gestor escolhe as perguntas
        AppNavigator.goToTab(2);
        AppNavigator.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const PerformanceGestorScreen()),
        );
      case 'servicos': // notificação antiga, de antes da rota específica
        AppNavigator.goToTab(2);
      default: // 'feed' ou qualquer outra coisa
        AppNavigator.goToTab(0);
    }
  }

  static int? _itemId(Map<String, dynamic>? data) =>
      int.tryParse(data?['itemId'] as String? ?? '');
}
