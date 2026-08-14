/// Models de Fisioterapia (app do colaborador/prestador).
/// Espelham as tabelas fisioterapia_casos / fisioterapia_sessoes /
/// fisioterapia_exercicios / fisioterapia_termos, criadas e mantidas pelo
/// app Admin (mesmo schema, mesmos buckets).

class FisioterapiaCaso {
  final int id;
  final int colaboradorId;
  final int? fisioterapeutaId;
  final String patologia;
  final String justificativa;
  final String status; // 'em_espera' | 'ativo' | 'alta' | 'encerrado_sesmt'
  final int? sessoesPrevistas;
  final String? motivoEncerramentoSesmt;
  final DateTime? dataAlta;
  final String? assinaturaAltaUrl;
  final DateTime? criadoEm;

  // Vem do join com `colaboradores` — só preenchido quando o select pede.
  final String? nomeColaborador;
  final String? matriculaColaborador;
  final String? setorColaborador;

  FisioterapiaCaso({
    required this.id,
    required this.colaboradorId,
    this.fisioterapeutaId,
    required this.patologia,
    required this.justificativa,
    this.status = 'em_espera',
    this.sessoesPrevistas,
    this.motivoEncerramentoSesmt,
    this.dataAlta,
    this.assinaturaAltaUrl,
    this.criadoEm,
    this.nomeColaborador,
    this.matriculaColaborador,
    this.setorColaborador,
  });

  factory FisioterapiaCaso.fromJson(Map<String, dynamic> json) {
    final colab = json['colaboradores'] as Map<String, dynamic>?;
    return FisioterapiaCaso(
      id: json['id'] as int,
      colaboradorId: json['colaborador_id'] as int,
      fisioterapeutaId: json['fisioterapeuta_id'] as int?,
      patologia: json['patologia'] ?? '',
      justificativa: json['justificativa'] ?? '',
      status: json['status'] ?? 'em_espera',
      sessoesPrevistas: json['sessoes_previstas'] as int?,
      motivoEncerramentoSesmt: json['motivo_encerramento_sesmt'],
      dataAlta:
          json['data_alta'] != null ? DateTime.parse(json['data_alta']) : null,
      assinaturaAltaUrl: json['assinatura_alta_url'],
      criadoEm:
          json['criado_em'] != null ? DateTime.parse(json['criado_em']) : null,
      nomeColaborador: colab?['nome'],
      matriculaColaborador: colab?['matricula'],
      setorColaborador: colab?['setor'],
    );
  }

  bool get emEspera => status == 'em_espera';
  bool get ativo => status == 'ativo';
  bool get alta => status == 'alta';
  bool get encerradoSesmt => status == 'encerrado_sesmt';
}

class FisioterapiaSessao {
  final int id;
  final int casoId;
  final DateTime data;
  final String horario;
  final String status; // 'AGENDADO' | 'VEIO' | 'NAO_VEIO' | 'CANCELADO'
  final String? evolucao;

  FisioterapiaSessao({
    required this.id,
    required this.casoId,
    required this.data,
    required this.horario,
    this.status = 'AGENDADO',
    this.evolucao,
  });

  factory FisioterapiaSessao.fromJson(Map<String, dynamic> json) =>
      FisioterapiaSessao(
        id: json['id'] as int,
        casoId: json['caso_id'] as int,
        data: DateTime.parse(json['data']),
        horario: (json['horario'] as String).substring(0, 5),
        status: json['status'] ?? 'AGENDADO',
        evolucao: json['evolucao'],
      );
}

class FisioterapiaExercicio {
  final int id;
  final int casoId;
  final String descricao;
  final String? frequencia;

  FisioterapiaExercicio({
    required this.id,
    required this.casoId,
    required this.descricao,
    this.frequencia,
  });

  factory FisioterapiaExercicio.fromJson(Map<String, dynamic> json) =>
      FisioterapiaExercicio(
        id: json['id'] as int,
        casoId: json['caso_id'] as int,
        descricao: json['descricao'] ?? '',
        frequencia: json['frequencia'],
      );
}
