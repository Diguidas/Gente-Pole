import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';
import '../models/aniversariante_model.dart';
import '../services/api_service.dart';

class AniversariantesScreen extends StatefulWidget {
  const AniversariantesScreen({super.key});

  @override
  State<AniversariantesScreen> createState() => _AniversariantesScreenState();
}

class _AniversariantesScreenState extends State<AniversariantesScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabCtrl;
  late Future<List<AniversarianteModel>> _future;
  late Future<List<Map<String, dynamic>>> _futureMensagens;

  final Set<int> _jaParabenisei = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _future = _api.buscarAniversariantesMes();
    _futureMensagens = _api.buscarMensagensParabens();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _recarregar() => setState(() {
    _future = _api.buscarAniversariantesMes();
    _futureMensagens = _api.buscarMensagensParabens();
  });

  // ─── Build principal ─────────────────────────────────────────────────────────

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🎂 Aniversariantes',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _mesAtual(),
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _recarregar,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                // TabBar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: TabBar(
                    controller: _tabCtrl,
                    labelStyle: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white.withOpacity(0.55),
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
                    tabs: const [
                      Tab(text: 'Aniversariantes'),
                      Tab(text: 'Mensagens'),
                    ],
                  ),
                ),

                // Conteúdo
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _buildAbaAniversariantes(),
                        _buildAbaMensagens(),
                      ],
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

  // ─── Aba 1: Aniversariantes ──────────────────────────────────────────────────

  Widget _buildAbaAniversariantes() {
    return FutureBuilder<List<AniversarianteModel>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.magenta),
          );
        }
        if (snap.hasError) return _erroWidget();

        final lista = snap.data ?? [];
        if (lista.isEmpty) return _vazioWidget();

        final hoje = lista.where((a) => a.ehHoje).toList();
        final now = DateTime.now();
        final restante = lista
            .where((a) => !a.ehHoje && a.diaNascimento > now.day)
            .toList();

        // Dentro do FutureBuilder, após montar a lista hoje/restante:
        final meuAniv = _meuAniversario();
        final ehMeuAniversario =
            meuAniv != null &&
            hoje.any((a) => a.colaborador.id == _api.colaboradorAtual?.id);

        final hojeExcluindoEu = hoje
            .where((a) => a.colaborador.id != _api.colaboradorAtual?.id)
            .toList();

        // Agrupa por dia
        final Map<int, List<AniversarianteModel>> porDia = {};
        for (final a in restante) {
          porDia.putIfAbsent(a.diaNascimento, () => []).add(a);
        }
        final diasOrdenados = porDia.keys.toList()..sort();

        return RefreshIndicator(
          color: AppColors.magenta,
          onRefresh: () async => _recarregar(),
          child: CustomScrollView(
            slivers: [
              // ── Banner "meu aniversário" ────────────────────────
              if (ehMeuAniversario)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF9B5DE5), Color(0xFFE040A0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF9B5DE5).withOpacity(0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Text('🎂', style: TextStyle(fontSize: 40)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Parabéns pelo seu dia,',
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '${_api.colaboradorAtual?.primeiroNome ?? 'Polevalente'}! 🎉',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Que este novo ciclo seja incrível! ✨',
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Depois vem o restante normal (Hoje 🎉, Este mês...)
              // Hoje
              if (hojeExcluindoEu.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Text(
                      'Hoje 🎉',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _cardHoje(hojeExcluindoEu[i]),
                    childCount: hojeExcluindoEu.length,
                  ),
                ),
              ],

              // Este mês — agrupado por dia
              if (diasOrdenados.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Text(
                      'Este mês',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate((ctx, i) {
                    final dia = diasOrdenados[i];
                    return _grupoDia(dia, porDia[dia]!);
                  }, childCount: diasOrdenados.length),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        );
      },
    );
  }

  // ─── Aba 2: Mensagens ────────────────────────────────────────────────────────

  Widget _buildAbaMensagens() {
    final meuId = _api.colaboradorAtual?.id;
    final aniv = _meuAniversario();
    final ehAniversarioHoje =
        aniv != null &&
        DateTime.now().day == aniv.dia &&
        DateTime.now().month == aniv.mes;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _futureMensagens,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.magenta),
          );
        }

        // Não é aniversário hoje
        if (!ehAniversarioHoje) {
          return _buildAguardarSeuDia();
        }

        final mensagens = snap.data ?? [];

        // É aniversário mas não tem mensagens
        if (mensagens.isEmpty) {
          return _buildFelicitacaoPropria();
        }

        // Tem mensagens — exibe lista
        return RefreshIndicator(
          color: AppColors.magenta,
          onRefresh: () async =>
              setState(() => _futureMensagens = _api.buscarMensagensParabens()),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            itemCount: mensagens.length + 1, // +1 para o header
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Banner topo
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF6B00), Color(0xFFE91E8C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Text('🎂', style: TextStyle(fontSize: 36)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Feliz aniversário! 🎉',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '${mensagens.length} pessoa${mensagens.length != 1 ? 's' : ''} te parabenizou!',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Mensagens recebidas',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                );
              }

              final msg = mensagens[i - 1];
              final remetente = msg['remetente_nome'] as String? ?? 'Colega';
              final setor = msg['remetente_setor'] as String?;
              final texto = msg['mensagem'] as String? ?? '';
              final criadoEm = msg['criado_em'] as String? ?? '';
              final hora = criadoEm.length >= 16
                  ? criadoEm.substring(11, 16)
                  : '';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.laranja.withOpacity(0.15),
                      child: Text(
                        _iniciais(remetente),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.laranja,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  remetente,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: AppColors.dark,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (hora.isNotEmpty)
                                Text(
                                  hora,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: AppColors.cinzaTexto,
                                  ),
                                ),
                            ],
                          ),
                          if (setor != null)
                            Text(
                              setor,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: AppColors.cinzaTexto,
                              ),
                            ),
                          const SizedBox(height: 6),
                          Text(
                            texto,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: AppColors.dark,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ─── "Aguarde seu dia" (não é aniversário) ───────────────────────────────────

  Widget _buildAguardarSeuDia() {
    final colaborador = _api.colaboradorAtual;
    final aniv = _meuAniversario();
    final dia = aniv?.dia;
    final mes = aniv?.mes;

    String dataFormatada = '';
    if (dia != null && mes != null) {
      const meses = [
        '',
        'janeiro',
        'fevereiro',
        'março',
        'abril',
        'maio',
        'junho',
        'julho',
        'agosto',
        'setembro',
        'outubro',
        'novembro',
        'dezembro',
      ];
      dataFormatada = '$dia de ${meses[mes]}';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.magenta.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('🎁', style: TextStyle(fontSize: 36)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Aguarde seu dia!',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              dataFormatada.isNotEmpty
                  ? 'Seu aniversário é dia $dataFormatada.\nQuando chegar, você verá as mensagens aqui! 🎂'
                  : 'No seu aniversário, as mensagens dos seus colegas aparecerão aqui.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.cinzaTexto,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Felicitação própria (aniversário hoje, sem mensagens ainda) ─────────────

  Widget _buildFelicitacaoPropria() {
    final nome = _api.colaboradorAtual?.primeiroNome ?? 'você';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉🎂🎉', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 20),
            Text(
              'Feliz aniversário, $nome!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Que este novo ciclo traga muita saúde,\nalegria e conquistas. Você merece! ✨',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: AppColors.cinzaTexto,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.magenta.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.magenta.withOpacity(0.2)),
              ),
              child: Text(
                'As mensagens dos seus colegas\naparecerão aqui ao longo do dia.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.magenta,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Card destaque hoje ──────────────────────────────────────────────────────

  Widget _cardHoje(AniversarianteModel a) {
    final jaParabenisei = _jaParabenisei.contains(a.colaborador.id);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B00), Color(0xFFE91E8C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.magenta.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            _avatar(a.colaborador, raio: 30, fonteGrande: true),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.colaborador.nome,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (a.colaborador.setor != null)
                    Text(
                      a.colaborador.setor!,
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Hoje é dia de celebrar! 🎊',
                    style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  if (a.totalParabens > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${a.totalParabens} parabéns recebidos',
                        style: GoogleFonts.poppins(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Botão parabenizar — só aparece para aniversariantes de hoje
            GestureDetector(
              onTap: jaParabenisei ? null : () => _abrirModalParabens(a),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: jaParabenisei
                      ? Colors.white.withOpacity(0.2)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  jaParabenisei ? '✓ Enviado' : '🎉 Parabenizar',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: jaParabenisei
                        ? Colors.white.withOpacity(0.7)
                        : AppColors.magenta,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Grupo por dia (colapsável) ──────────────────────────────────────────────

  Widget _grupoDia(int dia, List<AniversarianteModel> pessoas) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.magenta.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                dia.toString().padLeft(2, '0'),
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppColors.magenta,
                ),
              ),
            ),
          ),
          title: Text(
            pessoas.length == 1
                ? pessoas.first.colaborador.primeiroNome
                : '${pessoas.length} aniversariantes',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.dark,
            ),
          ),
          subtitle: pessoas.length == 1
              ? Text(
                  pessoas.first.colaborador.setor ?? '',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.cinzaTexto,
                  ),
                )
              : null,
          // Sem botão parabenizar nos itens do mês — só em hoje
          children: pessoas.map((a) => _itemDentroGrupo(a)).toList(),
        ),
      ),
    );
  }

  Widget _itemDentroGrupo(AniversarianteModel a) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          _avatar(a.colaborador, raio: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.colaborador.nome,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.dark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (a.colaborador.setor != null)
                  Text(
                    a.colaborador.setor!,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.cinzaTexto,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Sem botão parabenizar — pessoa ainda não está aniversariando
        ],
      ),
    );
  }

  // ─── Modal de parabéns ───────────────────────────────────────────────────────

  void _abrirModalParabens(AniversarianteModel a) {
    final controller = TextEditingController(
      text:
          'Feliz aniversário, ${a.colaborador.primeiroNome}! 🎉 Que seu dia seja incrível!',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ModalParabens(
        aniversariante: a,
        controller: controller,
        onEnviar: (mensagem) async {
          final ok = await _api.enviarParabens(
            destinatarioId: a.colaborador.id,
            mensagem: mensagem,
          );
          if (!mounted) return;
          if (ok) {
            setState(() => _jaParabenisei.add(a.colaborador.id));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Parabéns enviado para ${a.colaborador.primeiroNome}! 🎊',
                  style: GoogleFonts.poppins(),
                ),
                backgroundColor: AppColors.magenta,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Erro ao enviar. Tente novamente.',
                  style: GoogleFonts.poppins(),
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  Widget _avatar(colaborador, {double raio = 22, bool fonteGrande = false}) {
    final iniciais = _iniciais(colaborador.nome);
    return CircleAvatar(
      radius: raio,
      backgroundColor: AppColors.laranja.withOpacity(0.2),
      backgroundImage: colaborador.fotoUrl != null
          ? NetworkImage(colaborador.fotoUrl!)
          : null,
      child: colaborador.fotoUrl == null
          ? Text(
              iniciais,
              style: GoogleFonts.poppins(
                fontSize: fonteGrande ? 18 : 12,
                fontWeight: FontWeight.w700,
                color: AppColors.laranja,
              ),
            )
          : null,
    );
  }

  // Helper no _AniversariantesScreenState:
  ({int dia, int mes})? _meuAniversario() {
    final data = _api.colaboradorAtual?.dataNascimento;
    if (data == null) return null;
    final partes = data.split('-');
    if (partes.length < 3) return null;
    return (
      dia: int.tryParse(partes[2]) ?? 0,
      mes: int.tryParse(partes[1]) ?? 0,
    );
  }

  String _iniciais(String nome) {
    final p = nome.trim().split(' ');
    return p.length >= 2
        ? '${p.first[0]}${p.last[0]}'.toUpperCase()
        : nome.isNotEmpty
        ? nome[0].toUpperCase()
        : '?';
  }

  String _mesAtual() {
    const meses = [
      '',
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    final now = DateTime.now();
    return '${meses[now.month]} ${now.year}';
  }

  Widget _erroWidget() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: AppColors.cinzaTexto,
          size: 48,
        ),
        const SizedBox(height: 12),
        Text(
          'Erro ao carregar',
          style: GoogleFonts.poppins(color: AppColors.cinzaTexto),
        ),
        TextButton(
          onPressed: _recarregar,
          child: const Text('Tentar novamente'),
        ),
      ],
    ),
  );

  Widget _vazioWidget() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('🎂', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text(
          'Nenhum aniversariante este mês',
          style: GoogleFonts.poppins(color: AppColors.cinzaTexto),
        ),
      ],
    ),
  );
}

