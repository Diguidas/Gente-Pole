import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gentepole/core/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_navigator.dart';
import 'core/app_theme.dart';
import 'core/error_reporter.dart';
import 'screens/login_screen.dart';
import 'screens/main_layout.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/version_check_service.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    configurarCapturaGlobalDeErros();

    await Supabase.initialize(
      url: 'https://jebjtpmugcnpxxkdexyg.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplYmp0cG11Z2NucHh4a2RleHlnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg5MDUxNDEsImV4cCI6MjEwNDQ4MTE0MX0.8hUBMXaBJvKMWywd6xRQ0t_UvJoKaCkyjhkjZW0Bknk',
    );

    if (!defaultTargetPlatform.name.contains('iOS') || kIsWeb) {
      await Firebase.initializeApp();
    }

    final sessaoAtiva = await ApiService().restaurarSessao();

    if (sessaoAtiva && !defaultTargetPlatform.name.contains('iOS')) {
      // Best-effort: falha aqui (ex: SERVICE_NOT_AVAILABLE do FCM em
      // aparelhos com Play Services instável/desatualizado) não pode
      // impedir o app de abrir — sem isso, a exceção sobe antes do
      // runApp() e a tela fica preta pra sempre.
      try {
        await NotificationService.init();
      } catch (e, s) {
        ErrorReporter.report(e, s, contexto: 'Falha ao inicializar notificações');
      }
    }

    runApp(GentePoleApp(sessaoAtiva: sessaoAtiva));
    // Roda independente de login (pega quem ainda tá na tela de login) e
    // nunca trava o app se falhar (sem internet, config ausente etc).
    VersionCheckService.verificarNoInicio();
  }, (error, stack) {
    ErrorReporter.report(error, stack, contexto: 'Erro não tratado');
  });
}

class GentePoleApp extends StatelessWidget {
  final bool sessaoAtiva;
  const GentePoleApp({super.key, required this.sessaoAtiva});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gente Pole',
      theme: AppTheme.theme,
      navigatorKey: AppNavigator.navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: sessaoAtiva ? const MainLayout() : const LoginScreen(),
    );
  }
}
