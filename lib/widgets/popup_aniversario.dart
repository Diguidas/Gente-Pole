import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_theme.dart';
import '../core/nivel_tempo_casa.dart';
import '../services/api_service.dart';

/// Pop-up festivo mostrado ao abrir o app no dia do natalício e/ou do
/// aniversário de tempo de empresa (>= 1 ano) do colaborador logado.
/// Aparece uma única vez por dia, por tipo e matrícula (SharedPreferences).
/// Natalício e empresa no mesmo dia: um após o outro.
class PopupAniversario {
  PopupAniversario._();

  static DateTime? _parseData(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final iso = DateTime.tryParse(v.trim());
    if (iso != null) return iso;
    final p = v.trim().split('/');
    if (p.length == 3) {
      final d = int.tryParse(p[0]), m = int.tryParse(p[1]), a = int.tryParse(p[2]);
      if (d != null && m != null && a != null) return DateTime(a, m, d);
    }
    return null;
  }

  static String _chave(DateTime hoje, String tipo, String matricula) {
    final d = '${hoje.year}${hoje.month.toString().padLeft(2, '0')}'
        '${hoje.day.toString().padLeft(2, '0')}';
    return 'aniv_popup_${d}_${tipo}_$matricula';
  }

  static Future<void> verificar(BuildContext context) async {
    try {
      final api = ApiService();
      final colab = api.colaboradorAtual;
      if (colab == null) return;
      final hoje = DateTime.now();
      final nasc = _parseData(colab.dataNascimento);
      final adm = _parseData(colab.dataAdmissao);

      final eventos = <({String tipo, int anos})>[];
      if (nasc != null && nasc.day == hoje.day && nasc.month == hoje.month) {
        eventos.add((tipo: 'natalicio', anos: hoje.year - nasc.year));
      }
      if (adm != null && adm.day == hoje.day && adm.month == hoje.month) {
        final anos = hoje.year - adm.year;
        if (anos >= 1) eventos.add((tipo: 'empresa', anos: anos));
      }
      if (eventos.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      for (final e in eventos) {
        final chave = _chave(hoje, e.tipo, colab.matricula);
        if (prefs.getBool(chave) == true) continue;
        // Marca antes de mostrar: mesmo que o app feche, não repete no dia.
        await prefs.setBool(chave, true);

        Map<String, dynamic>? msg;
        try {
          msg = await api.buscarMensagemEmpresaAniversario(tipo: e.tipo);
        } catch (_) {}
        if (!context.mounted) return;
        await _mostrar(context, colab.primeiroNome, e.tipo, e.anos, msg);
        if (!context.mounted) return;
      }
    } catch (_) {
      // Pop-up é só cortesia: qualquer falha é silenciosa.
    }
  }

  static String _aplicar(String texto, String nome, int anos) => texto
      .replaceAll(RegExp(r'\{nome\}', caseSensitive: false), nome)
      .replaceAll(RegExp(r'\{anos\}', caseSensitive: false), '$anos');

  static Future<void> _mostrar(BuildContext context, String nome, String tipo,
      int anos, Map<String, dynamic>? msg) {
    final empresa = tipo == 'empresa';
    final tituloPadrao = empresa
        ? 'Feliz aniversário de empresa, $nome!'
        : 'Feliz aniversário, $nome!';
    final corpoPadrao = empresa
        ? 'Hoje você completa $anos ${anos == 1 ? 'ano' : 'anos'} de Pole. '
            'Obrigado por fazer parte da nossa história!'
        : 'Hoje o dia é todo seu! Desejamos muita saúde, alegria e conquistas. '
            'Aproveite!';
    final titulo = (msg?['titulo'] as String?)?.trim();
    final corpo = (msg?['corpo'] as String?)?.trim();
    final tituloFinal = _aplicar(
        (titulo == null || titulo.isEmpty) ? tituloPadrao : titulo, nome, anos);
    final corpoFinal = _aplicar(
        (corpo == null || corpo.isEmpty) ? corpoPadrao : corpo, nome, anos);
    final nivel =
        empresa ? NivelTempoCasa.deCategoria(NivelTempoCasa.categoriaDeAnos(anos)) : null;

    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration:
                    const BoxDecoration(gradient: AppColors.gradientePrincipal),
                child: Column(
                  children: [
                    Icon(
                        empresa
                            ? Icons.workspace_premium_rounded
                            : Icons.cake_rounded,
                        color: Colors.white,
                        size: 56),
                    if (nivel != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(nivel.icone, color: nivel.cor, size: 18),
                            const SizedBox(width: 4),
                            Text('${nivel.label} · $anos anos',
                                style: AppTextStyles.corpoMenor.copyWith(
                                    color: nivel.cor,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(
                  children: [
                    Text(tituloFinal,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.tituloMedio),
                    const SizedBox(height: 10),
                    Text(corpoFinal,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.corpoNormal),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.magenta,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Obrigado!'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
