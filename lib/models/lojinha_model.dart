// ─── Produto ──────────────────────────────────────────────────────────────────

class LojinhaProdutoModel {
  final int id;
  final String material;
  final String descricao;
  final String unidadeVenda;
  final String? unidadeVisual;
  final double preco;
  final double estoque;
  final String? marca;
  final String? categoria;
  final String? linha;
  final String? grupo;
  final String? fotoUrl;
  final String? centro;
  final String? deposito;
  final List<int>? diasSemana;
  final int? limiteQtd;
  final String? periodoLimite;

  LojinhaProdutoModel({
    required this.id,
    required this.material,
    required this.descricao,
    required this.unidadeVenda,
    this.unidadeVisual,
    required this.preco,
    required this.estoque,
    this.marca,
    this.categoria,
    this.linha,
    this.grupo,
    this.fotoUrl,
    this.centro,
    this.deposito,
    this.diasSemana,
    this.limiteQtd,
    this.periodoLimite,
  });

  factory LojinhaProdutoModel.fromJson(Map<String, dynamic> j) =>
      LojinhaProdutoModel(
        id:            j['id'] as int,
        material:      j['material'] as String,
        descricao:     j['descricao'] as String,
        unidadeVenda:  j['unidade_venda'] as String,
        unidadeVisual: j['unidade_visual'] as String?,
        preco:         (j['preco'] as num).toDouble(),
        estoque:       (j['estoque'] as num).toDouble(),
        marca:         j['marca'] as String?,
        categoria:     j['categoria'] as String?,
        linha:         j['linha'] as String?,
        grupo:         j['grupo'] as String?,
        fotoUrl:       j['foto_url'] as String?,
        centro:        j['centro'] as String?,
        deposito:      j['deposito'] as String?,
        diasSemana:    (j['dias_semana'] as List?)?.cast<int>(),
        limiteQtd:     j['limite_qtd'] as int?,
        periodoLimite: j['periodo_limite'] as String?,
      );

  bool get disponivelHoje {
    if (diasSemana == null || diasSemana!.isEmpty) return true;
    return diasSemana!.contains(DateTime.now().weekday);
  }

  int limiteEfetivo(int estoqueVisivel) =>
      limiteQtd != null ? limiteQtd!.clamp(0, estoqueVisivel) : estoqueVisivel;
}

// ─── Resultado de pedido por centro ──────────────────────────────────────────

class LojinhaPedidoCentroResult {
  final String centro;
  final bool ok;
  final String retorno;
  final String? numeroPedido;
  final String? remessa;

  LojinhaPedidoCentroResult({
    required this.centro,
    required this.ok,
    required this.retorno,
    this.numeroPedido,
    this.remessa,
  });

  factory LojinhaPedidoCentroResult.fromJson(Map<String, dynamic> j) =>
      LojinhaPedidoCentroResult(
        centro:       j['centro'] as String,
        ok:           j['ok'] as bool,
        retorno:      j['retorno'] as String,
        numeroPedido: j['numeroPedido'] as String?,
        remessa:      j['remessa'] as String?,
      );
}

// ─── Carrinho ─────────────────────────────────────────────────────────────────

class CarrinhoItem {
  final LojinhaProdutoModel produto;
  int quantidade;

  CarrinhoItem({required this.produto, this.quantidade = 1});

  double get subtotal => produto.preco * quantidade;

  Map<String, dynamic> toSapItem() => {
        'produto':    produto.material.replaceAll(RegExp(r'^0+'), ''),
        'unidvenda':  produto.unidadeVenda,
        'quantidade': quantidade.toString(),
        'preco':      produto.preco.toStringAsFixed(2),
        // centro e deposito usados pela Edge Function para agrupar pedidos por centro;
        // são removidos antes do envio ao SAP
        'centro':     produto.centro ?? '',
        'deposito':   produto.deposito ?? '',
      };
}

// ─── Dados do Funcionário (SAP) ───────────────────────────────────────────────

class LojinhaFuncionarioModel {
  final double limiteTotal;
  final double limiteDisp;
  final String bloqueio;
  final String centro;
  final List<LojinhaPedidoResumoModel> pedidos;
  final String mensagem;

  LojinhaFuncionarioModel({
    required this.limiteTotal,
    required this.limiteDisp,
    required this.bloqueio,
    required this.centro,
    required this.pedidos,
    required this.mensagem,
  });

  bool get bloqueado => bloqueio.trim().isNotEmpty;
  double get limiteUsado => limiteTotal - limiteDisp;
  double get percentualUsado =>
      limiteTotal > 0 ? (limiteUsado / limiteTotal).clamp(0.0, 1.0) : 0.0;

  /// Centros cujos produtos este funcionário pode ver.
  List<String> get centrosVisiveis {
    switch (centro) {
      case '2100': return ['2100', '2014'];
      case '2002': return ['2002', '2015'];
      default:     return [centro];
    }
  }

