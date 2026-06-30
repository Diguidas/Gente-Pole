import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/lojinha_model.dart';
import '../../services/api_service.dart';
import 'lojinha_carrinho_screen.dart';
import 'lojinha_pedido_detalhe_screen.dart';
import 'dart:async';

class LojinhaProdutosScreen extends StatefulWidget {
  final LojinhaFuncionarioModel? dadosFuncionario;
  final Future<void> Function() onPedidoCriado;

  const LojinhaProdutosScreen({
    super.key,
    required this.dadosFuncionario,
    required this.onPedidoCriado,
  });

  @override
  State<LojinhaProdutosScreen> createState() => _LojinhaProdutosScreenState();
}

class _LojinhaProdutosScreenState extends State<LojinhaProdutosScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  List<LojinhaProdutoModel> _todos = [];
  List<LojinhaProdutoModel> _filtrados = [];
  final Map<int, CarrinhoItem> _carrinho = {};
  final Map<int, Timer> _cartTimers = {};

  String? _marcaSel;
  String? _categoriaSel;
  String? _linhaSel;
  String? _grupoSel;

  bool _carregando = true;
  bool _enviando = false;

  int? _limiteQtdGlobal;
  int? _periodoDiasGlobal;
  int _comprasRecentes = 0;

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
    for (final t in _cartTimers.values) t.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _aplicarFiltros();
    });
  }

  // ── Dados ──────────────────────────────────────────────────────────────────

  Future<void> _carregarProdutos() async {
    setState(() => _carregando = true);
    final colabId = _api.colaboradorAtual?.matricula ?? '';
    final results = await Future.wait([
      _api.buscarProdutosLojinha(centros: widget.dadosFuncionario?.centrosVisiveis ?? []),
      _api.buscarConfigLojinha(),
      _api.buscarExclusivosLojinha(),
    ]);
    final regulares = results[0] as List<LojinhaProdutoModel>;
    final exclusivos = results[2] as List<LojinhaProdutoModel>;
    _todos = [...exclusivos, ...regulares];
    final config = results[1] as Map<String, dynamic>;
    final limiteQtd = config['limite_qtd'] as int?;
    final periodoDias = config['periodo_dias'] as int?;
    int comprasRecentes = 0;
    if (limiteQtd != null && periodoDias != null && colabId.isNotEmpty) {
      comprasRecentes = await _api.buscarComprasRecentesColab(colabId, periodoDias);
    }
    setState(() {
      _limiteQtdGlobal = limiteQtd;
      _periodoDiasGlobal = periodoDias;
      _comprasRecentes = comprasRecentes;
      _carregando = false;
    });
    _aplicarFiltros();
  }

  int get _totalItensCarrinho => _carrinho.values.fold(0, (s, i) => s + i.quantidade);
  int get _itensRestantes {
    if (_limiteQtdGlobal == null) return 999;
    return (_limiteQtdGlobal! - _comprasRecentes).clamp(0, _limiteQtdGlobal!);
  }
  bool get _limiteAtingido => _limiteQtdGlobal != null && _itensRestantes <= 0;

  void _aplicarFiltros() {
    final busca = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtrados = _todos.where((p) {
        if (!p.disponivelHoje) return false;
        if (_marcaSel != null && p.marca != _marcaSel) return false;
        if (_categoriaSel != null && p.categoria != _categoriaSel) return false;
        if (_linhaSel != null && p.linha != _linhaSel) return false;
        if (_grupoSel != null && p.grupo != _grupoSel) return false;
        if (busca.isNotEmpty &&
            !p.descricao.toLowerCase().contains(busca) &&
            !(p.marca?.toLowerCase().contains(busca) ?? false))
          return false;
        return true;
      }).toList();
    });
  }

  void _limparFiltros() {
    _searchCtrl.clear();
    setState(() {
      _marcaSel = null;
      _categoriaSel = null;
      _linhaSel = null;
      _grupoSel = null;
    });
    _aplicarFiltros();
  }

  bool get _temFiltroAtivo =>
      _marcaSel != null ||
      _categoriaSel != null ||
      _linhaSel != null ||
      _grupoSel != null ||
      _searchCtrl.text.isNotEmpty;

  /// Valores únicos de um campo — apenas dos produtos com estoque (já em _todos)
  /// e respeitando os filtros superiores da hierarquia
  List<String> _valoresUnicos(
    String? Function(LojinhaProdutoModel) campo, {
    Map<String, String?> filtrosSuperior = const {},
  }) {
    return _todos
        .where((p) {
          for (final entry in filtrosSuperior.entries) {
            if (entry.value == null) continue;
            switch (entry.key) {
              case 'marca':
                if (p.marca != entry.value) return false;
              case 'categoria':
                if (p.categoria != entry.value) return false;
              case 'linha':
                if (p.linha != entry.value) return false;
            }
          }
          return true;
        })
        .map(campo)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
  }

  // ── Carrinho ───────────────────────────────────────────────────────────────

  int get _totalItens => _carrinho.values.fold(0, (s, i) => s + i.quantidade);
  double get _totalValor =>
      _carrinho.values.fold(0.0, (s, i) => s + i.subtotal);

  void _adicionar(LojinhaProdutoModel p) {
    final atual = _carrinho[p.id]?.quantidade ?? 0;
    final limite = p.limiteEfetivo(p.estoque.toInt());
    if (atual >= limite) return;
    if (_limiteQtdGlobal != null && _totalItensCarrinho >= _itensRestantes) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Limite de $_limiteQtdGlobal item${_limiteQtdGlobal != 1 ? 'ns' : ''} a cada $_periodoDiasGlobal dias atingido.',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    setState(() {
      _carrinho.containsKey(p.id)
          ? _carrinho[p.id]!.quantidade++
          : _carrinho[p.id] = CarrinhoItem(produto: p);
    });
    _agendarSyncCarrinho(p);
  }

  void _remover(LojinhaProdutoModel p) {
    if (!_carrinho.containsKey(p.id)) return;
    setState(() {
      _carrinho[p.id]!.quantidade <= 1
          ? _carrinho.remove(p.id)
          : _carrinho[p.id]!.quantidade--;
    });
    _agendarSyncCarrinho(p);
  }

  void _agendarSyncCarrinho(LojinhaProdutoModel p) {
    _cartTimers[p.id]?.cancel();
    _cartTimers[p.id] = Timer(
      const Duration(milliseconds: 600),
      () => _syncCarrinho(p),
    );
  }

  Future<void> _syncCarrinho(LojinhaProdutoModel p) async {
    final qtd = _carrinho[p.id]?.quantidade ?? 0;
    final result = await _api.adicionarAoCarrinho(
      material: p.material,
      quantidade: qtd,
    );
    if (!mounted || result.ok) return;
    if (result.motivo == 'estoque_insuficiente') {
      final max = result.estoqueDisponivel ?? 0;
      setState(() {
        if (max <= 0) {
          _carrinho.remove(p.id);
        } else {
          _carrinho[p.id]?.quantidade = max;
        }
      });
      _mostrarErroEstoque(max);
    }
  }

  void _mostrarErroEstoque(int disponiveis) {
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
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inventory_2_outlined,
                  color: Colors.orange, size: 36),
            ),
            const SizedBox(height: 16),
            Text('Estoque insuficiente',
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              disponiveis > 0
                  ? 'Apenas $disponiveis unidade${disponiveis > 1 ? 's' : ''} disponível${disponiveis > 1 ? 'is' : ''}. Seu carrinho foi ajustado.'
                  : 'Este produto não está mais disponível.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.cinzaTexto),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text('OK',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Pedido ─────────────────────────────────────────────────────────────────

  Future<void> _finalizarPedido() async {
    if (_carrinho.isEmpty || _enviando) return;
    setState(() => _enviando = true);

    final result = await _api.finalizarPedidoLojinha(
      itens: _carrinho.values.toList(),
    );

    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (result.ok) _carrinho.clear();
    });

    if (result.ok) {
      widget.onPedidoCriado();
      final primeiroPedido = result.pedidos
          .where((p) => p.ok && p.numeroPedido != null)
          .map((p) => p.numeroPedido!)
          .firstOrNull;
      if (mounted && primeiroPedido != null) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => LojinhaPedidoDetalheScreen(ordem: primeiroPedido),
          ),
        );
      } else if (mounted) {
        Navigator.pop(context);
      }
    } else {
      _mostrarErro(result.retorno);
    }
  }

  void _mostrarErro(String msg) {
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
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_rounded,
                color: Colors.red,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Erro no pedido',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              msg,
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
                  backgroundColor: Colors.red,
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LojinhaCarrinhoScreen(
          carrinho: _carrinho,
          onAdicionar: _adicionar,
          onRemover: _remover,
          onFinalizar: _finalizarPedido,
          enviando: _enviando,
          itensRestantes: _itensRestantes,
          limiteQtdGlobal: _limiteQtdGlobal,
          periodoDiasGlobal: _periodoDiasGlobal,
        ),
      ),
    ).then((_) => setState(() {})); // rebuild ao voltar para refletir qty alteradas
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      // ── Drawer na DIREITA ────────────────────────────────────────────────
      endDrawer: _NichoDrawer(
        colaboradorNome: _api.colaboradorAtual?.nome ?? '',
        dadosFuncionario: widget.dadosFuncionario,
        // Marcas: todos os produtos com estoque
        marcas: _valoresUnicos((p) => p.marca),
        // Categorias: apenas da marca selecionada
        categorias: _marcaSel == null
            ? []
            : _valoresUnicos(
                (p) => p.categoria,
                filtrosSuperior: {'marca': _marcaSel},
              ),
        // Linhas: apenas da categoria selecionada
        linhas: _categoriaSel == null
            ? []
            : _valoresUnicos(
                (p) => p.linha,
                filtrosSuperior: {
                  'marca': _marcaSel,
                  'categoria': _categoriaSel,
                },
              ),
        // Grupos: apenas da linha selecionada
        grupos: _linhaSel == null
            ? []
            : _valoresUnicos(
                (p) => p.grupo,
                filtrosSuperior: {
                  'marca': _marcaSel,
                  'categoria': _categoriaSel,
                  'linha': _linhaSel,
                },
              ),
        marcaSel: _marcaSel,
        categoriaSel: _categoriaSel,
        linhaSel: _linhaSel,
        grupoSel: _grupoSel,
        onMarca: (v) {
          setState(() {
            _marcaSel = v;
            _categoriaSel = null;
            _linhaSel = null;
            _grupoSel = null;
          });
          _aplicarFiltros();
        },
        onCategoria: (v) {
          setState(() {
            _categoriaSel = v;
            _linhaSel = null;
            _grupoSel = null;
          });
          _aplicarFiltros();
        },
        onLinha: (v) {
          setState(() {
            _linhaSel = v;
            _grupoSel = null;
          });
          _aplicarFiltros();
        },
        onGrupo: (v) {
          setState(() => _grupoSel = v);
          _aplicarFiltros();
        },
        onLimpar: _limparFiltros,
      ),
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
                // ── Header ──────────────────────────────────────────────
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
                              'Novo Pedido',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Escolha seus produtos',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Ícone carrinho
                      if (_totalItens > 0) ...[
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
                                  size: 22,
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
                        const SizedBox(width: 8),
                      ],
                      // Ícone filtro → abre endDrawer (direita)
                      GestureDetector(
                        onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(
                                Icons.tune_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              if (_temFiltroAtivo)
                                Positioned(
                                  top: -3,
                                  right: -3,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
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

                const SizedBox(height: 12),

                // ── Corpo (fundo claro começa aqui) ──────────────────────
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
                              // ── Busca (sobre fundo branco) ───────────
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  0,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.06),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: TextField(
                                    controller: _searchCtrl,
                                    style: GoogleFonts.poppins(
                                      color: AppColors.dark,
                                      fontSize: 14,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Buscar produto ou marca...',
                                      hintStyle: GoogleFonts.poppins(
                                        color: AppColors.cinzaTexto,
                                        fontSize: 13,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.search_rounded,
                                        color: AppColors.cinzaTexto,
                                        size: 20,
                                      ),
                                      suffixIcon: _searchCtrl.text.isNotEmpty
                                          ? GestureDetector(
                                              onTap: () {
                                                _searchCtrl.clear();
                                                FocusScope.of(
                                                  context,
                                                ).unfocus();
                                              },
                                              child: Icon(
                                                Icons.close_rounded,
                                                color: AppColors.cinzaTexto,
                                                size: 18,
                                              ),
                                            )
                                          : null,
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                    ),
                                  ),
                                ),
                              ),

                              // ── Chips de filtros ativos ──────────────
                              if (_temFiltroAtivo) _chipsAtivos(),

                              // ── Contador ─────────────────────────────
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  10,
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
                                    if (_temFiltroAtivo) ...[
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: _limparFiltros,
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

                              // ── Grid ─────────────────────────────────
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
                                              childAspectRatio: 0.70,
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

          // ── FAB carrinho ──────────────────────────────────────────────
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

  Widget _chipsAtivos() {
    final chips = <Widget>[];

    void addChip(String label, VoidCallback onRemove) => chips.add(
      Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.laranja,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(
                Icons.close_rounded,
                size: 13,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (_marcaSel != null)
      addChip(_marcaSel!, () {
        setState(() {
          _marcaSel = null;
          _categoriaSel = null;
          _linhaSel = null;
          _grupoSel = null;
        });
        _aplicarFiltros();
      });
    if (_categoriaSel != null)
      addChip(_categoriaSel!, () {
        setState(() {
          _categoriaSel = null;
          _linhaSel = null;
          _grupoSel = null;
        });
        _aplicarFiltros();
      });
    if (_linhaSel != null)
      addChip(_linhaSel!, () {
        setState(() {
          _linhaSel = null;
          _grupoSel = null;
        });
        _aplicarFiltros();
      });
    if (_grupoSel != null)
      addChip(_grupoSel!, () {
        setState(() => _grupoSel = null);
        _aplicarFiltros();
      });

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        children: chips,
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
        if (_temFiltroAtivo)
          TextButton(
            onPressed: _limparFiltros,
            child: Text(
              'Limpar filtros',
              style: GoogleFonts.poppins(color: AppColors.laranja),
            ),
          ),
      ],
    ),
  );
}