// ─── Modal de parabéns ────────────────────────────────────────────────────────

class _ModalParabens extends StatefulWidget {
  final AniversarianteModel aniversariante;
  final TextEditingController controller;
  final Future<void> Function(String mensagem) onEnviar;

  const _ModalParabens({
    required this.aniversariante,
    required this.controller,
    required this.onEnviar,
  });

  @override
  State<_ModalParabens> createState() => _ModalParabensState();
}

class _ModalParabensState extends State<_ModalParabens> {
  bool _enviando = false;

  static const _sugestoes = [
    '🎂 Feliz aniversário! Muitas felicidades!',
    '🥳 Parabéns! Que venham muitas conquistas!',
    '🎊 Feliz aniversário! Que seu dia seja especial!',
    '✨ Mais um ano de vida e conquistas. Parabéns!',
  ];

  @override
  Widget build(BuildContext context) {
    final a = widget.aniversariante;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cinzaTexto.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.laranja.withOpacity(0.15),
                  child: Text(
                    _iniciais(a.colaborador.nome),
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.laranja,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Parabenizar ${a.colaborador.primeiroNome}',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: AppColors.dark,
                        ),
                      ),
                      if (a.colaborador.setor != null)
                        Text(
                          a.colaborador.setor!,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.cinzaTexto,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Sugestões',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.cinzaTexto,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _sugestoes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => GestureDetector(
                  onTap: () =>
                      setState(() => widget.controller.text = _sugestoes[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.magenta.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.magenta.withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      _sugestoes[i],
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.magenta,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.controller,
              maxLines: 3,
              maxLength: 280,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Escreva sua mensagem...',
                hintStyle: GoogleFonts.poppins(color: AppColors.cinzaTexto),
                filled: true,
                fillColor: AppColors.cinzaClaro,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _enviando
                    ? null
                    : () async {
                        final msg = widget.controller.text.trim();
                        if (msg.isEmpty) return;
                        setState(() => _enviando = true);
                        await widget.onEnviar(msg);
                        if (mounted) Navigator.pop(context);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.magenta,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: _enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        '🎉 Enviar parabéns',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _iniciais(String nome) {
    final p = nome.trim().split(' ');
    return p.length >= 2
        ? '${p.first[0]}${p.last[0]}'.toUpperCase()
        : nome.isNotEmpty
        ? nome[0].toUpperCase()
        : '?';
  }
}
