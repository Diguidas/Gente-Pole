import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_navigator.dart';
import 'api_service.dart';

/// Avisa quando tem uma versão nova do app disponível — lê
/// `app_versao_config` (linha única, editada pelo admin no painel web) e
/// compara com a versão instalada:
/// - abaixo da mínima: dialog bloqueante, sem como fechar sem atualizar
/// - abaixo da recomendada (mas acima da mínima): dialog dispensável
class VersionCheckService {
  VersionCheckService._();

  static bool _jaVerificou = false;

  /// Best-effort: qualquer falha aqui (sem internet, config ausente, etc)
  /// não pode impedir o uso do app — só não mostra o aviso dessa vez.
  static Future<void> verificarNoInicio() async {
    if (_jaVerificou || kIsWeb) return;
    _jaVerificou = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final config = await ApiService().buscarConfigVersaoApp();
      if (config == null) return;

      final urlLoja = config['url_play_store'] as String?;
      if (urlLoja == null || urlLoja.isEmpty) return;

      final versaoMinima = config['versao_minima'] as String?;
      final versaoRecomendada = config['versao_recomendada'] as String?;
      final mensagem = config['mensagem'] as String?;
      final versaoAtual = info.version;

      final abaixoDaMinima =
          versaoMinima != null && _comparar(versaoAtual, versaoMinima) < 0;
      final abaixoDaRecomendada = versaoRecomendada != null &&
          _comparar(versaoAtual, versaoRecomendada) < 0;

      if (!abaixoDaMinima && !abaixoDaRecomendada) return;

      // Espera o primeiro frame renderizar — sem isso o navigatorKey ainda
      // não tem um context válido pra abrir o dialog.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = AppNavigator.navigatorKey.currentContext;
        if (context == null) return;
        _mostrarDialog(
          context,
          obrigatorio: abaixoDaMinima,
          urlLoja: urlLoja,
          mensagem: mensagem,
        );
      });
    } catch (_) {
      // Silencioso de propósito — ver comentário acima.
    }
  }

  /// Compara duas versões "x.y.z" — negativo se [a] < [b], 0 se igual,
  /// positivo se [a] > [b]. Ignora sufixos não numéricos (build number etc).
  static int _comparar(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }

  static Future<void> _mostrarDialog(
    BuildContext context, {
    required bool obrigatorio,
    required String urlLoja,
    String? mensagem,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !obrigatorio,
      builder: (ctx) => PopScope(
        canPop: !obrigatorio,
        child: AlertDialog(
          icon: const Icon(Icons.system_update_rounded, size: 36, color: Color(0xFFE91E8C)),
          title: Text(
            obrigatorio ? 'Atualização necessária' : 'Nova versão disponível',
            textAlign: TextAlign.center,
          ),
          content: Text(
            mensagem?.isNotEmpty == true
                ? mensagem!
                : obrigatorio
                    ? 'Esta versão do app não é mais suportada. Atualize pra continuar usando o Gente Pole.'
                    : 'Tem uma versão nova do Gente Pole com melhorias e correções. Que tal atualizar?',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            if (!obrigatorio)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Agora não'),
              ),
            ElevatedButton(
              onPressed: () => launchUrl(
                Uri.parse(urlLoja),
                mode: LaunchMode.externalApplication,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE91E8C),
                foregroundColor: Colors.white,
              ),
              child: const Text('Atualizar agora'),
            ),
          ],
        ),
      ),
    );
  }
}
