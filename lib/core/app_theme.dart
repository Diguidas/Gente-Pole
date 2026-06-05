import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const laranja = Color(0xFFFF6B00);
  static const magenta = Color(0xFFE91E8C);
  static const amarelo = Color(0xFFFFB800);
  static const dark = Color(0xFF1A1A2E);
  static const cinzaTexto = Color(0xFF6B7280);
  static const cinzaClaro = Color(0xFFF1F5F9);
  static const branco = Color(0xFFFFFFFF);

  static const gradientePrincipal = LinearGradient(
    colors: [laranja, magenta],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const gradienteVertical = LinearGradient(
    colors: [laranja, magenta],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        fontFamily: 'Poppins',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.laranja,
          primary: AppColors.laranja,
          secondary: AppColors.magenta,
        ),
        scaffoldBackgroundColor: AppColors.branco,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: AppColors.branco,
          ),
          iconTheme: IconThemeData(color: AppColors.branco),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.magenta,
            foregroundColor: AppColors.branco,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: AppColors.magenta,
          unselectedItemColor: AppColors.cinzaTexto,
          backgroundColor: AppColors.branco,
          elevation: 12,
          type: BottomNavigationBarType.fixed,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.cinzaClaro,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          labelStyle: const TextStyle(color: AppColors.cinzaTexto),
        ),
      );
}