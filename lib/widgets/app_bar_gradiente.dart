import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';

/// Topo padrão das telas: fundo em degradê, botão de voltar, título e
/// subtítulo opcional — mesmo visual das telas de cabeçalho colorido
/// (ex.: Minha Equipe). Use em `Scaffold(appBar: AppBarGradiente(...))`.
class AppBarGradiente extends StatelessWidget implements PreferredSizeWidget {
  final String titulo;
  final String? subtitulo;
  final List<Widget> actions;

  const AppBarGradiente({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.actions = const [],
  });

  @override
  Size get preferredSize => Size.fromHeight(subtitulo == null ? 64 : 76);

  @override
  Widget build(BuildContext context) {
    final podeVoltar = Navigator.of(context).canPop();
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.gradientePrincipal),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Row(
              children: [
                if (podeVoltar)
                  IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    tooltip: 'Voltar',
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                  )
                else
                  const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700),
                      ),
                      if (subtitulo != null && subtitulo!.isNotEmpty)
                        Text(
                          subtitulo!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 12),
                        ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
