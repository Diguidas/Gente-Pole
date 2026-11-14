import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_theme.dart';
import '../../models/lojinha_model.dart';
import '../../services/api_service.dart';
import 'lojinha_produtos_screen.dart';
import 'lojinha_pedidos_screen.dart';
import 'lojinha_pedido_detalhe_screen.dart';

class LojinhaHomeScreen extends StatefulWidget {
  const LojinhaHomeScreen({super.key});

  @override
  State<LojinhaHomeScreen> createState() => _LojinhaHomeScreenState();
}

class _LojinhaHomeScreenState extends State<LojinhaHomeScreen> {
  final _api = ApiService();
  LojinhaFuncionarioModel? _dados;
  bool _carregando = true;
  bool _recalculando = false;
  /// Se a filial do colaborador não tiver uma regra 'geral' liberando,
  /// a Lojinha fica só-consulta (sem catálogo, sem novo pedido).
  bool _liberadaParaCompra = true;
  // Regra "geral" (produtos SAP) aberta agora. A Lojinha também abre só com
  // exclusivos abertos (dia + horário + filial), independente da geral.
  bool _liberadaGeral = true;
  // Exclusivos abertos agora (dia + horário + filial) e se existe algum
  // exclusivo cadastrado para a filial.
  int _exclusivosLiberadosAgora = 0;
  bool _temExclusivos = false;

  // Limite de PEDIDOS (não itens) por tipo, configurado no gentepole_admin —
  // ex: 1 regular (SAP) + 1 exclusivo por semana.
  bool _sapEsgotado = false;
  bool _exclusivoEsgotado = false;

  // Limite de ITENS por período, separado por tipo (SAP x exclusivos).
  int? _limiteQtdSap;
  int? _limiteQtdExclusivo;
  int? _periodoDiasItens;
  int _itensRestantesSap = 999;
  int _itensRestantesExclusivo = 999;

  bool get _limiteItensAtingido =>
      (_limiteQtdSap != null && _itensRestantesSap <= 0) ||
      (_limiteQtdExclusivo != null && _itensRestantesExclusivo <= 0);

  String _qtdItens(int n) => '$n ${n != 1 ? 'itens' : 'item'}';

  String get _resumoItensRestantes =>
      [
        if (_limiteQtdSap != null) '${_qtdItens(_itensRestantesSap)} Pole',
        if (_limiteQtdExclusivo != null)
          '${_qtdItens(_itensRestantesExclusivo)} ovos',
      ].join(' · ') +
      ' disponíveis para compra';

  String get _resumoLimiteItens {
    final dias = _periodoDiasItens ?? 0;
    final per = 'a cada $dias dia${dias != 1 ? 's' : ''}';
    return 'Limite: ' +
        [
          if (_limiteQtdSap != null) '${_qtdItens(_limiteQtdSap!)} Pole',
          if (_limiteQtdExclusivo != null)
            '${_qtdItens(_limiteQtdExclusivo!)} ovos',
        ].join(' + ') +
        ' $per';
  }

  // Olhinho pra ocultar o limite disponível (privacidade quando alguém olha
  // por cima do ombro) — lembrado entre sessões via SharedPreferences.
  static const _kValorOcultoKey = 'lojinha_valor_oculto';
  bool _valorOculto = false;
  bool _detalheLimiteAberto = false;

  @override
  void initState() {
    super.initState();
    _carregarPreferenciaOcultar();
    _carregar();
  }

