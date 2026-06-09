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
      };
}

// ─── Dados do Funcionário (SAP) ───────────────────────────────────────────────

class LojinhaFuncionarioModel {
  final double limiteTotal;
  final double limiteDisp;
  final String bloqueio;
  final List<LojinhaPedidoResumoModel> pedidos;
  final String mensagem;

  LojinhaFuncionarioModel({
    required this.limiteTotal,
    required this.limiteDisp,
    required this.bloqueio,
    required this.pedidos,
    required this.mensagem,
  });

  bool get bloqueado => bloqueio.trim().isNotEmpty;
  double get limiteUsado => limiteTotal - limiteDisp;
  double get percentualUsado =>
      limiteTotal > 0 ? (limiteUsado / limiteTotal).clamp(0.0, 1.0) : 0.0;

  factory LojinhaFuncionarioModel.fromJson(Map<String, dynamic> j) {
    final pedidosJson = (j['PEDIDOS'] as List? ?? []);
    return LojinhaFuncionarioModel(
      limiteTotal: _parseDouble(j['LIMITETOTAL']),
      limiteDisp:  _parseDouble(j['LIMITEDISP']),
      bloqueio:    (j['BLOQUEIO'] as String? ?? '').trim(),
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

  LojinhaPedidoResumoModel({
    required this.ordem,
    required this.criacao,
    required this.valorTotal,
  });

  /// Formata data yyyyMMdd → dd/MM/yyyy
  String get criacaoFormatada {
    if (criacao.length != 8) return criacao;
    return '${criacao.substring(6)}/${criacao.substring(4, 6)}/${criacao.substring(0, 4)}';
  }

  factory LojinhaPedidoResumoModel.fromJson(Map<String, dynamic> j) =>
      LojinhaPedidoResumoModel(
        ordem:      (j['ORDEM'] as String).trim(),
        criacao:    (j['CRIACAO'] as String).trim(),
        valorTotal: double.tryParse((j['VALORTOTAL'] as String).trim()) ?? 0.0,
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