class ColaboradorModel {
  final int id;
  final String matricula;
  final String nome;
  final String? setor;
  final String? cargo;
  final String? cpf;
  final String? dataNascimento;
  final String? dataAdmissao;
  final int? supervisorId;
  final String? fotoUrl;
  final String? clienteSap;

  ColaboradorModel({
    required this.id,
    required this.matricula,
    required this.nome,
    this.setor,
    this.cargo,
    this.cpf,
    this.dataNascimento,
    this.dataAdmissao,
    this.supervisorId,
    this.fotoUrl, this.clienteSap,
  });

  factory ColaboradorModel.fromJson(Map<String, dynamic> json) {
    return ColaboradorModel(
      id: json['id'] as int,
      matricula: json['matricula'] ?? '',
      nome: json['nome'] ?? '',
      setor: json['setor'],
      cargo: json['cargo'],
      cpf: json['cpf'],
      dataNascimento: json['data_nascimento'],
      dataAdmissao: json['data_admissao'],
      supervisorId: json['supervisor_id'],
      fotoUrl: json['foto_url'],
      clienteSap: json['cliente_sap'],
    );
  }

  /// Retorna o primeiro nome do colaborador
  String get primeiroNome => nome.split(' ').first;

  /// Formata data de admissão para exibição (yyyy-mm-dd → dd/mm/yyyy)
  String? get dataAdmissaoFormatada {
    if (dataAdmissao == null) return null;
    final parts = dataAdmissao!.split('-');
    if (parts.length != 3) return dataAdmissao;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }
}