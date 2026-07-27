import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gentepole/core/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_theme.dart';
import 'core/error_reporter.dart';
import 'screens/login_screen.dart';
import 'screens/main_layout.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    configurarCapturaGlobalDeErros();

    await Supabase.initialize(
      url: 'https://gtwtaowrhrbwnkgmauwr.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd0d3Rhb3dyaHJid25rZ21hdXdyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0NDM0MDAsImV4cCI6MjA5NjAxOTQwMH0.vqRlIQRly4-zyLfgKt6ewwcxMikpLSGAzEQKM6K_lY4',
    );

    if (!defaultTargetPlatform.name.contains('iOS') || kIsWeb) {
      await Firebase.initializeApp();
    }

    final sessaoAtiva = await ApiService().restaurarSessao();

    if (sessaoAtiva && !defaultTargetPlatform.name.contains('iOS')) {
      await NotificationService.init();
    }

    runApp(GentePoleApp(sessaoAtiva: sessaoAtiva));
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
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: sessaoAtiva ? const MainLayout() : const LoginScreen(),
    );
  }
}
