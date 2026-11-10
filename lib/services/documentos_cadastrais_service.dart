import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Documentos pessoais, dependentes, atualização cadastral e crachá virtual
/// do colaborador (porte do service do painel web).
///
/// Documentos de colaboradores ativos ficam em `colaborador_documentos` e os
/// dependentes em `dependentes` / `dependentes_documentos`. As colunas
/// `colaborador_id` dessas tabelas são texto: sempre converta o id (int) com
/// `toString()`.
class DocumentosCadastraisService {
  DocumentosCadastraisService._();
  static final instance = DocumentosCadastraisService._();

  SupabaseClient get _c => Supabase.instance.client;
  static const _bucket = 'documentos-admissao';

  static const tiposDocumentoPessoal = <(String, String)>[
    ('RG_FRENTE', 'RG (frente)'),
    ('RG_VERSO', 'RG (verso)'),
    ('CPF', 'CPF'),
    ('COMPROVANTE_RESIDENCIA', 'Comprovante de residência'),
    ('COMPROVANTE_ESCOLARIDADE', 'Comprovante de escolaridade'),
    ('CARTEIRA_TRABALHO', 'Carteira de trabalho'),
    ('PIS', 'PIS/PASEP'),
    ('TITULO_ELEITOR', 'Título de eleitor'),
    ('RESERVISTA', 'Certificado de reservista'),
    ('CNH', 'CNH'),
    ('CONTA_BANCARIA', 'Comprovante bancário'),
    ('FOTOGRAFIA', 'Foto 3×4'),
  ];

  static const tiposDocumentoDependente = <(String, String)>[
    ('CERTIDAO_NASCIMENTO', 'Certidão de nascimento'),
    ('CPF', 'CPF'),
    ('RG', 'RG'),
    ('DECLARACAO_ESCOLAR', 'Declaração escolar'),
    ('CARTAO_VACINA', 'Cartão de vacina'),
    ('CERTIDAO_CASAMENTO', 'Certidão de casamento'),
  ];

  static const parentescos = <(String, String)>[
    ('filho', 'Filho(a)'),
    ('companheiro', 'Companheiro(a)'),
    ('outro', 'Outro'),
  ];

  static String rotuloParentesco(String? v) => parentescos
      .firstWhere((p) => p.$1 == v, orElse: () => ('outro', 'Outro'))
      .$2;

  String _nomeSeguro(String n) => n.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<String> _subir(String path, Uint8List bytes) async {
    await _c.storage.from(_bucket).uploadBinary(path, bytes,
        fileOptions: const FileOptions(upsert: true));
    return _c.storage.from(_bucket).getPublicUrl(path);
  }

  // ─── Dependentes ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listarDependentes(
      String colaboradorId) async {
    final res = await _c
        .from('dependentes')
        .select('*, dependentes_documentos(*)')
        .eq('colaborador_id', colaboradorId)
        .order('criado_em');
    return (res as List).map((m) {
      final mapa = Map<String, dynamic>.from(m as Map);
      mapa['documentos'] = mapa.remove('dependentes_documentos') ?? [];
      return mapa;
    }).toList();
  }

  Future<void> adicionarDependente({
    required String colaboradorId,
    required String nome,
    required String parentesco,
  }) async {
    await _c.from('dependentes').insert({
      'colaborador_id': colaboradorId,
      'nome': nome.trim(),
      'parentesco': parentesco,
    });
  }

  Future<void> removerDependente(dynamic id) async {
    await _c.from('dependentes').delete().eq('id', id);
  }

  Future<void> uploadDocumentoDependente({
    required dynamic dependenteId,
    required String tipo,
    required Uint8List bytes,
    required String nomeArquivo,
  }) async {
    final url = await _subir(
        'dependentes/$dependenteId/${tipo}_${_nomeSeguro(nomeArquivo)}', bytes);
    await _c.from('dependentes_documentos').upsert({
      'dependente_id': dependenteId,
      'tipo': tipo,
      'arquivo_url': url,
      'nome_arquivo': nomeArquivo,
      'enviado_em': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'dependente_id,tipo');
  }

  // ─── Documentos pessoais ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listarDocumentosPessoais(
      String colaboradorId) async {
    final res = await _c
        .from('colaborador_documentos')
        .select()
        .eq('colaborador_id', colaboradorId);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> uploadDocumentoPessoal({
    required String colaboradorId,
    required String tipo,
    required Uint8List bytes,
    required String nomeArquivo,
  }) async {
    final url = await _subir(
        'colaboradores/$colaboradorId/${tipo}_${_nomeSeguro(nomeArquivo)}',
        bytes);
    await _c.from('colaborador_documentos').upsert({
      'colaborador_id': colaboradorId,
      'tipo': tipo,
      'arquivo_url': url,
      'nome_arquivo': nomeArquivo,
      'enviado_em': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'colaborador_id,tipo');
  }

  // ─── Atualização cadastral ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listarPedidosPendentes(
      String colaboradorId) async {
    final res = await _c
        .from('atualizacao_cadastral_pedidos')
        .select()
        .eq('colaborador_id', colaboradorId)
        .eq('status', 'pendente')
        .order('criado_em', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> concluirPedidos(String colaboradorId) async {
    await _c.from('atualizacao_cadastral_pedidos').update({
      'status': 'concluido',
      'concluido_em': DateTime.now().toUtc().toIso8601String(),
    }).eq('colaborador_id', colaboradorId).eq('status', 'pendente');
  }

  Future<bool> lembreteAnualAtivo() async {
    try {
      final r = await _c
          .from('atualizacao_cadastral_config')
          .select('lembrete_anual_ativo')
          .eq('id', 1)
          .maybeSingle();
      return r?['lembrete_anual_ativo'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Lembrete anual: dentro dos 30 dias após cada aniversário de empresa
  /// (com pelo menos 1 ano), se o colaborador ainda não atualizou desde então.
  /// Devolve a chave do aviso (ex.: 'cad_anual:2026') ou null.
  Future<String?> lembreteAnualPendente({
    required String colaboradorId,
    required String? dataAdmissao,
  }) async {
    final adm = DateTime.tryParse(dataAdmissao ?? '');
    if (adm == null) return null;
    final hoje = DateTime.now();
    var aniv = DateTime(hoje.year, adm.month, adm.day);
    if (aniv.isAfter(hoje)) aniv = DateTime(hoje.year - 1, adm.month, adm.day);
    if (aniv.year <= adm.year) return null; // menos de 1 ano de casa
    if (hoje.difference(aniv).inDays > 30) return null;
    if (!await lembreteAnualAtivo()) return null;
    final ult = await _c
        .from('colaborador_documentos')
        .select('enviado_em')
        .eq('colaborador_id', colaboradorId)
        .order('enviado_em', ascending: false)
        .limit(1);
    if ((ult as List).isNotEmpty) {
      final dt = DateTime.tryParse(ult.first['enviado_em'] as String? ?? '');
      if (dt != null && dt.toLocal().isAfter(aniv)) return null;
    }
    return 'cad_anual:${aniv.year}';
  }

  // ─── Crachá virtual ─────────────────────────────────────────────────────

  /// Crachá do colaborador; null se não cadastrado (ou erro de leitura).
  Future<({String? frente, String? verso})?> buscarCracha(
      int colaboradorId) async {
    try {
      final r = await _c
          .from('colaborador_cracha')
          .select('frente_url, verso_url')
          .eq('colaborador_id', colaboradorId)
          .maybeSingle();
      if (r == null) return null;
      return (
        frente: r['frente_url'] as String?,
        verso: r['verso_url'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
