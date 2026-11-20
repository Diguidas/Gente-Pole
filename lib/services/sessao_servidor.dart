import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum EstadoSessao { valida, invalida, indeterminada }

/// Sessão emitida pelo servidor (`app_login`).
///
/// Depois do login o servidor devolve um token aleatório. Ele fica salvo no
/// aparelho e vai no cabeçalho `x-app-session` das consultas ao banco, para o
/// banco saber QUEM está pedindo (políticas de RLS usam `app_matricula()`,
/// `app_tem_papel()` etc.). O servidor guarda só o hash do token.
///
/// O cabeçalho vai nas consultas ao banco (`rest`), no Storage e nas Edge Functions (que validam a sessão
/// com `_shared/auth.ts`; todas aceitam `x-app-session` no CORS).
class SessaoServidor {
  SessaoServidor._();

  static const _kToken = 'app_sessao_token';
  static const _cabecalho = 'x-app-session';
  static String? _token;

  static SupabaseClient get _c => Supabase.instance.client;

  /// Token da sessão atual (para chamadas que precisem mandá-lo no corpo).
  static String? get token => _token;

  static void _cabecalhos(String? token) {
    for (final h in [_c.rest.headers, _c.storage.headers, _c.functions.headers]) {
      if (token == null) {
        h.remove(_cabecalho);
      } else {
        h[_cabecalho] = token;
      }
    }
  }

  static void _aplicar(String? token) {
    _token = token;
    _cabecalhos(token);
  }

  /// Faz o login no servidor e deixa a sessão ativa e salva. `false` = recusado
  /// (senha errada, conta bloqueada, muitas tentativas ou acesso não liberado).
  static Future<bool> entrar({
    required String matricula,
    required String empresa,
    required String senhaHash,
  }) async {
    final res = await _c.rpc('app_login', params: {
      'p_matricula': matricula,
      'p_empresa': empresa,
      'p_senha_hash': senhaHash,
      'p_dispositivo': kIsWeb ? 'web' : defaultTargetPlatform.name,
    });
    final rows = res as List;
    if (rows.isEmpty) return false;
    final token = (rows.first as Map)['token'] as String;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    _aplicar(token);
    return true;
  }

  /// Cabeçalho só em memória, para as páginas PÚBLICAS do portal (candidato logado ou dono do
  /// link de admissão). Não mexe na sessão salva de funcionário: com `null` volta a ela, se houver.
  static void definirCabecalhoAvulso(String? token) {
    _cabecalhos(token ?? _token);
  }

  /// Usa um token que o servidor já emitiu (ex.: login de fornecedor).
  static Future<void> usarToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    _aplicar(token);
  }

  /// Reaplica a sessão salva e confere no servidor se ela ainda vale.
  /// `indeterminada` (sem rede, por exemplo) NÃO deve derrubar quem já estava
  /// logado.
  static Future<EstadoSessao> restaurar() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kToken);
    if (token == null) return EstadoSessao.invalida;
    _aplicar(token);
    try {
      final r = await _c.rpc('app_sessao_atual') as List;
      if (r.isEmpty) {
        await _limparLocal();
        return EstadoSessao.invalida;
      }
      return EstadoSessao.valida;
    } catch (_) {
      return EstadoSessao.indeterminada;
    }
  }

  /// Encerra a sessão no servidor (melhor esforço) e apaga o token local.
  static Future<void> encerrar() async {
    try {
      if (_token != null) await _c.rpc('app_logout');
    } catch (_) {}
    await _limparLocal();
  }

  static Future<void> _limparLocal() async {
    _aplicar(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
  }
}
