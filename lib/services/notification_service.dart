import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/app_navigator.dart';
import '../screens/ti/chamados_ti_screen.dart';
import '../screens/pesquisa/pesquisa_list_screen.dart';
import '../screens/gestor/vagas_gestor_screen.dart';
import '../screens/massoterapia/massoterapia_screen.dart';
import '../screens/nutricionista/nutricionista_screen.dart';
import '../screens/fisioterapia/fisioterapia_screen.dart';
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

  static Future<void> init() async {
    // Registra handler de background
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

    // Pede permissão ao usuário
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

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
    );

    // Notificação em foreground → exibe local
    FirebaseMessaging.onMessage.listen(_showLocal);

    // Toque em notificação com app em background (não fechado)
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _navigate(m.data));

    // Toque com app fechado
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _navigate(initial.data);

    // Salva token FCM no Supabase e escuta renovações
    final token = await _fcm.getToken();
    if (token != null) await ApiService().salvarFcmToken(token);
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
      case 'servicos': // notificação antiga, de antes da rota específica
        AppNavigator.goToTab(2);
      default: // 'feed' ou qualquer outra coisa
        AppNavigator.goToTab(0);
    }
  }

  static int? _itemId(Map<String, dynamic>? data) =>
      int.tryParse(data?['itemId'] as String? ?? '');
}
