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
  /// Código de centro de custo de 10 dígitos (ex: "2001401016").
  /// Estrutura: [4 filial][2 segmento][4 setor]
  final String? codCentro;
  final String? empresa;
  final bool ehGestor;
  /// Código da filial vindo direto do TOTVS RM (campo `branch`) — mais
  /// confiável que derivar de codCentro.
  final String? branch;

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
    this.codCentro,
    this.empresa,
    this.ehGestor = false,
    this.branch,
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
      codCentro: json['cod_centro'],
      empresa: json['empresa'],
      ehGestor: json['eh_gestor'] as bool? ?? false,
      branch: json['branch'],
    );
  }

  /// Código da filial: primeiros 4 dígitos do cod_centro.
  String? get codFilial =>
      (codCentro != null && codCentro!.length == 10) ? codCentro!.substring(0, 4) : null;

  /// Filial efetiva do colaborador: prioriza `branch` (vem direto do TOTVS
  /// RM), cai pra derivar de codCentro se `branch` não vier preenchido.
  String? get filialEfetiva => branch ?? codFilial;

  /// Código do segmento: primeiros 6 dígitos do cod_centro.
  String? get codSegmento =>
      (codCentro != null && codCentro!.length == 10) ? codCentro!.substring(0, 6) : null;

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