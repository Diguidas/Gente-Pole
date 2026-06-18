// models/feed_post_model.dart

/// Representa um post no Feed.
///
/// [tipo] pode ser:
///   'post'                 — post normal de um colaborador
///   'comunicado'           — comunicado do sistema / Gente Pole
///   'aniversario'          — felicitação automática de aniversário de nascimento
///   'aniversario_empresa'  — felicitação automática de aniversário de empresa
class FeedPostModel {
  final int id;
  final int? autorId;
  final String? autorNome;
  final String? autorFotoUrl;
  final String? autorCargo;
  final String tipo; // 'post' | 'comunicado' | 'aniversario' | 'aniversario_empresa'
  final String? titulo;
  final String? conteudo;
  final String? imagemUrl;
  final String destinatario; // 'todos' | '@setor:NomeSetor' | '@colaborador:42'
  final DateTime criadoEm;
  // 'aprovado' | 'pendente' | 'rejeitado' — só relevante para posts para 'todos'
  final String status;

  const FeedPostModel({
    required this.id,
    this.autorId,
    this.autorNome,
    this.autorFotoUrl,
    this.autorCargo,
    required this.tipo,
    this.titulo,
    this.conteudo,
    this.imagemUrl,
    required this.destinatario,
    required this.criadoEm,
    this.status = 'aprovado',
  });

  factory FeedPostModel.fromJson(Map<String, dynamic> json) {
    // O autor vem via join: autor:colaboradores(nome, foto_url, cargo)
    final autor = json['autor'] as Map<String, dynamic>?;

    return FeedPostModel(
      id: json['id'] as int,
      autorId: json['autor_id'] as int?,
      autorNome: autor?['nome'] as String?,
      autorFotoUrl: autor?['foto_url'] as String?,
      autorCargo: autor?['cargo'] as String?,
      tipo: json['tipo'] as String? ?? 'post',
      titulo: json['titulo'] as String?,
      conteudo: json['conteudo'] as String?,
      imagemUrl: json['imagem_url'] as String?,
      destinatario: json['destinatario'] as String? ?? 'todos',
      criadoEm: DateTime.parse(json['criado_em'] as String),
      status: json['status'] as String? ?? 'aprovado',
    );
  }

  /// Retorna label legível do destinatário para exibir no post.
  /// Ex: 'Para todos', 'Para @TI', 'Para @João Silva'
  /// Formato do destinatario para colaborador: '@colaborador:42|HELIO PESSOA'
  String get destinatarioLabel {
    if (destinatario == 'todos') return 'Para todos';
    if (destinatario.startsWith('@setor:')) {
      return 'Para @${destinatario.substring(7)}';
    }
    if (destinatario.startsWith('@colaborador:')) {
      final pipeIdx = destinatario.indexOf('|');
      if (pipeIdx >= 0) return '@${destinatario.substring(pipeIdx + 1)}';
      return 'Menção direta';
    }
    return destinatario;
  }

  /// Tempo relativo humanizado (agora, 5 min, 2h, ontem, etc.)
  String get tempoRelativo {
    final diff = DateTime.now().difference(criadoEm);
    if (diff.inSeconds < 60) return 'agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays == 1) return 'ontem';
    if (diff.inDays < 7) return '${diff.inDays}d';
    // Formata dd/mm
    return '${criadoEm.day.toString().padLeft(2, '0')}/${criadoEm.month.toString().padLeft(2, '0')}';
  }

  FeedPostModel copyWith({String? status}) => FeedPostModel(
        id: id,
        autorId: autorId,
        autorNome: autorNome,
        autorFotoUrl: autorFotoUrl,
        autorCargo: autorCargo,
        tipo: tipo,
        titulo: titulo,
        conteudo: conteudo,
        imagemUrl: imagemUrl,
        destinatario: destinatario,
        criadoEm: criadoEm,
        status: status ?? this.status,
      );

  bool get isDoSistema => autorId == null;
  bool get temImagem => imagemUrl != null && imagemUrl!.isNotEmpty;
  bool get isAniversario =>
      tipo == 'aniversario' || tipo == 'aniversario_empresa';
  bool get isPendente => status == 'pendente';
  bool get isRejeitado => status == 'rejeitado';
  bool get isAprovado => status == 'aprovado';
}