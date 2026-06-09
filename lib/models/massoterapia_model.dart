/// Model de agendamento de massoterapia
class MassoterapiaAgendamentoModel {
  final int id;
  final int colaboradorId;
  final String nomeColaborador;
  final String matricula;
  final String setor;
  final String data;    // 'yyyy-MM-dd'
  final String horario; // 'HH:mm'
  final String status;  // AGENDADO | VEIO | NAO_VEIO | CANCELADO
  final String? observacao;
  final String criadoEm;

  MassoterapiaAgendamentoModel({
    required this.id,
    required this.colaboradorId,
    required this.nomeColaborador,
    required this.matricula,
    required this.setor,
    required this.data,
    required this.horario,
    required this.status,
    this.observacao,
    required this.criadoEm,
  });

  factory MassoterapiaAgendamentoModel.fromJson(Map<String, dynamic> json) {
    // O select faz join com colaboradores
    final colab = json['colaboradores'] as Map<String, dynamic>? ?? {};
    return MassoterapiaAgendamentoModel(
      id: json['id'] as int,
      colaboradorId: json['colaborador_id'] as int,
      nomeColaborador: colab['nome'] ?? '',
      matricula: colab['matricula'] ?? '',
      setor: colab['setor'] ?? '',
      data: (json['data'] as String).substring(0, 10),
      horario: (json['horario'] as String).substring(0, 5),
      status: json['status'] ?? 'AGENDADO',
      observacao: json['observacao'],
      criadoEm: json['criado_em'] ?? '',
    );
  }
}

/// Configuração de vagas por setor
class MassoterapiaConfigSetorModel {
  final int id;
  final String setor;
  final int vagasDia;
  final bool ativo;

  MassoterapiaConfigSetorModel({
    required this.id,
    required this.setor,
    required this.vagasDia,
    required this.ativo,
  });

  factory MassoterapiaConfigSetorModel.fromJson(Map<String, dynamic> json) {
    return MassoterapiaConfigSetorModel(
      id: json['id'] as int,
      setor: json['setor'] ?? '',
      vagasDia: json['vagas_dia'] as int? ?? 1,
      ativo: json['ativo'] as bool? ?? true,
    );
  }
}