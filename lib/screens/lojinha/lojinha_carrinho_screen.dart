import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/lojinha_model.dart';
import '../../services/api_service.dart';

class LojinhaCarrinhoScreen extends StatefulWidget {
  final Map<int, CarrinhoItem> carrinho;
  final void Function(LojinhaProdutoModel) onAdicionar;
  final void Function(LojinhaProdutoModel) onRemover;
  final Future<void> Function() onFinalizar;
  final bool enviando;
  final int? itensRestantes;
  final int? limiteQtdGlobal;
  /// Limite de itens separado para EXCLUSIVOS (`limite_qtd_exclusivo`).
  final int? itensRestantesExclusivo;
  final int? limiteQtdExclusivo;
  final int? periodoDiasGlobal;
  /// Estoque visível (material → qtd) já carregado na grade de produtos —
  /// fallback enquanto/caso a consulta do carrinho não responda.
  final Map<String, int> estoque;
  /// Limite em R$ disponível (já descontadas as compras exclusivas do
  /// ciclo); null = dados do funcionário indisponíveis, não bloqueia.
  final double? limiteDisp;
  final bool bloqueado;
  /// Já usou o pedido regular (SAP) / exclusivo do período.
  final bool sapEsgotado;
  final bool exclusivoEsgotado;

  const LojinhaCarrinhoScreen({
    super.key,
    required this.carrinho,
    required this.onAdicionar,
    required this.onRemover,
    required this.onFinalizar,
    required this.enviando,
    this.itensRestantes,
    this.limiteQtdGlobal,
    this.itensRestantesExclusivo,
    this.limiteQtdExclusivo,
    this.periodoDiasGlobal,
    this.estoque = const {},
    this.limiteDisp,
    this.bloqueado = false,
    this.sapEsgotado = false,
    this.exclusivoEsgotado = false,
  });

  @override
  State<LojinhaCarrinhoScreen> createState() => _LojinhaCarrinhoScreenState();
}

class _LojinhaCarrinhoScreenState extends State<LojinhaCarrinhoScreen> {
  final _api = ApiService();

  // material (com zeros) → estoque visível
  Map<String, int> _estoqueVisivel = {};
  bool _carregandoEstoque = true;

  List<CarrinhoItem> get _itens => widget.carrinho.values.toList();
  double get _total => _itens.fold(0.0, (s, i) => s + i.subtotal);
  int get _totalItens => _itens.fold(0, (s, i) => s + i.quantidade);

  /// Itens no carrinho do mesmo tipo (SAP ou exclusivo) que [exclusivo].
  int _itensDoTipo(bool exclusivo) => _itens
      .where((i) => i.produto.isExclusivo == exclusivo)
      .fold(0, (s, i) => s + i.quantidade);

  /// Limite de itens do período, validado por tipo (SAP x exclusivo).
  bool get _ultrapassaLimiteItens =>
      (widget.limiteQtdGlobal != null &&
          _itensDoTipo(false) >
              (widget.itensRestantes ?? widget.limiteQtdGlobal!)) ||
      (widget.limiteQtdExclusivo != null &&
          _itensDoTipo(true) >
              (widget.itensRestantesExclusivo ?? widget.limiteQtdExclusivo!));

  /// Limite em R$ disponível.
  bool get _ultrapassaValor =>
      widget.limiteDisp != null &&
      widget.limiteDisp! > 0 &&
      _total > widget.limiteDisp!;

  bool get _temItemRegular => _itens.any((i) => !i.produto.isExclusivo);
  bool get _temItemExclusivo => _itens.any((i) => i.produto.isExclusivo);

  /// Limite de PEDIDOS (não itens) por tipo — revalidado aqui no carrinho.
  bool get _ultrapassaLimitePedidos =>
      (widget.sapEsgotado && _temItemRegular) ||
      (widget.exclusivoEsgotado && _temItemExclusivo);

  bool get _ultrapassaLimite =>
      _ultrapassaValor || _ultrapassaLimiteItens || _ultrapassaLimitePedidos;

  List<String> get _avisos => [
        if (_ultrapassaValor)
          'Ultrapassa o limite disponível de ${_moeda(widget.limiteDisp!)}',
        if (_ultrapassaLimiteItens)
          'Limite de itens do período: ${widget.itensRestantes ?? widget.limiteQtdGlobal} Pole'
              '${widget.limiteQtdExclusivo != null ? " e ${widget.itensRestantesExclusivo ?? widget.limiteQtdExclusivo} ovos" : ""}, a cada ${widget.periodoDiasGlobal} dias. Ajuste o carrinho.',
        if (_ultrapassaLimitePedidos)
          widget.sapEsgotado && _temItemRegular
              ? 'Você já usou seu pedido de produtos Pole do período. Remova os produtos Pole do carrinho ou tente de novo mais tarde.'
              : 'Você já usou seu pedido de produtos ovos do período. Remova os produtos ovos do carrinho ou tente de novo mais tarde.',
      ];