  Future<void> _carregarPreferenciaOcultar() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _valorOculto = prefs.getBool(_kValorOcultoKey) ?? false);
  }

  Future<void> _alternarValorOculto() async {
    setState(() => _valorOculto = !_valorOculto);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kValorOcultoKey, _valorOculto);
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    _dados = await _api.buscarDadosFuncionarioLojinha();
    final liberadaGeral = await _api.lojinhaLiberadaParaFilial(
      _api.colaboradorAtual?.branch,
    );
    var liberada = liberadaGeral;
    var exclusivosAgora = 0;
    var temExclusivos = false;
    try {
      final excl = await _api.buscarExclusivosLojinha();
      temExclusivos = excl.isNotEmpty;
      exclusivosAgora = excl.where((p) => p.disponivelHoje).length;
      if (!liberada) liberada = exclusivosAgora > 0;
    } catch (_) {}
    await _carregarLimitePedidos();
    if (!mounted) return;
    setState(() {
      _carregando = false;
      _liberadaParaCompra = liberada;
      _liberadaGeral = liberadaGeral;
      _exclusivosLiberadosAgora = exclusivosAgora;
      _temExclusivos = temExclusivos;
    });
    await _retentarSeValorZerado();
  }

  /// Se o colaborador já usou o pedido regular e/ou exclusivo do período
  /// (limite configurado no gentepole_admin), marca aqui pra: (1) bloquear
  /// "Novo Pedido" de vez quando os dois tipos já foram usados, ou (2) fazer
  /// o catálogo mostrar só o tipo que ainda tem potencial de compra.
  Future<void> _carregarLimitePedidos() async {
    final matricula = _api.colaboradorAtual?.matricula;
    if (matricula == null) return;
    try {
      final config = await _api.buscarConfigLojinha();

      // Limite de ITENS por tipo (SAP x exclusivo) no período.
      final limiteQtd = config['limite_qtd'] as int?;
      final limiteQtdExcl = config['limite_qtd_exclusivo'] as int?;
      final periodoDias = config['periodo_dias'] as int?;
      if ((limiteQtd != null || limiteQtdExcl != null) && periodoDias != null) {
        final r =
            await _api.buscarComprasRecentesPorTipoColab(matricula, periodoDias);
        if (!mounted) return;
        setState(() {
          _limiteQtdSap = limiteQtd;
          _limiteQtdExclusivo = limiteQtdExcl;
          _periodoDiasItens = periodoDias;
          _itensRestantesSap = limiteQtd == null
              ? 999
              : (limiteQtd - r.sap).clamp(0, limiteQtd);
          _itensRestantesExclusivo = limiteQtdExcl == null
              ? 999
              : (limiteQtdExcl - r.exclusivo).clamp(0, limiteQtdExcl);
        });
      } else if (mounted) {
        setState(() {
          _limiteQtdSap = null;
          _limiteQtdExclusivo = null;
        });
      }

      final limiteSap = config['limite_pedidos_sap'] as int?;
      final limiteExclusivo = config['limite_pedidos_exclusivo'] as int?;
      final periodoDiasPedidos = config['periodo_dias_pedidos'] as int?;
      if ((limiteSap == null && limiteExclusivo == null) ||
          periodoDiasPedidos == null) {
        return;
      }
      final contagem = await _api.buscarPedidosPorTipoRecentesColab(
          matricula, periodoDiasPedidos);
      if (!mounted) return;
      setState(() {
        _sapEsgotado = limiteSap != null && contagem.regular >= limiteSap;
        _exclusivoEsgotado =
            limiteExclusivo != null && contagem.exclusivo >= limiteExclusivo;
      });
    } catch (_) {
      // Sem limite configurado ou erro ao consultar — não bloqueia nada.
    }
  }

  /// O SAP pode levar um instante para calcular o valor total de um pedido
  /// recém-criado — a primeira leitura logo após finalizar às vezes volta
  /// com VALORTOTAL zerado, e só aparece certo numa atualização seguinte.
  /// Tenta de novo algumas vezes antes de deixar o valor zerado na tela.
  /// Enquanto tenta, `_recalculando` fica true pra esconder o "R$ 0,00"
  /// (que é enganoso) e mostrar "Calculando..." no lugar.
  Future<void> _retentarSeValorZerado() async {
    final hoje = DateTime.now();
    final criacaoHoje =
        '${hoje.year}${hoje.month.toString().padLeft(2, '0')}${hoje.day.toString().padLeft(2, '0')}';

    bool pendente() => _dados?.pedidos
            .any((p) => p.criacao == criacaoHoje && p.valorTotal == 0) ??
        false;

    if (!pendente()) return;
    setState(() => _recalculando = true);
    for (var tentativa = 0; tentativa < 3; tentativa++) {
      if (!pendente()) break;
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final novosDados = await _api.buscarDadosFuncionarioLojinha();
      if (!mounted) return;
      setState(() => _dados = novosDados);
    }
    if (mounted) setState(() => _recalculando = false);
  }

  String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    final colaborador = _api.colaboradorAtual;
    final dados = _dados;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Banner imagem ────────────────────────────────────────────────
          SizedBox(
            height: 220,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(28)),
                    child: Image.asset(
                      'assets/lojinha.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  child: SafeArea(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Título + Card de Limite ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lojinha',
                    style: GoogleFonts.poppins(
                        fontSize: 22, fontWeight: FontWeight.w700)),
                Text('Olá, ${colaborador?.primeiroNome ?? ''}!',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(height: 14),
                _carregando
                    ? _shimmerCard()
                    : dados == null
                        ? _erroCard()
                        : _limiteCard(dados),
              ],
            ),
          ),

          // ── Corpo ────────────────────────────────────────────────
          Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_liberadaParaCompra) ...[
                            _avisoSoConsulta(),
                            const SizedBox(height: 16),
                            _botaoMenu(
                              context,
                              icone: Icons.receipt_long_rounded,
                              titulo: 'Meus Pedidos',
                              subtitulo:
                                  '${dados?.pedidos.length ?? 0} pedido${(dados?.pedidos.length ?? 0) != 1 ? 's' : ''} realizados',
                              cor: AppColors.magenta,
                              bloqueado: false,
                              onTap: dados == null
                                  ? null
                                  : () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => LojinhaPedidosScreen(
                                            pedidos: dados.pedidos,
                                          ),
                                        ),
                                      ),
                            ),
                          ] else ...[
                          // ── Alerta de bloqueio ───────────────────────
                          if (dados != null && dados.bloqueado)
                            _alertaBloqueio(),

                          // ── Limite de itens por tipo (SAP x exclusivos) ──
                          if (_limiteQtdSap != null ||
                              _limiteQtdExclusivo != null) ...[
                            _cardLimiteItens(),
                            const SizedBox(height: 16),
                          ],

                          // ── Pedido(s) do período já realizado(s) ─────
                          if (_avisoPedidosUsados() != null)
                            _avisoPedidosUsados()!,

                          // ── Botões principais ────────────────────────
                          _botaoMenu(
                            context,
                            icone: Icons.add_shopping_cart_rounded,
                            titulo: 'Novo Pedido',
                            subtitulo: (_sapEsgotado && _exclusivoEsgotado)
                                ? 'Você já realizou a compra liberada deste período'
                                : _limiteItensAtingido
                                    ? 'Você já realizou a compra liberada deste período'
                                    : _nadaDisponivelAgora
                                        ? 'Nenhum produto disponível agora'
                                        : 'Explorar produtos disponíveis',
                            cor: AppColors.laranja,
                            bloqueado: (dados?.bloqueado ?? false) ||
                                _limiteItensAtingido ||
                                _nadaDisponivelAgora,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LojinhaProdutosScreen(
                                    dadosFuncionario: dados,
                                    onPedidoCriado: _carregar,
                                    sapEsgotado: _sapEsgotado,
                                    exclusivoEsgotado: _exclusivoEsgotado,
                                    liberadaGeral: _liberadaGeral,
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 14),

                          _botaoMenu(
                            context,
                            icone: Icons.receipt_long_rounded,
                            titulo: 'Meus Pedidos',
                            subtitulo:
                                '${dados?.pedidos.length ?? 0} pedido${(dados?.pedidos.length ?? 0) != 1 ? 's' : ''} realizados',
                            cor: AppColors.magenta,
                            bloqueado: false,
                            onTap: dados == null
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => LojinhaPedidosScreen(
                                          pedidos: dados.pedidos,
                                        ),
                                      ),
                                    ),
                          ),

                          const SizedBox(height: 28),

                          // ── Pedidos vigentes ─────────────────────────
                          if (dados != null) ...[
                            Builder(builder: (_) {
                              final vigentes = (dados.pedidos
                                  .where((p) => p.isVigente)
                                  .toList()
                                ..sort((a, b) =>
                                    b.dataOrdenacao.compareTo(a.dataOrdenacao)))
                                  .take(3)
                                  .toList();
                              if (vigentes.isEmpty) return const SizedBox.shrink();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 8, height: 8,
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade500,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text('Sendo descontado agora',
                                          style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.cinzaTexto,
                                              letterSpacing: 0.4)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ...vigentes.map((p) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _ultimoPedidoCard(p, recalculando: _recalculando),
                                  )),
                                ],
                              );
                            }),
                          ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Widgets internos ──────────────────────────────────────────────────────

  Widget _limiteCard(LojinhaFuncionarioModel d) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Text('Limite disponível',
                    style: GoogleFonts.poppins(
                        color: AppColors.cinzaTexto, fontSize: 12)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _alternarValorOculto,
                  child: Icon(
                    _valorOculto
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 16,
                    color: AppColors.cinzaTexto,
                  ),
                ),
              ]),
              Text(
                  _valorOculto
                      ? 'Total: ••••'
                      : 'Total: ${_moeda(d.limiteTotal)}',
                  style: GoogleFonts.poppins(
                      color: AppColors.cinzaTexto, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          Text(_valorOculto ? '••••••' : _moeda(d.limiteDisp),
              style: GoogleFonts.poppins(
                  color: AppColors.laranja,
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: 1 - d.percentualUsado,
              backgroundColor: Colors.grey.shade200,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.laranja),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _valorOculto
                ? 'Utilizado: •••• de ••••'
                : 'Utilizado: ${_moeda(d.limiteUsado)} de ${_moeda(d.limiteTotal)}',
            style: GoogleFonts.poppins(
                color: AppColors.cinzaTexto, fontSize: 11),
          ),
          if (!_valorOculto && d.totalDescontos > 0) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            InkWell(
              onTap: () => setState(
                  () => _detalheLimiteAberto = !_detalheLimiteAberto),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Text('Como seu limite é calculado',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.dark)),
                  ),
                  AnimatedRotation(
                    turns: _detalheLimiteAberto ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: AppColors.cinzaTexto),
                  ),
                ]),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: _detalheLimiteAberto
                  ? Column(children: [
                      _linhaLimite('Limite total', d.limiteBruto),
                      if (d.pensao > 0) _linhaLimite('Pensão', -d.pensao),
                      if (d.emprestimos > 0)
                        _linhaLimite('Empréstimos', -d.emprestimos),
                      if (d.planoSaude > 0)
                        _linhaLimite('Plano de saúde', -d.planoSaude),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Divider(height: 1),
                      ),
                      _linhaLimite('Limite para compras', d.limiteTotal,
                          destaque: true),
                      const SizedBox(height: 4),
                    ])
                  : const SizedBox(width: double.infinity),
            ),
          ],
          if (!_valorOculto && d.bonificacao > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.card_giftcard_outlined,
                    size: 16, color: Color(0xFF16A34A)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Você tem bonificação em aberto: ${_moeda(d.bonificacao)}. '
                      'Ela ajuda a liberar crédito para suas compras.',
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: const Color(0xFF166534))),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _linhaLimite(String rotulo, double valor, {bool destaque = false}) {
    final negativo = valor < 0;
    final texto = '${negativo ? '- ' : ''}${_moeda(valor.abs())}';
    final estilo = GoogleFonts.poppins(
      fontSize: 11,
      fontWeight: destaque ? FontWeight.w700 : FontWeight.w400,
      color: negativo ? Colors.red.shade600 : AppColors.dark,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(rotulo, style: estilo),
        Text(texto, style: estilo),
      ]),
    );
  }

  Widget _shimmerCard() => Container(
        height: 80,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
            child: CircularProgressIndicator(color: AppColors.laranja)),
      );

  Widget _erroCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.grey.shade500),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Não foi possível carregar seus dados.',
                  style: GoogleFonts.poppins(
                      color: AppColors.cinzaTexto, fontSize: 13)),
            ),
            GestureDetector(
              onTap: _carregar,
              child: Icon(Icons.refresh_rounded, color: AppColors.laranja),
            ),
          ],
        ),
      );

  Widget _avisoSoConsulta() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storefront_outlined, size: 20, color: AppColors.cinzaTexto),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Lojinha não disponível para compra, só consulta',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                'A Lojinha ainda não foi liberada pra compra na sua filial. '
                'Você pode consultar seus pedidos anteriores em "Meus Pedidos".',
                style: GoogleFonts.poppins(
                    fontSize: 12.5, color: AppColors.cinzaTexto, height: 1.4)),
          ],
        ),
      );

  Widget _cardLimiteItens() {
    final atingido = _limiteItensAtingido;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: atingido ? Colors.red.shade50 : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: atingido ? Colors.red.shade200 : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(
            atingido ? Icons.block_rounded : Icons.shopping_bag_outlined,
            size: 20,
            color: atingido ? Colors.red.shade600 : AppColors.cinzaTexto,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  atingido
                      ? 'Você já realizou a compra liberada deste período'
                      : _resumoItensRestantes,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: atingido ? Colors.red.shade700 : AppColors.dark,
                  ),
                ),
                Text(
                  _resumoLimiteItens,
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppColors.cinzaTexto),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _sapDisponivel => _liberadaGeral && !_sapEsgotado;
  bool get _exclusivoDisponivel =>
      !_exclusivoEsgotado && _exclusivosLiberadosAgora > 0;
  bool get _nadaDisponivelAgora => !_sapDisponivel && !_exclusivoDisponivel;

  /// Explica, por tipo, por que não dá para comprar agora (já usou o pedido do
  /// período ou não está liberado neste momento). Nulo quando os dois tipos
  /// estão disponíveis.
  Widget? _avisoPedidosUsados() {
    final linhas = <String>[];
    if (!_liberadaGeral) {
      linhas.add('Produtos Pole: não estão liberados neste momento.');
    } else if (_sapEsgotado) {
      linhas.add(
          'Produtos Pole: você já realizou o pedido liberado deste período.');
    }
    if (_exclusivoEsgotado) {
      linhas.add(
          'Produtos ovos: você já realizou o pedido liberado deste período.');
    } else if (_exclusivosLiberadosAgora == 0 && _temExclusivos) {
      linhas.add('Produtos ovos: não estão liberados neste momento.');
    }
    if (linhas.isEmpty) return null;
    if (_nadaDisponivelAgora) {
      linhas.insert(0, 'Nenhum produto disponível para compra agora.');
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in linhas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      l,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade900),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertaBloqueio() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.block_rounded, color: Colors.red.shade600, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Seu cadastro está bloqueado para compras. Procure o RH.',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade700),
              ),
            ),
          ],
        ),
      );

  Widget _botaoMenu(
    BuildContext context, {
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required Color cor,
    required bool bloqueado,
    required VoidCallback? onTap,
  }) {
    final desabilitado = bloqueado && titulo == 'Novo Pedido';
    return GestureDetector(
      onTap: desabilitado ? null : onTap,
      child: Opacity(
        opacity: desabilitado ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: cor.withOpacity(0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: cor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16)),
                child: Icon(icone, color: cor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark)),
                    Text(subtitulo,
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.cinzaTexto)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.cinzaTexto, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ultimoPedidoCard(LojinhaPedidoResumoModel p, {required bool recalculando}) {
    final cor = p.isRecusado
        ? AppColors.erro
        : (p.isVigente ? Colors.green.shade600 : AppColors.laranja);
    final aguardandoValor = recalculando && p.valorTotal == 0;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => LojinhaPedidoDetalheScreen(
                  ordem: p.ordem,
                  criacao: p.criacao,
                  docnum: p.docnum,
                  descricaoExclusivo: p.descricaoExclusivo,
                  quantidadeExclusivo: p.quantidadeExclusivo,
                  valorExclusivo: p.isExclusivo ? p.valorTotal : null,
                )),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
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
                      color: cor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.receipt_rounded, color: cor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          p.isExclusivo
                              ? p.rotuloExclusivo
                              : 'Pedido nº ${p.ordem}',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      Text(
                          p.isRecusado
                              ? '${p.criacaoFormatada} · Cancelado'
                              : p.criacaoFormatada,
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: p.isRecusado
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: p.isRecusado
                                  ? AppColors.erro
                                  : AppColors.cinzaTexto)),
                    ],
                  ),
                ),
                aguardandoValor
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cor),
                          ),
                          const SizedBox(width: 6),
                          Text('Calculando...',
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: AppColors.cinzaTexto)),
                        ],
                      )
                    : Text(
                        'R\$ ${p.valorTotal.toStringAsFixed(2).replaceAll('.', ',')}',
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cor),
                      ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.cinzaTexto, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}