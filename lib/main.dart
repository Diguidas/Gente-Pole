import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:gentepole/core/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_layout.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://gtwtaowrhrbwnkgmauwr.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd0d3Rhb3dyaHJid25rZ21hdXdyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0NDM0MDAsImV4cCI6MjA5NjAxOTQwMH0.vqRlIQRly4-zyLfgKt6ewwcxMikpLSGAzEQKM6K_lY4',
  );

  await Firebase.initializeApp();

  final sessaoAtiva = await ApiService().restaurarSessao();

  // Só inicializa notificações se já tem sessão (tem colaborador logado)
  if (sessaoAtiva) {
    await NotificationService.init();
  }

  runApp(GentePoleApp(sessaoAtiva: sessaoAtiva));
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
      home: sessaoAtiva ? const MainLayout() : const LoginScreen(),
    );
  }
}
