import 'colaborador_model.dart';

class AniversarianteModel {
  final ColaboradorModel colaborador;
  final int diaNascimento;
  final int mesNascimento;
  final bool ehHoje;
  final int totalParabens;

  AniversarianteModel({
    required this.colaborador,
    required this.diaNascimento,
    required this.mesNascimento,
    required this.ehHoje,
    required this.totalParabens,
  });

  factory AniversarianteModel.fromJson(Map<String, dynamic> json) {
    return AniversarianteModel(
      colaborador: ColaboradorModel.fromJson(json),
      diaNascimento: (json['dia_nascimento'] as num).toInt(),
      mesNascimento: (json['mes_nascimento'] as num).toInt(),
      ehHoje: json['eh_hoje'] == true,
      totalParabens: (json['total_parabens'] as num?)?.toInt() ?? 0,
    );
  }

  /// "03/06" formatado
  String get dataFormatada =>
      '${diaNascimento.toString().padLeft(2, '0')}/${mesNascimento.toString().padLeft(2, '0')}';
}

class ParabensModel {
  final int id;
  final String mensagem;
  final String? remetenteNome;
  final DateTime criadoEm;

  ParabensModel({
    required this.id,
    required this.mensagem,
    this.remetenteNome,
    required this.criadoEm,
  });

  factory ParabensModel.fromJson(Map<String, dynamic> json) {
    return ParabensModel(
      id: json['id'] as int,
      mensagem: json['mensagem'] ?? '',
      remetenteNome: json['remetente']?['nome'],
      criadoEm: DateTime.parse(json['criado_em']),
    );
  }
}