// ── Drawer de Nichos (direita) ────────────────────────────────────────────────

class _NichoDrawer extends StatelessWidget {
  final String colaboradorNome;
  final LojinhaFuncionarioModel? dadosFuncionario;
  final List<String> marcas, categorias, linhas, grupos;
  final String? marcaSel, categoriaSel, linhaSel, grupoSel;
  final void Function(String?) onMarca, onCategoria, onLinha, onGrupo;
  final VoidCallback onLimpar;

  const _NichoDrawer({
    required this.colaboradorNome,
    required this.dadosFuncionario,
    required this.marcas,
    required this.categorias,
    required this.linhas,
    required this.grupos,
    required this.marcaSel,
    required this.categoriaSel,
    required this.linhaSel,
    required this.grupoSel,
    required this.onMarca,
    required this.onCategoria,
    required this.onLinha,
    required this.onGrupo,
    required this.onLimpar,
  });

  String _moeda(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    final d = dadosFuncionario;
    final temFiltro =
        marcaSel != null ||
        categoriaSel != null ||
        linhaSel != null ||
        grupoSel != null;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho com perfil + limite ──────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: AppColors.gradientePrincipal,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          colaboradorNome,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (d != null) ...[
                    const SizedBox(height: 14),
                    _infoLinha('Limite total', _moeda(d.limiteTotal)),
                    _infoLinha('Disponível', _moeda(d.limiteDisp)),
                    _infoLinha('Utilizado', _moeda(d.limiteUsado)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: 1 - d.percentualUsado,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                        minHeight: 5,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Título + limpar ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Text(
                    'Filtrar por nicho',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                  const Spacer(),
                  if (temFiltro)
                    GestureDetector(
                      onTap: () {
                        onLimpar();
                        Navigator.pop(context);
                      },
                      child: Text(
                        'Limpar tudo',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.laranja,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const Divider(height: 1),

            // ── Hierarquia cascata ─────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nível 1 — Marca (sempre visível)
                    _NivelFiltro(
                      icone: '🏷',
                      titulo: 'Marca',
                      opcoes: marcas,
                      selecionado: marcaSel,
                      onSelect: (v) {
                        onMarca(v);
                        // não fecha — usuário continua refinando
                      },
                    ),

                    // Nível 2 — Categoria (só aparece após escolher marca)
                    if (marcaSel != null && categorias.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _NivelFiltro(
                        icone: '🐔',
                        titulo: 'Categoria',
                        opcoes: categorias,
                        selecionado: categoriaSel,
                        onSelect: onCategoria,
                      ),
                    ],

                    // Nível 3 — Linha (só após categoria)
                    if (categoriaSel != null && linhas.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _NivelFiltro(
                        icone: '📦',
                        titulo: 'Linha',
                        opcoes: linhas,
                        selecionado: linhaSel,
                        onSelect: onLinha,
                      ),
                    ],

                    // Nível 4 — Grupo (só após linha)
                    if (linhaSel != null && grupos.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _NivelFiltro(
                        icone: '🗂',
                        titulo: 'Grupo',
                        opcoes: grupos,
                        selecionado: grupoSel,
                        onSelect: onGrupo,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Botão aplicar ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.laranja,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Aplicar filtros',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoLinha(String label, String valor) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      children: [
        Text(
          '$label: ',
          style: GoogleFonts.poppins(
            color: Colors.white.withOpacity(0.75),
            fontSize: 11,
          ),
        ),
        Text(
          valor,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

// ── Nível de filtro hierárquico ───────────────────────────────────────────────

class _NivelFiltro extends StatelessWidget {
  final String icone, titulo;
  final List<String> opcoes;
  final String? selecionado;
  final void Function(String?) onSelect;

  const _NivelFiltro({
    required this.icone,
    required this.titulo,
    required this.opcoes,
    required this.selecionado,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            Text(icone, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              titulo,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.cinzaTexto,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: opcoes.map((op) {
            final ativo = selecionado == op;
            return GestureDetector(
              onTap: () => onSelect(ativo ? null : op),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
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
                            color: AppColors.laranja.withOpacity(0.22),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  op,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ativo ? Colors.white : AppColors.cinzaTexto,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        const Divider(),
      ],
    );
  }
}

// ── Card de Produto ───────────────────────────────────────────────────────────

class _CardProduto extends StatelessWidget {
  final LojinhaProdutoModel produto;
  final int quantidade;
  final VoidCallback onAdicionar, onRemover;

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
        border: temNoCarrinho
            ? Border.all(color: AppColors.laranja.withOpacity(0.45), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.laranja.withOpacity(temNoCarrinho ? 0.18 : 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    child: produto.fotoUrl != null
                        ? Image.network(
                            produto.fotoUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.inventory_2_outlined,
                              size: 44,
                              color: AppColors.laranja.withOpacity(0.4),
                            ),
                          )
                        : Icon(
                            Icons.inventory_2_outlined,
                            size: 44,
                            color: AppColors.laranja.withOpacity(0.4),
                          ),
                  ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 4),
                Text(
                  'R\$ ${produto.preco.toStringAsFixed(2).replaceAll('.', ',')}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.laranja,
                  ),
                ),
                const SizedBox(height: 8),
                temNoCarrinho
                    ? Row(
                        children: [
                          _BotaoQtd(icone: Icons.remove, onTap: onRemover),
                          Expanded(
                            child: Text(
                              '$quantidade',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          _BotaoQtd(icone: Icons.add, onTap: onAdicionar),
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
  const _BotaoQtd({required this.icone, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.laranja.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icone, size: 16, color: AppColors.laranja),
    ),
  );
}

// ── Carrinho Sheet ────────────────────────────────────────────────────────────

class _CarrinhoSheet extends StatelessWidget {
  final Map<int, CarrinhoItem> carrinho;
  final double totalValor;
  final void Function(LojinhaProdutoModel) onAdicionar, onRemover;
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
              maxHeight: MediaQuery.of(context).size.height * 0.35,
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
                              'R\$ ${item.produto.preco.toStringAsFixed(2).replaceAll('.', ',')} · total R\$ ${item.subtotal.toStringAsFixed(2).replaceAll('.', ',')}',
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
