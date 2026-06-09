import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';

class AvatarColaborador extends StatelessWidget {
  final String? fotoUrl;
  final String nome;
  final double raio;

  const AvatarColaborador({
    super.key,
    required this.fotoUrl,
    required this.nome,
    this.raio = 22,
  });

  String _iniciais(String nome) {
    final p = nome.trim().split(' ');
    return p.length >= 2
        ? '${p.first[0]}${p.last[0]}'.toUpperCase()
        : nome.isNotEmpty
            ? nome[0].toUpperCase()
            : '?';
  }

  @override
  Widget build(BuildContext context) {
    final iniciais = _iniciais(nome);

    if (fotoUrl == null || fotoUrl!.isEmpty) {
      return CircleAvatar(
        radius: raio,
        backgroundColor: AppColors.laranjaOp15,
        child: Text(
          iniciais,
          style: GoogleFonts.poppins(
            fontSize: raio * 0.55,
            fontWeight: FontWeight.w700,
            color: AppColors.laranja,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: raio,
      backgroundColor: AppColors.laranjaOp15,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: fotoUrl!,
          width: raio * 2,
          height: raio * 2,
          fit: BoxFit.cover,
          placeholder: (context, url) => Center(
            child: Text(
              iniciais,
              style: GoogleFonts.poppins(
                fontSize: raio * 0.55,
                fontWeight: FontWeight.w700,
                color: AppColors.laranja,
              ),
            ),
          ),
          errorWidget: (context, url, error) => Center(
            child: Text(
              iniciais,
              style: GoogleFonts.poppins(
                fontSize: raio * 0.55,
                fontWeight: FontWeight.w700,
                color: AppColors.laranja,
              ),
            ),
          ),
        ),
      ),
    );
  }
}