  @override
  void initState() {
    super.initState();
    _buscarEstoque();
  }

  Future<void> _buscarEstoque() async {
    // Exclusivos não existem no SAP (não têm centro/deposito válidos), então
    // não fazem parte dessa checagem — usam sempre o próprio campo `estoque`.
    final produtos =
        _itens.map((i) => i.produto).where((p) => !p.isExclusivo).toList();
    if (produtos.isEmpty) {
      setState(() => _carregandoEstoque = false);
      return;
    }
    final result = await _api.buscarEstoqueVisivel(produtos);
    if (!mounted) return;
    setState(() {
      // Falha na consulta devolve vazio: mantém o último valor conhecido.
      if (result.isNotEmpty) _estoqueVisivel = result;
      _carregandoEstoque = false;
    });
  }

  int _disponivelPara(LojinhaProdutoModel p) {
    if (p.isExclusivo) return p.limiteEfetivo(p.estoque.toInt());
    final semZeros = p.material.replaceAll(RegExp(r'^0+'), '');
    final estoque = _estoqueVisivel[p.material] ??
        _estoqueVisivel[semZeros] ??
        widget.estoque[p.material] ??
        widget.estoque[semZeros] ??
        p.estoque.toInt();
    return p.limiteEfetivo(estoque);
  }

  /// Reconsulta o estoque bem na hora de fechar o pedido e ajusta o carrinho
  /// se alguém levou o produto entre o momento em que ele foi adicionado e
  /// agora. Sem essa trava, dois colaboradores disputando a última unidade
  /// só descobrem o problema quando o SAP rejeita o pedido com um erro cru.
  /// Retorna true se o carrinho teve que ser ajustado (e portanto não deve
  /// seguir direto pra confirmação).
  Future<bool> _revalidarEstoque() async {
    await _buscarEstoque();
    if (!mounted) return true;
    final ajustados = <String>[];
    final removidos = <String>[];
    for (final item in _itens) {
      final p = item.produto;
      final disponivel = _disponivelPara(p);
      final qtd = item.quantidade;
      if (disponivel <= 0) {
        // Usa o callback do carrinho pra manter a sincronização com o servidor.
        for (var n = 0; n < qtd; n++) {
          widget.onRemover(p);
        }
        removidos.add(p.descricao);
      } else if (qtd > disponivel) {
        for (var n = 0; n < qtd - disponivel; n++) {
          widget.onRemover(p);
        }
        ajustados.add(p.descricao);
      }
    }
    if (ajustados.isEmpty && removidos.isEmpty) return false;
    setState(() {});
    if (!mounted) return true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('O estoque mudou',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(
          [
            if (removidos.isNotEmpty)
              'Sem estoque, removido do carrinho: ${removidos.join(', ')}.',
            if (ajustados.isNotEmpty)
              'Quantidade ajustada pro que ainda tem disponível: ${ajustados.join(', ')}.',
          ].join('\n\n'),
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.laranja,
                foregroundColor: Colors.white),
            child: Text('Entendi', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    return true;
  }

  /// Compra feita de 21 do mês passado até 20 desse mês entra no desconto
  /// em folha do dia 5 do mês seguinte a esse fechamento. Vale pra qualquer
  /// produto da Lojinha (SAP ou exclusivo).
  static DateTime _dataDescontoFolha(DateTime data) {
    final fechamento = data.day <= 20
        ? DateTime(data.year, data.month)
        : DateTime(data.year, data.month + 1);
    return DateTime(fechamento.year, fechamento.month + 1, 5);
  }

  String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  void _adicionar(LojinhaProdutoModel p) {
    // Usa o mesmo número de estoque mostrado nessa tela (mais atualizado do
    // que o carregado na grade de produtos) — antes o "+" ignorava esse
    // valor e só era corrigido depois, pelo debounce de sincronização.
    final atual = widget.carrinho[p.id]?.quantidade ?? 0;
    if (atual >= _disponivelPara(p)) return;
    widget.onAdicionar(p);
    setState(() {});
  }

  void _remover(LojinhaProdutoModel p) {
    widget.onRemover(p);
    setState(() {});
  }

  Future<void> _confirmarPedido() async {
    if (_ultrapassaLimite ||
        widget.bloqueado ||
        _itens.isEmpty ||
        widget.enviando) {
      return;
    }

    // Revalida o estoque na hora de fechar; se algo mudou, mostra o aviso e
    // não segue direto pra confirmação.
    if (await _revalidarEstoque()) return;
    if (_itens.isEmpty || !mounted) return;

    final desconto = _dataDescontoFolha(DateTime.now());
    final dd = desconto.day.toString().padLeft(2, '0');
    final mm = desconto.month.toString().padLeft(2, '0');

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(28),
        content: SingleChildScrollView(
         child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.laranja.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shopping_bag_outlined,
                color: AppColors.laranja,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Confirmar pedido?',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 12),
            // Lista de itens do pedido
            ..._itens.map((i) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Icon(Icons.circle,
                            size: 5, color: AppColors.cinzaTexto),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${i.produto.descricao} × ${i.quantidade}',
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: AppColors.dark),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.laranja.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('Total a descontar em folha',
                            style: GoogleFonts.poppins(fontSize: 13)),
                      ),
                      Text(_moeda(_total),
                          style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.laranja)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Compras de 21 do mês passado a 20 desse mês saem no contracheque de $dd/$mm/${desconto.year}.',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.cinzaTexto),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.cinzaTexto,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.laranja,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      'Confirmar',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
         ),
        ),
      ),
    );

    if (confirmar == true && mounted) {
      Navigator.pop(context); // fecha a tela do carrinho
      await widget.onFinalizar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Fundo gradiente no topo
          Container(
            height: 160,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Carrinho',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '$_totalItens ${_totalItens == 1 ? 'item' : 'itens'}',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── Corpo ────────────────────────────────────────────────────
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: _itens.isEmpty
                        ? _vazio()
                        : _carregandoEstoque
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 20, 16, 140),
                                itemCount: _itens.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (_, i) => _CardItem(
                                  item: _itens[i],
                                  estoqueDisponivel:
                                      _disponivelPara(_itens[i].produto),
                                  onAdicionar: () =>
                                      _adicionar(_itens[i].produto),
                                  onRemover: () =>
                                      _remover(_itens[i].produto),
                                ),
                              ),
                  ),
                ),
              ],
            ),
          ),

          // ── Rodapé com total + botão ─────────────────────────────────────
          if (_itens.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.of(context).padding.bottom + 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: AppColors.cinzaTexto,
                          ),
                        ),
                        Text(
                          _moeda(_total),
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark,
                          ),
                        ),
                      ],
                    ),
                    if (_ultrapassaLimite) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.red.shade700, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final aviso in _avisos)
                                    Text(
                                      aviso,
                                      style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: Colors.red.shade700),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _ultrapassaLimite
                              ? Colors.grey.shade400
                              : AppColors.laranja,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                        ),
                        onPressed: (widget.enviando ||
                                _ultrapassaLimite ||
                                widget.bloqueado)
                            ? null
                            : _confirmarPedido,
                        child: widget.enviando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Finalizar pedido',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (widget.enviando)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _vazio() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.shopping_cart_outlined,
          size: 64,
          color: AppColors.cinzaTexto.withOpacity(0.3),
        ),
        const SizedBox(height: 12),
        Text(
          'Carrinho vazio',
          style: GoogleFonts.poppins(
            fontSize: 16,
            color: AppColors.cinzaTexto,
          ),
        ),
      ],
    ),
  );
}