  factory LojinhaFuncionarioModel.fromJson(Map<String, dynamic> j) {
    final pedidosJson = (j['PEDIDOS'] as List? ?? []);
    return LojinhaFuncionarioModel(
      limiteTotal: _parseDouble(j['LIMITETOTAL']),
      limiteDisp:  _parseDouble(j['LIMITEDISP']),
      bloqueio:    (j['BLOQUEIO'] as String? ?? '').trim(),
      centro:      (j['CENTRO']   as String? ?? '').trim(),
      mensagem:    (j['MENSAGEM'] as String? ?? '').trim(),
      pedidos:     pedidosJson
          .map((e) => LojinhaPedidoResumoModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    return double.tryParse(v.toString().trim()) ?? 0.0;
  }
}

// ─── Resumo de Pedido (lista) ─────────────────────────────────────────────────

class LojinhaPedidoResumoModel {
  final String ordem;
  final String criacao; // yyyyMMdd
  final double valorTotal;
  final String situacao; // VIGENTE | FUTURO | ...
  final String status;   // "Liberado para faturamento" etc.

  LojinhaPedidoResumoModel({
    required this.ordem,
    required this.criacao,
    required this.valorTotal,
    required this.situacao,
    required this.status,
  });

  /// Formata data yyyyMMdd → dd/MM/yyyy
  String get criacaoFormatada {
    if (criacao.length != 8) return criacao;
    return '${criacao.substring(6)}/${criacao.substring(4, 6)}/${criacao.substring(0, 4)}';
  }

  bool get isVigente => situacao.toUpperCase() == 'VIGENTE';
  bool get isFuturo  => situacao.toUpperCase() == 'FUTURO';

  /// Sexta-feira de entrega com base na data de criação.
  /// Ciclo: seg/ter/qua → sexta desta semana | qui/sex/sáb/dom → sexta da próxima semana.
  DateTime get dataEntrega {
    if (criacao.length != 8) return DateTime.now();
    final d = DateTime(
      int.parse(criacao.substring(0, 4)),
      int.parse(criacao.substring(4, 6)),
      int.parse(criacao.substring(6, 8)),
    );
    // weekday: Mon=1 … Sun=7
    const diasMap = {1: 4, 2: 3, 3: 2, 4: 8, 5: 7, 6: 6, 7: 5};
    return d.add(Duration(days: diasMap[d.weekday]!));
  }

  /// Tag de entrega a exibir nos pedidos ativos. Retorna null se não aplicável.
  String? get labelEntrega {
    if (!isVigente && !isFuturo) return null;
    final entrega = DateTime(dataEntrega.year, dataEntrega.month, dataEntrega.day);
    final hoje = DateTime.now();
    final hojeDate = DateTime(hoje.year, hoje.month, hoje.day);
    if (entrega.isBefore(hojeDate)) return null;

    // Próxima sexta a partir de hoje (mesma lógica)
    const diasMap = {1: 4, 2: 3, 3: 2, 4: 8, 5: 7, 6: 6, 7: 5};
    final proximaSexta = hojeDate.add(Duration(days: diasMap[hojeDate.weekday]!));

    if (entrega == proximaSexta) return 'Chega nessa sexta';
    if (entrega == proximaSexta.add(const Duration(days: 7))) return 'Chega na próxima sexta';
    final dia = entrega.day.toString().padLeft(2, '0');
    final mes = entrega.month.toString().padLeft(2, '0');
    return 'Chega em $dia/$mes';
  }

  factory LojinhaPedidoResumoModel.fromJson(Map<String, dynamic> j) =>
      LojinhaPedidoResumoModel(
        ordem:      (j['ORDEM'] as String).trim(),
        criacao:    (j['CRIACAO'] as String).trim(),
        valorTotal: double.tryParse((j['VALORTOTAL'] as String).trim()) ?? 0.0,
        situacao:   (j['SITUACAO'] as String? ?? '').trim(),
        status:     (j['STATUS'] as String? ?? '').trim(),
      );
}

// ─── Detalhe de Pedido ────────────────────────────────────────────────────────

class LojinhaPedidoDetalheModel {
  final String ordem;
  final String pedidoExterno;
  final String plataforma;
  final String dtFaturamento; // yyyyMMdd
  final List<LojinhaPedidoItemModel> itens;

  LojinhaPedidoDetalheModel({
    required this.ordem,
    required this.pedidoExterno,
    required this.plataforma,
    required this.dtFaturamento,
    required this.itens,
  });

  String get dtFaturamentoFormatada {
    if (dtFaturamento.length != 8) return dtFaturamento;
    return '${dtFaturamento.substring(6)}/${dtFaturamento.substring(4, 6)}/${dtFaturamento.substring(0, 4)}';
  }

  factory LojinhaPedidoDetalheModel.fromJson(Map<String, dynamic> j) {
    final itensJson = (j['ITENS'] as List? ?? []);
    return LojinhaPedidoDetalheModel(
      ordem:          (j['ORDEM'] as String).trim(),
      pedidoExterno:  (j['PEDIDO_EXTERNO'] as String? ?? '').trim(),
      plataforma:     (j['PLATAFORMA'] as String? ?? '').trim(),
      dtFaturamento:  (j['DT_FATURAMENTO'] as String? ?? '').trim(),
      itens:          itensJson
          .map((e) => LojinhaPedidoItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class LojinhaPedidoItemModel {
  final String item;
  final String material;
  final String denominacao;
  final double quantidade;
  final String unidadeVenda;
  final double valorUnitario;
  final String recusa;
  final String notificacoes;

  LojinhaPedidoItemModel({
    required this.item,
    required this.material,
    required this.denominacao,
    required this.quantidade,
    required this.unidadeVenda,
    required this.valorUnitario,
    required this.recusa,
    required this.notificacoes,
  });

  double get valorTotal => quantidade * valorUnitario;

  factory LojinhaPedidoItemModel.fromJson(Map<String, dynamic> j) =>
      LojinhaPedidoItemModel(
        item:          (j['ITEM'] as String).trim(),
        material:      (j['MATERIAL'] as String).trim(),
        denominacao:   (j['DENOMINACAO'] as String).trim(),
        quantidade:    double.tryParse((j['QUANTIDADE'] as String).trim()) ?? 0,
        unidadeVenda:  (j['UNIDADE_VENDA'] as String).trim(),
        valorUnitario: double.tryParse((j['VALOR_UNITARIO'] as String).trim()) ?? 0,
        recusa:        (j['RECUSA'] as String? ?? '').trim(),
        notificacoes:  (j['NOTIFICACOES'] as String? ?? '').trim(),
      );
}