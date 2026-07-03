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
  final int? periodoDiasGlobal;

  const LojinhaCarrinhoScreen({
    super.key,
    required this.carrinho,
    required this.onAdicionar,
    required this.onRemover,
    required this.onFinalizar,
    required this.enviando,
    this.itensRestantes,
    this.limiteQtdGlobal,
    this.periodoDiasGlobal,
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
  bool get _ultrapassaLimite =>
      widget.limiteQtdGlobal != null &&
      _totalItens > (widget.itensRestantes ?? widget.limiteQtdGlobal!);

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
      _estoqueVisivel = result;
      _carregandoEstoque = false;
    });
  }

  int _disponivelPara(LojinhaProdutoModel p) {
    if (p.isExclusivo) return p.limiteEfetivo(p.estoque.toInt());
    final estoque = _estoqueVisivel[p.material] ?? p.estoque.toInt();
    return p.limiteEfetivo(estoque);
  }

  String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  void _adicionar(LojinhaProdutoModel p) {
    widget.onAdicionar(p);
    setState(() {});
  }

  void _remover(LojinhaProdutoModel p) {
    widget.onRemover(p);
    setState(() {});
  }

  Future<void> _confirmarPedido() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(28),
        content: Column(
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
            Text(
              '$_totalItens ${_totalItens == 1 ? 'item' : 'itens'} · ${_moeda(_total)}',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.cinzaTexto,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Deseja finalizar o pedido?',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.cinzaTexto,
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
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.red.shade700, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Carrinho ultrapassa o limite de ${widget.limiteQtdGlobal} itens a cada ${widget.periodoDiasGlobal} dias.',
                                style: GoogleFonts.poppins(
                                    fontSize: 11, color: Colors.red.shade700),
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
                        onPressed: (widget.enviando || _ultrapassaLimite) ? null : _confirmarPedido,
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
                  ? Image.network(
                      p.fotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _semFoto(),
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

  const _BotaoQtd({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.laranja.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: AppColors.laranja),
      ),
    );
  }
}