// ── Card de item do carrinho ──────────────────────────────────────────────────

class _CardItem extends StatelessWidget {
  final CarrinhoItem item;
  final int estoqueDisponivel;
  final VoidCallback onAdicionar;
  final VoidCallback onRemover;

  const _CardItem({
    required this.item,
    required this.estoqueDisponivel,
    required this.onAdicionar,
    required this.onRemover,
  });

  String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    final p = item.produto;
    final temFoto = p.fotoUrl != null && p.fotoUrl!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Imagem
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 80,
              height: 80,
              child: temFoto
                  ? CachedNetworkImage(
                      imageUrl: p.fotoUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 160,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) => _semFoto(),
                      errorWidget: (_, __, ___) => _semFoto(),
                    )
                  : _semFoto(),
            ),
          ),

          const SizedBox(width: 14),

          // Informações
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.descricao,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.dark,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  estoqueDisponivel == 0
                      ? 'Sem estoque disponível'
                      : 'Disponível: $estoqueDisponivel ${p.unidadeVisual ?? p.unidadeVenda}',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: estoqueDisponivel == 0
                        ? Colors.red
                        : estoqueDisponivel <= 3
                            ? Colors.orange
                            : AppColors.cinzaTexto,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      _moeda(p.preco),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.cinzaTexto,
                      ),
                    ),
                    const Spacer(),
                    // Controle de quantidade
                    _BotaoQtd(
                      icon: Icons.remove,
                      onTap: onRemover,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '${item.quantidade}',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                    ),
                    _BotaoQtd(
                      icon: Icons.add,
                      onTap: onAdicionar,
                      enabled: item.quantidade < estoqueDisponivel,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Subtotal: ${_moeda(item.subtotal)}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.laranja,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _semFoto() => Container(
    color: const Color(0xFFF0F0F0),
    child: const Icon(
      Icons.image_not_supported_outlined,
      color: Colors.grey,
      size: 32,
    ),
  );
}

class _BotaoQtd extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  const _BotaoQtd({required this.icon, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final cor = enabled ? AppColors.laranja : AppColors.cinzaTexto;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: cor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: cor),
      ),
    );
  }
}
