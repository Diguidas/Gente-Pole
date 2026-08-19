import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const laranja = Color(0xFFFF6B00);
  static const magenta = Color(0xFFE91E8C);
  static const amarelo = Color(0xFFFFB800);
  static const dark = Color(0xFF1A1A2E);
  static const cinzaTexto = Color(0xFF6B7280);
  static const cinzaClaro = Color(0xFFF1F5F9);
  static const branco = Color(0xFFFFFFFF);
  static const fundo = Color(0xFFF8FAFC);
  static const sucesso = Color(0xFF22C55E);
  static const erro = Color(0xFFEF4444);

    // Laranja com opacidade (evita withOpacity() no build)
  static const laranjaOp08 = Color(0x14FF6B00);  // 0.08
  static const laranjaOp10 = Color(0x1AFF6B00);  // 0.10
  static const laranjaOp15 = Color(0x26FF6B00);  // 0.15

  // Magenta com opacidade
  static const magentaOp15 = Color(0x26E91E8C);  // 0.15
  static const magentaOp18 = Color(0x2EE91E8C);  // 0.18
  static const magentaOp50 = Color(0x80E91E8C);  // 0.50

  // Branco com opacidade
  static const brancoOp18 = Color(0x2EFFFFFF);   // 0.18
  static const brancoOp20 = Color(0x33FFFFFF);   // 0.20
  static const brancoOp25 = Color(0x40FFFFFF);   // 0.25
  static const brancoOp30 = Color(0x4DFFFFFF);   // 0.30
  static const brancoOp70 = Color(0xB3FFFFFF);   // 0.70
  static const brancoOp80 = Color(0xCCFFFFFF);   // 0.80

  // Preto com opacidade (sombras)
  static const pretoOp04 = Color(0x0A000000);    // 0.04
  static const pretoOp08 = Color(0x14000000);    // 0.08

  // CinzaTexto com opacidade
  static const cinzaTextoOp30 = Color(0x4D6B7280); // 0.30

  static const LinearGradient gradientePrincipal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFD000), // amarelo vibrante
      Color(0xFFFF8000), // laranja médio
      Color(0xFFE84E00), // laranja queimado
    ],
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

class AppTextStyles {
  AppTextStyles._();

  // Títulos
  static final tituloGrande = GoogleFonts.poppins(
    fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.dark,
  );
  static final tituloMedio = GoogleFonts.poppins(
    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.dark,
  );
  static final tituloPequeno = GoogleFonts.poppins(
    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.dark,
  );

  // Corpo
  static final corpoNormal = GoogleFonts.poppins(
    fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.dark,
  );
  static final corpoMedio = GoogleFonts.poppins(
    fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.dark,
  );
  static final corpoCinza = GoogleFonts.poppins(
    fontSize: 13, color: AppColors.cinzaTexto,
  );
  static final corpoMenor = GoogleFonts.poppins(
    fontSize: 12, color: AppColors.cinzaTexto,
  );
  static final corpoMinimo = GoogleFonts.poppins(
    fontSize: 11, color: AppColors.cinzaTexto,
  );

  // Branco (para usar sobre gradiente/fundo colorido)
  static final tituloBranco = GoogleFonts.poppins(
    fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white,
  );
  static final corpoBranco = GoogleFonts.poppins(
    fontSize: 13, color: Colors.white,
  );
  static final corpoBrancoOpaco = GoogleFonts.poppins(
    fontSize: 12, color: Color(0xCCFFFFFF), // white com 80% opacidade
  );

  // Botões
  static final botaoPrimario = GoogleFonts.poppins(
    fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white,
  );
  static final labelSecao = GoogleFonts.poppins(
    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.dark,
  );
}