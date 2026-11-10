import 'package:supabase_flutter/supabase_flutter.dart';

/// Ações do Conexões do Bem com inscrições por período e limite de vagas.
/// Tolerante a tabela/RPC ausente: os métodos de leitura do colaborador
/// devolvem null quando as tabelas ainda não existem (fluxo antigo).
class ConexoesAcoesService {
  ConexoesAcoesService._();
  static SupabaseClient get _c => Supabase.instance.client;

  /// Status calculado: aberta, nao_iniciou, encerrada, esgotada, inativa.
  static String status(Map<String, dynamic> a) {
    if (a['ativo'] == false) return 'inativa';
    final agora = DateTime.now();
    final ini = DateTime.tryParse('${a['inscricao_inicio'] ?? ''}')?.toLocal();
    final fim = DateTime.tryParse('${a['inscricao_fim'] ?? ''}')?.toLocal();
    if (ini != null && agora.isBefore(ini)) return 'nao_iniciou';
    if (fim != null && agora.isAfter(fim)) return 'encerrada';
    final vagas = (a['vagas'] as num?)?.toInt() ?? 0;
    final insc = (a['inscritos'] as num?)?.toInt() ?? 0;
    if (insc >= vagas) return 'esgotada';
    return 'aberta';
  }

  static String fmtData(dynamic v, {bool hora = false}) {
    final d = DateTime.tryParse('${v ?? ''}');
    if (d == null) return '';
    final l = d.isUtc ? d.toLocal() : d;
    String p(int n) => n.toString().padLeft(2, '0');
    final s = '${p(l.day)}/${p(l.month)}/${l.year}';
    return hora ? '$s ${p(l.hour)}:${p(l.minute)}' : s;
  }

  // ── Painel ────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> listarAcoes() async {
    try {
      final res = await _c
          .from('conexoes_acoes_resumo')
          .select()
          .order('data_acao', ascending: false)
          .order('id', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> salvarAcao(Map<String, dynamic> dados, {int? id}) async {
    try {
      if (id == null) {
        await _c.from('conexoes_acoes').insert(dados);
      } else {
        await _c.from('conexoes_acoes').update(dados).eq('id', id);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> excluirAcao(int id) async {
    try {
      await _c.from('conexoes_acoes').delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> listarInscritos(int acaoId) async {
    try {
      final res = await _c
          .from('conexoes_inscricoes')
          .select()
          .eq('acao_id', acaoId)
          .order('criado_em');
      final lista = List<Map<String, dynamic>>.from(res);
      final ids = lista
          .map((e) => e['colaborador_id'])
          .whereType<int>()
          .toSet()
          .toList();
      if (ids.isEmpty) return lista;
      final colabs = await _c
          .from('colaboradores')
          .select('id, nome, setor')
          .inFilter('id', ids);
      final mapa = {for (final c in colabs) c['id'] as int: c};
      return lista
          .map((e) => {...e, 'colaboradores': mapa[e['colaborador_id']] ?? {}})
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> removerInscrito(int inscricaoId) async {
    try {
      await _c.from('conexoes_inscricoes').delete().eq('id', inscricaoId);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Colaborador ───────────────────────────────────────────────────────────

  /// Ações ativas (abertas ou futuras, não encerradas). null = tabelas ausentes.
  static Future<List<Map<String, dynamic>>?> listarAcoesColab() async {
    try {
      final res = await _c
          .from('conexoes_acoes_resumo')
          .select()
          .eq('ativo', true)
          .order('data_acao');
      return List<Map<String, dynamic>>.from(res)
          .where((a) => status(a) != 'encerrada')
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Minhas inscrições, indexadas por acao_id.
  static Future<Map<int, Map<String, dynamic>>> minhasInscricoes(
      int colaboradorId) async {
    try {
      final res = await _c
          .from('conexoes_inscricoes')
          .select()
          .eq('colaborador_id', colaboradorId);
      return {
        for (final r in res) (r['acao_id'] as num).toInt(): Map<String, dynamic>.from(r)
      };
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, dynamic>> inscrever({
    required int acaoId,
    required int colaboradorId,
    required String matricula,
    required String tamanhoCamisa,
    required String whatsapp,
  }) async {
    try {
      final r = await _c.rpc('inscrever_conexoes_acao', params: {
        'p_acao_id': acaoId,
        'p_colaborador_id': colaboradorId,
        'p_matricula': matricula,
        'p_tamanho_camisa': tamanhoCamisa,
        'p_whatsapp': whatsapp,
      });
      return Map<String, dynamic>.from(r as Map);
    } catch (_) {
      return {
        'ok': false,
        'motivo': 'erro',
        'mensagem': 'Não foi possível inscrever. Tente novamente.'
      };
    }
  }

  static Future<bool> cancelar(int acaoId, int colaboradorId) async {
    try {
      await _c.rpc('cancelar_inscricao_conexoes', params: {
        'p_acao_id': acaoId,
        'p_colaborador_id': colaboradorId,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
