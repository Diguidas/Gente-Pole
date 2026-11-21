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
  /// Nome que gosta de ser chamado (opcional).
  final String? apelido;
  final String? clienteSap;
  /// Código de centro de custo de 10 dígitos (ex: "2001401016").
  /// Estrutura: [4 filial][2 segmento][4 setor]
  final String? codCentro;
  final String? empresa;
  final bool ehGestor;
  /// Código da filial vindo direto do TOTVS RM (campo `branch`) — mais
  /// confiável que derivar de codCentro.
  final String? branch;
  /// Só vem preenchido como true no picker de substituição da abertura de
  /// vaga (demitidos nunca aparecem nas demais listas).
  final bool demitido;
  /// Veio só pelo par (setor + função) de requisitante de vaga: na
  /// substituição só vale se o cargo bater com a função do template.
  final bool origemRequisitante;

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
    this.fotoUrl, this.apelido, this.clienteSap,
    this.codCentro,
    this.empresa,
    this.ehGestor = false,
    this.branch,
    this.demitido = false,
    this.origemRequisitante = false,
  });

  /// Cópia com a data de nascimento preenchida (ela fica numa tabela privada e
  /// é buscada à parte, pelo servidor).
  ColaboradorModel comNascimento(String? nascimento) => ColaboradorModel(
        id: id,
        matricula: matricula,
        nome: nome,
        setor: setor,
        cargo: cargo,
        cpf: cpf,
        dataNascimento: nascimento ?? dataNascimento,
        dataAdmissao: dataAdmissao,
        supervisorId: supervisorId,
        fotoUrl: fotoUrl,
        apelido: apelido,
        clienteSap: clienteSap,
        codCentro: codCentro,
        empresa: empresa,
        ehGestor: ehGestor,
        branch: branch,
        demitido: demitido,
        origemRequisitante: origemRequisitante,
      );

  /// Cópia com o CPF preenchido (a coluna é privada: o app lê o do próprio pelo servidor).
  ColaboradorModel comCpf(String? novoCpf) => ColaboradorModel(
        id: id,
        matricula: matricula,
        nome: nome,
        setor: setor,
        cargo: cargo,
        cpf: novoCpf ?? cpf,
        dataNascimento: dataNascimento,
        dataAdmissao: dataAdmissao,
        supervisorId: supervisorId,
        fotoUrl: fotoUrl,
        apelido: apelido,
        clienteSap: clienteSap,
        codCentro: codCentro,
        empresa: empresa,
        ehGestor: ehGestor,
        branch: branch,
        demitido: demitido,
        origemRequisitante: origemRequisitante,
      );

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
      apelido: json['apelido'],
      clienteSap: json['cliente_sap'],
      codCentro: json['cod_centro'],
      empresa: json['empresa'],
      ehGestor: json['eh_gestor'] as bool? ?? false,
      branch: json['branch'],
      demitido: json['demitido'] as bool? ?? false,
      origemRequisitante: json['_origem_requisitante'] as bool? ?? false,
    );
  }

  /// Código da filial: primeiros 4 dígitos do cod_centro.
  String? get codFilial =>
      (codCentro != null && codCentro!.length == 10) ? codCentro!.substring(0, 4) : null;

  /// Branch cru: `branch` (TOTVS RM) ou, se vazio, derivado do codCentro.
  /// Use para o que é código puro (ex.: centro SAP). Para identificar a filial
  /// use [filialEfetiva], que considera a empresa.
  String? get branchEfetivo {
    final b = (branch ?? '').trim();
    return b.isNotEmpty ? b : codFilial;
  }

  /// Chave da filial: o `branch` só é único dentro de cada empresa (a filial
  /// 1 existe nas empresas 5, 9 e 10). Empresa 5 (ou vazia) -> 'branch';
  /// demais -> 'empresa:branch' (ex.: '10:1'). Mesma chave de hierarquia_nomes.
  String? get filialEfetiva {
    final base = branchEfetivo;
    if (base == null) return null;
    final e = (empresa ?? '').trim();
    return (e.isEmpty || e == '5') ? base : '$e:$base';
  }

  /// Código do segmento: primeiros 6 dígitos do cod_centro.
  String? get codSegmento =>
      (codCentro != null && codCentro!.length == 10) ? codCentro!.substring(0, 6) : null;

  /// Nome de exibição curto: o apelido ("nome que gosta de ser chamado")
  /// quando existe; senão o primeiro nome.
  String get primeiroNome => (apelido != null && apelido!.trim().isNotEmpty)
      ? apelido!.trim()
      : nome.split(' ').first;

  /// Anos completos de empresa, a partir de [dataAdmissao] (mesma regra do painel web).
  int? get anosDeEmpresa {
    if (dataAdmissao == null) return null;
    final d = DateTime.tryParse(dataAdmissao!);
    if (d == null) return null;
    final now = DateTime.now();
    var anos = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) anos--;
    return anos < 0 ? 0 : anos;
  }

  /// Formata data de admissão para exibição (yyyy-mm-dd → dd/mm/yyyy)
  String? get dataAdmissaoFormatada {
    if (dataAdmissao == null) return null;
    final parts = dataAdmissao!.split('-');
    if (parts.length != 3) return dataAdmissao;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }
}