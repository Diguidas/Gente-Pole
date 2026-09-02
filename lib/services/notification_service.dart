import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/app_navigator.dart';
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
      onDidReceiveNotificationResponse: (r) => _navigate(r.payload),
    );

    // Notificação em foreground → exibe local
    FirebaseMessaging.onMessage.listen(_showLocal);

    // Toque em notificação com app em background (não fechado)
    FirebaseMessaging.onMessageOpenedApp
        .listen((m) => _navigate(m.data['route'] as String?));

    // Toque com app fechado
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _navigate(initial.data['route'] as String?);

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
      payload: message.data['route'] as String?,
    );
  }

  // Mapeia a rota da notificação para uma aba do app
  // 0 = Feed | 1 = Aniversariantes | 2 = Serviços | 3 = Perfil
  static void _navigate(String? route) {
    switch (route) {
      case 'aniversario':
      case 'parabens':
        AppNavigator.goToTab(1);
      case 'servicos':
      case 'pesquisas':
      case 'gestor_exames':
      case 'gestor_vagas':
      case 'gestor_feedback':
      case 'gestor_equipe':
        AppNavigator.goToTab(2);
      case 'perfil':
        AppNavigator.goToTab(3);
      default: // 'feed' ou qualquer outra coisa
        AppNavigator.goToTab(0);
    }
  }
}
