import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gentepole/core/app_theme.dart';
import 'package:gentepole/services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';

/// Menção com espaço no nome, gravada como `@[Nome Completo]`.
final RegExp regexMencaoColchetes = RegExp(r'@\[[^\]]+\]');

/// Ao apagar um caractere de dentro de uma menção `@[Nome]`, apaga a menção
/// inteira (e o espaço que vem logo depois dela, se houver).
class MencaoApagaInteira extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue antigo, TextEditingValue novo) {
    final a = antigo.text;
    final n = novo.text;
    // Só trata a remoção de UM caractere, sem seleção.
    if (n.length != a.length - 1 || !antigo.selection.isCollapsed) return novo;
    var i = 0;
    while (i < n.length && a[i] == n[i]) {
      i++;
    }
    for (final m in regexMencaoColchetes.allMatches(a)) {
      if (i >= m.start && i < m.end) {
        var fim = m.end;
        if (fim < a.length && a[fim] == ' ') fim++;
        return TextEditingValue(
          text: a.substring(0, m.start) + a.substring(fim),
          selection: TextSelection.collapsed(offset: m.start),
        );
      }
    }
    return novo;
  }
}

class _DadosPessoa {
  final String nome;
  final String? setor;
  final String? cargo;
  final String? fotoUrl;
  const _DadosPessoa(this.nome, this.setor, this.cargo, this.fotoUrl);
}

final Map<String, Future<_DadosPessoa?>> _cachePessoas = {};

Future<_DadosPessoa?> _buscarPessoa(String nome) {
  return _cachePessoas.putIfAbsent(nome, () async {
    try {
      final m = await ApiService().buscarColaboradorPorNomeExato(nome);
      if (m == null) return null;
      return _DadosPessoa(
        m['nome'] as String? ?? nome,
        m['setor'] as String?,
        m['cargo'] as String?,
        m['foto_url'] as String?,
      );
    } catch (_) {
      return null;
    }
  });
}

/// Menção já publicada: nome colorido; ao tocar, abre um cartão com foto,
/// nome, setor e cargo (se o nome for de uma pessoa).
class MencaoChip extends StatelessWidget {
  final String nome;
  final double fontSize;
  const MencaoChip({super.key, required this.nome, this.fontSize = 14});

  void _abrirCartao(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CartaoPessoa(nome: nome),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _abrirCartao(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: AppColors.magenta.withOpacity(0.08),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('@$nome',
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              color: AppColors.magenta,
              fontWeight: FontWeight.w700,
              height: 1.4,
            )),
      ),
    );
  }
}

class _CartaoPessoa extends StatelessWidget {
  final String nome;
  const _CartaoPessoa({required this.nome});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: FutureBuilder<_DadosPessoa?>(
          future: _buscarPessoa(nome),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 64,
                child: Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.magenta))),
              );
            }
            final p = snap.data;
            if (p == null) {
              return Text(nome,
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w600));
            }
            final iniciais = p.nome
                .trim()
                .split(' ')
                .take(2)
                .map((e) => e.isEmpty ? '' : e[0])
                .join()
                .toUpperCase();
            final temFoto = (p.fotoUrl ?? '').isNotEmpty;
            return Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.magenta.withOpacity(0.12),
                backgroundImage:
                    temFoto ? CachedNetworkImageProvider(p.fotoUrl!) : null,
                child: temFoto
                    ? null
                    : Text(iniciais,
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppColors.magenta)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.nome,
                        style: GoogleFonts.poppins(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    if ((p.setor ?? '').isNotEmpty)
                      Text(p.setor!,
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: AppColors.cinzaTexto)),
                    if ((p.cargo ?? '').isNotEmpty)
                      Text(p.cargo!,
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: AppColors.cinzaTexto)),
                  ],
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
