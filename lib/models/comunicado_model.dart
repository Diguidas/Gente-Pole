class ComunicadoModel {
  final int id;
  final String titulo;
  final String? descricao;
  final String? fotoUrl;
  final DateTime criadoEm;

  ComunicadoModel({
    required this.id,
    required this.titulo,
    this.descricao,
    this.fotoUrl,
    required this.criadoEm,
  });

  factory ComunicadoModel.fromJson(Map<String, dynamic> json) {
    return ComunicadoModel(
      id: json['id'] as int,
      titulo: json['titulo'] ?? '',
      descricao: json['descricao'],
      fotoUrl: json['foto_url'],
      criadoEm: DateTime.parse(json['criado_em']),
    );
  }

  /// "03/06/2026"
  String get dataFormatada {
    return '${criadoEm.day.toString().padLeft(2, '0')}/'
        '${criadoEm.month.toString().padLeft(2, '0')}/'
        '${criadoEm.year}';
  }
}