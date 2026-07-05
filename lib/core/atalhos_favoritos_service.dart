import 'package:shared_preferences/shared_preferences.dart';

/// Guarda localmente (no dispositivo) até 3 ids de serviços marcados como
/// atalho pelo colaborador.
class AtalhosFavoritosService {
  static const _chave = 'atalhos_favoritos';
  static const maxAtalhos = 3;

  static Future<List<String>> obterFavoritos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_chave) ?? [];
  }

  static Future<void> salvarFavoritos(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_chave, ids.take(maxAtalhos).toList());
  }
}
