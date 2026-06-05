class VagaModel {
  final int id;
  final String titulo;
  final String? descricao;
  final String? departamento;
  final String? localidade;
  final String tipoContrato;
  final double? faixaSalarialMin;
  final double? faixaSalarialMax;
  final bool salarioAExibir;
  final bool testePratico;
  final String status;
  final String tipoVaga;
  final int? requisitadoPorId;
  final String statusRequisicao;
  final DateTime createdAt;

  VagaModel({
    required this.id,
    required this.titulo,
    this.descricao,
    this.departamento,
    this.localidade,
    required this.tipoContrato,
    this.faixaSalarialMin,
    this.faixaSalarialMax,
    required this.salarioAExibir,
    required this.testePratico,
    required this.status,
    required this.tipoVaga,
    this.requisitadoPorId,
    required this.statusRequisicao,
    required this.createdAt,
  });

  factory VagaModel.fromJson(Map<String, dynamic> json) {
    return VagaModel(
      id: json['id'] as int,
      titulo: json['titulo'] ?? '',
      descricao: json['descricao'],
      departamento: json['departamento'],
      localidade: json['localidade'],
      tipoContrato: json['tipo_contrato'] ?? 'CLT',
      faixaSalarialMin: (json['faixa_salarial_min'] as num?)?.toDouble(),
      faixaSalarialMax: (json['faixa_salarial_max'] as num?)?.toDouble(),
      salarioAExibir: json['salario_a_exibir'] == true,
      testePratico: json['teste_pratico'] == true,
      status: json['status'] ?? 'ABERTA',
      tipoVaga: json['tipo_vaga'] ?? 'UNICA',
      requisitadoPorId: json['requisitado_por_id'] as int?,
      statusRequisicao: json['status_requisicao'] ?? 'APROVADA',
      createdAt: DateTime.parse(
        (json['created_at'] ?? json['criado_em']) as String,
      ),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'titulo': titulo,
      'descricao': descricao,
      'departamento': departamento,
      'localidade': localidade,
      'tipo_contrato': tipoContrato,
      'faixa_salarial_min': faixaSalarialMin,
      'faixa_salarial_max': faixaSalarialMax,
      'salario_a_exibir': salarioAExibir,
      'teste_pratico': testePratico,
      'status': 'FECHADA', // vaga começa fechada até RH aprovar
      'tipo_vaga': tipoVaga,
      'requisitado_por_id': requisitadoPorId,
      'status_requisicao': 'AGUARDANDO_APROVACAO_RH',
    };
  }
}

class CandidaturaGestorModel {
  final int id;
  final int vagaId;
  final String candidatoNome;
  final String candidatoEmail;
  final String? candidatoTelefone;
  final String? candidatoCidade;
  final String? candidatoEstado;
  final String? resumoProfissional;
  final String? curriculoUrl;
  final String status;
  final double? salarioEsperado;
  final String? motivoReprovacao;
  final String? testePraticoStatus;
  final DateTime createdAt;

  CandidaturaGestorModel({
    required this.id,
    required this.vagaId,
    required this.candidatoNome,
    required this.candidatoEmail,
    this.candidatoTelefone,
    this.candidatoCidade,
    this.candidatoEstado,
    this.resumoProfissional,
    this.curriculoUrl,
    required this.status,
    this.salarioEsperado,
    this.motivoReprovacao,
    this.testePraticoStatus,
    required this.createdAt,
  });

  factory CandidaturaGestorModel.fromJson(Map<String, dynamic> json) {
    final candidato = json['candidatos'] as Map<String, dynamic>? ?? {};
    return CandidaturaGestorModel(
      id: json['id'] as int,
      vagaId: json['vaga_id'] as int,
      candidatoNome: candidato['nome'] ?? '',
      candidatoEmail: candidato['email'] ?? '',
      candidatoTelefone: candidato['telefone'],
      candidatoCidade: candidato['cidade'],
      candidatoEstado: candidato['estado'],
      resumoProfissional: candidato['resumo_profissional'],
      curriculoUrl: candidato['curriculo_url'],
      status: json['status'] ?? 'INSCRITO',
      salarioEsperado: (json['salario_esperado'] as num?)?.toDouble(),
      motivoReprovacao: json['motivo_reprovacao'],
      testePraticoStatus: json['teste_pratico_status'],
      createdAt: DateTime.parse(
        (json['created_at'] ?? json['criado_em']) as String,
      ),
    );
  }
}