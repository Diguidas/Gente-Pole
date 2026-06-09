import 'package:flutter/material.dart';
import 'package:gentepole/services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/lojinha_model.dart';
import 'dart:async';

class LojinhaScreen extends StatefulWidget {
  const LojinhaScreen({super.key});

  @override
  State<LojinhaScreen> createState() => _LojinhaScreenState();
}

class _LojinhaScreenState extends State<LojinhaScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();

  List<LojinhaProdutoModel> _todos = [];
  List<LojinhaProdutoModel> _filtrados = [];
  final Map<int, CarrinhoItem> _carrinho = {};

  String? _categoriaSelecionada; // null = todas
  bool _carregando = true;
  bool _enviando = false;

  // ── Ciclo de vida ────────────────────────────────────────────────────────────

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _carregarProdutos();
    _searchCtrl.addListener(_onSearchChanged); // <-- mudar nome do listener
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _aplicarFiltros();
    });
  }

  // ── Dados ────────────────────────────────────────────────────────────────────

  Future<void> _carregarProdutos() async {
    setState(() => _carregando = true);
    _todos = await _api.buscarProdutosLojinha();
    _aplicarFiltros();
    setState(() => _carregando = false);
  }

  void _aplicarFiltros() {
    final busca = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtrados = _todos.where((p) {
        final matchCategoria =
            _categoriaSelecionada == null ||
            p.categoria == _categoriaSelecionada;
        final matchBusca =
            busca.isEmpty ||
            p.descricao.toLowerCase().contains(busca) ||
            (p.marca?.toLowerCase().contains(busca) ?? false);
        return matchCategoria && matchBusca;
      }).toList();
    });
  }

  /// Lista de categorias únicas (com estoque > 0 já filtrado no buscarProdutosLojinha)
  List<String> get _categorias {
    final cats =
        _todos.map((p) => p.categoria).whereType<String>().toSet().toList()
          ..sort();
    return cats;
  }

  // ── Carrinho ─────────────────────────────────────────────────────────────────

  int get _totalItens => _carrinho.values.fold(0, (s, i) => s + i.quantidade);
  double get _totalValor =>
      _carrinho.values.fold(0.0, (s, i) => s + i.subtotal);

  void _adicionar(LojinhaProdutoModel p) {
    setState(() {
      if (_carrinho.containsKey(p.id)) {
        _carrinho[p.id]!.quantidade++;
      } else {
        _carrinho[p.id] = CarrinhoItem(produto: p);
      }
    });
  }

  void _remover(LojinhaProdutoModel p) {
    setState(() {
      if (!_carrinho.containsKey(p.id)) return;
      if (_carrinho[p.id]!.quantidade <= 1) {
        _carrinho.remove(p.id);
      } else {
        _carrinho[p.id]!.quantidade--;
      }
    });
  }

  // ── Pedido ───────────────────────────────────────────────────────────────────

  Future<void> _finalizarPedido() async {
    if (_carrinho.isEmpty || _enviando) return;
    Navigator.of(context).pop(); // fecha o bottom sheet
    setState(() => _enviando = true);

    final result = await _api.finalizarPedidoLojinha(
      itens: _carrinho.values.toList(),
    );

    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (result.ok) _carrinho.clear();
    });

    _mostrarResultado(result.ok, result.retorno, result.numeroPedido);
  }

  void _mostrarResultado(bool ok, String retorno, String? numeroPedido) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(28),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: (ok ? AppColors.laranja : Colors.red).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                ok ? Icons.check_circle_rounded : Icons.error_rounded,
                color: ok ? AppColors.laranja : Colors.red,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              ok ? 'Pedido realizado!' : 'Erro no pedido',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ok
                  ? 'Pedido nº ${numeroPedido ?? ""} enviado!\nRetirar na lojinha. 🎉'
                  : retorno,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.cinzaTexto,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ok ? AppColors.laranja : Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'OK',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirCarrinho() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CarrinhoSheet(
        carrinho: _carrinho,
        totalValor: _totalValor,
        onAdicionar: _adicionar,
        onRemover: _remover,
        onFinalizar: _finalizarPedido,
        enviando: _enviando,
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 220,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Header ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🛒 Lojinha',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Produtos exclusivos para você',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Botão carrinho
                      if (_totalItens > 0)
                        GestureDetector(
                          onTap: _abrirCarrinho,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.shopping_cart_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              Positioned(
                                top: -4,
                                right: -4,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$_totalItens',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.laranja,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ── Barra de busca ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Buscar produto...',
                        hintStyle: GoogleFonts.poppins(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Colors.white.withOpacity(0.7),
                          size: 20,
                        ),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _searchCtrl.clear();
                                  FocusScope.of(context).unfocus();
                                },
                                child: Icon(
                                  Icons.close_rounded,
                                  color: Colors.white.withOpacity(0.7),
                                  size: 18,
                                ),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Corpo ────────────────────────────────────────────────
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: _carregando
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            children: [
                              // ── Chips de categoria ───────────────────
                              if (_categorias.isNotEmpty)
                                _ChipsCategorias(
                                  categorias: _categorias,
                                  selecionada: _categoriaSelecionada,
                                  onSelecionar: (cat) {
                                    setState(() {
                                      _categoriaSelecionada =
                                          _categoriaSelecionada == cat
                                          ? null
                                          : cat;
                                    });
                                    _aplicarFiltros();
                                  },
                                ),

                              // ── Contador de resultados ───────────────
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  8,
                                  20,
                                  4,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      '${_filtrados.length} produto${_filtrados.length != 1 ? 's' : ''}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: AppColors.cinzaTexto,
                                      ),
                                    ),
                                    if (_categoriaSelecionada != null ||
                                        _searchCtrl.text.isNotEmpty) ...[
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: () {
                                          _searchCtrl.clear();
                                          setState(
                                            () => _categoriaSelecionada = null,
                                          );
                                          _aplicarFiltros();
                                        },
                                        child: Text(
                                          'Limpar filtros',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            color: AppColors.laranja,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // ── Grid de produtos ─────────────────────
                              Expanded(
                                child: _filtrados.isEmpty
                                    ? _vazio()
                                    : GridView.builder(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          8,
                                          16,
                                          100,
                                        ),
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 2,
                                              mainAxisSpacing: 14,
                                              crossAxisSpacing: 14,
                                              childAspectRatio: 0.72,
                                            ),
                                        itemCount: _filtrados.length,
                                        itemBuilder: (_, i) => _CardProduto(
                                          produto: _filtrados[i],
                                          quantidade:
                                              _carrinho[_filtrados[i].id]
                                                  ?.quantidade ??
                                              0,
                                          onAdicionar: () =>
                                              _adicionar(_filtrados[i]),
                                          onRemover: () =>
                                              _remover(_filtrados[i]),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),

          // ── FAB carrinho ─────────────────────────────────────────────
          if (_totalItens > 0 && !_enviando)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: GestureDetector(
                onTap: _abrirCarrinho,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientePrincipal,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.laranja.withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$_totalItens ${_totalItens == 1 ? 'item' : 'itens'}',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ver carrinho',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        'R\$ ${_totalValor.toStringAsFixed(2).replaceAll('.', ',')}',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Loading de envio
          if (_enviando)
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
          Icons.search_off_rounded,
          size: 56,
          color: AppColors.cinzaTexto.withOpacity(0.35),
        ),
        const SizedBox(height: 10),
        Text(
          'Nenhum produto encontrado',
          style: GoogleFonts.poppins(color: AppColors.cinzaTexto, fontSize: 14),
        ),
        if (_categoriaSelecionada != null || _searchCtrl.text.isNotEmpty)
          TextButton(
            onPressed: () {
              _searchCtrl.clear();
              setState(() => _categoriaSelecionada = null);
              _aplicarFiltros();
            },
            child: Text(
              'Limpar filtros',
              style: GoogleFonts.poppins(color: AppColors.laranja),
            ),
          ),
      ],
    ),
  );
}

