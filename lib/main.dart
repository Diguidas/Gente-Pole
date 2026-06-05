import 'package:flutter/material.dart';
import 'package:gentepole/core/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_theme.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://gtwtaowrhrbwnkgmauwr.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd0d3Rhb3dyaHJid25rZ21hdXdyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0NDM0MDAsImV4cCI6MjA5NjAxOTQwMH0.vqRlIQRly4-zyLfgKt6ewwcxMikpLSGAzEQKM6K_lY4');

  runApp(const GentePoleApp());
}

class GentePoleApp extends StatelessWidget {
  const GentePoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gente Pole',
      theme: AppTheme.theme,
      home: const LoginScreen(),
    );
  }
}