// ── Chips de Categoria ───────────────────────────────────────────────────────

class _ChipsCategorias extends StatelessWidget {
  final List<String> categorias;
  final String? selecionada;
  final void Function(String) onSelecionar;

  const _ChipsCategorias({
    required this.categorias,
    required this.selecionada,
    required this.onSelecionar,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        scrollDirection: Axis.horizontal,
        itemCount: categorias.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = categorias[i];
          final ativo = selecionada == cat;
          return GestureDetector(
            onTap: () => onSelecionar(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: ativo ? AppColors.laranja : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: ativo
                      ? AppColors.laranja
                      : AppColors.cinzaTexto.withOpacity(0.25),
                ),
                boxShadow: ativo
                    ? [
                        BoxShadow(
                          color: AppColors.laranja.withOpacity(0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: Text(
                cat,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ativo ? Colors.white : AppColors.cinzaTexto,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Card de Produto ──────────────────────────────────────────────────────────

class _CardProduto extends StatelessWidget {
  final LojinhaProdutoModel produto;
  final int quantidade;
  final VoidCallback onAdicionar;
  final VoidCallback onRemover;

  const _CardProduto({
    required this.produto,
    required this.quantidade,
    required this.onAdicionar,
    required this.onRemover,
  });

  @override
  Widget build(BuildContext context) {
    final temNoCarrinho = quantidade > 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.laranja.withOpacity(temNoCarrinho ? 0.18 : 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: temNoCarrinho
            ? Border.all(color: AppColors.laranja.withOpacity(0.4), width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Área do ícone
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.laranja.withOpacity(0.07),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      Icons.inventory_2_outlined,
                      size: 44,
                      color: AppColors.laranja.withOpacity(0.4),
                    ),
                  ),
                  // Badge "Últimas unidades"
                  if (produto.estoque > 0 && produto.estoque <= 3)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Últimas unidades',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Infos
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Categoria / linha como label
                if (produto.categoria != null)
                  Text(
                    produto.categoria!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      color: AppColors.laranja,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  produto.descricao,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.dark,
                    height: 1.3,
                  ),
                ),
                if (produto.marca != null)
                  Text(
                    produto.marca!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: AppColors.cinzaTexto,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  'R\$ ${produto.preco.toStringAsFixed(2).replaceAll('.', ',')}',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.laranja,
                  ),
                ),
                const SizedBox(height: 8),

                // Controle de quantidade
                temNoCarrinho
                    ? Row(
                        children: [
                          _BotaoQtd(
                            icone: Icons.remove,
                            onTap: onRemover,
                            cor: AppColors.laranja,
                          ),
                          Expanded(
                            child: Text(
                              '$quantidade',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: AppColors.dark,
                              ),
                            ),
                          ),
                          _BotaoQtd(
                            icone: Icons.add,
                            onTap: onAdicionar,
                            cor: AppColors.laranja,
                          ),
                        ],
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: onAdicionar,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.laranja,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.add_shopping_cart_rounded,
                                  color: Colors.white,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Adicionar',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
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
}

class _BotaoQtd extends StatelessWidget {
  final IconData icone;
  final VoidCallback onTap;
  final Color cor;
  const _BotaoQtd({
    required this.icone,
    required this.onTap,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: cor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icone, size: 16, color: cor),
      ),
    );
  }
}

// ── Bottom Sheet do Carrinho ─────────────────────────────────────────────────

class _CarrinhoSheet extends StatelessWidget {
  final Map<int, CarrinhoItem> carrinho;
  final double totalValor;
  final void Function(LojinhaProdutoModel) onAdicionar;
  final void Function(LojinhaProdutoModel) onRemover;
  final VoidCallback onFinalizar;
  final bool enviando;

  const _CarrinhoSheet({
    required this.carrinho,
    required this.totalValor,
    required this.onAdicionar,
    required this.onRemover,
    required this.onFinalizar,
    required this.enviando,
  });

  @override
  Widget build(BuildContext context) {
    final itens = carrinho.values.toList();
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Text(
                  'Seu carrinho',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${itens.length} ${itens.length == 1 ? 'item' : 'itens'}',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.cinzaTexto,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.38,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: itens.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final item = itens[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.laranja.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.inventory_2_outlined,
                          color: AppColors.laranja,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.produto.descricao,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'R\$ ${item.produto.preco.toStringAsFixed(2).replaceAll('.', ',')} · ${item.subtotal.toStringAsFixed(2).replaceAll('.', ',')} total',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: AppColors.cinzaTexto,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          _BotaoQtd(
                            icone: Icons.remove,
                            onTap: () => onRemover(item.produto),
                            cor: AppColors.laranja,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              '${item.quantidade}',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          _BotaoQtd(
                            icone: Icons.add,
                            onTap: () => onAdicionar(item.produto),
                            cor: AppColors.laranja,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: GoogleFonts.poppins(
                          color: AppColors.cinzaTexto,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'R\$ ${totalValor.toStringAsFixed(2).replaceAll('.', ',')}',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.dark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.laranja,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: enviando ? null : onFinalizar,
                      child: enviando
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
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
        ],
      ),
    );
  }
}
