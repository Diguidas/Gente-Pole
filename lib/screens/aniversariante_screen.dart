import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/aniversariante_model.dart';
import '../services/api_service.dart';
import '../widgets/avatar_colaborador.dart';

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
              color: AppColors.laranja,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
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
                              style: AppTextStyles.tituloBranco,
                            ),
                            Text(_mesAtual(), style: AppTextStyles.corpoBranco),
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
                    labelStyle: AppTextStyles.corpoBranco.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: AppTextStyles.corpoBranco,
                    labelColor: Colors.white,
                    unselectedLabelColor: const Color(0x8CFFFFFF),
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
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x599B5DE5),
                          blurRadius: 20,
                          offset: Offset(0, 8),
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
                                style: AppTextStyles.corpoBranco.copyWith(
                                  color: const Color(0xD9FFFFFF),
                                ),
                              ),
                              Text(
                                '${_api.colaboradorAtual?.primeiroNome ?? 'Polevalente'}! 🎉',
                                style: AppTextStyles.tituloGrande.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Que este novo ciclo seja incrível! ✨',
                                style: AppTextStyles.corpoMenor.copyWith(
                                  color: AppColors.brancoOp80,
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
                    child: Text('Hoje 🎉', style: AppTextStyles.labelSecao),
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
                    child: Text('Este mês', style: AppTextStyles.labelSecao),
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
                                  style: AppTextStyles.corpoBranco.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '${mensagens.length} pessoa${mensagens.length != 1 ? 's' : ''} te parabenizou!',
                                  style: AppTextStyles.corpoBranco.copyWith(
                                    color: const Color(0xD9FFFFFF),
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
                      style: AppTextStyles.labelSecao,
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
                    AvatarColaborador(fotoUrl: null, nome: remetente, raio: 20),
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
                                  style: AppTextStyles.corpoMedio,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (hora.isNotEmpty)
                                Text(hora, style: AppTextStyles.corpoMinimo),
                            ],
                          ),
                          if (setor != null)
                            Text(setor, style: AppTextStyles.corpoMinimo),
                          const SizedBox(height: 6),
                          Text(
                            texto,
                            style: AppTextStyles.corpoCinza.copyWith(
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
              decoration: const BoxDecoration(
                color: AppColors.magentaOp15,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('🎁', style: TextStyle(fontSize: 36)),
              ),
            ),
            const SizedBox(height: 20),
            Text('Aguarde seu dia!', style: AppTextStyles.tituloMedio),
            const SizedBox(height: 8),
            Text(
              dataFormatada.isNotEmpty
                  ? 'Seu aniversário é dia $dataFormatada.\nQuando chegar, você verá as mensagens aqui! 🎂'
                  : 'No seu aniversário, as mensagens dos seus colegas aparecerão aqui.',
              textAlign: TextAlign.center,
              style: AppTextStyles.corpoCinza.copyWith(height: 1.5),
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
              style: AppTextStyles.tituloGrande.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 12),
            Text(
              'Que este novo ciclo traga muita saúde,\nalegria e conquistas. Você merece! ✨',
              textAlign: TextAlign.center,
              style: AppTextStyles.corpoNormal.copyWith(
                color: AppColors.cinzaTexto,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.magentaOp15,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.magentaOp18),
              ),
              child: Text(
                'As mensagens dos seus colegas\naparecerão aqui ao longo do dia.',
                textAlign: TextAlign.center,
                style: AppTextStyles.corpoMenor.copyWith(
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
        color: AppColors.laranja,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40E91E8C),
            blurRadius: 16,
            offset: Offset(0, 6),
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
                    style: AppTextStyles.tituloPequeno.copyWith(
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (a.colaborador.setor != null)
                    Text(
                      a.colaborador.setor!,
                      style: AppTextStyles.corpoMenor.copyWith(
                        color: AppColors.brancoOp80,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Hoje é dia de celebrar! 🎊',
                    style: AppTextStyles.corpoMenor.copyWith(
                      color: const Color(0xE6FFFFFF),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  if (a.totalParabens > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${a.totalParabens} parabéns recebidos',
                        style: AppTextStyles.corpoMinimo.copyWith(
                          color: AppColors.brancoOp70,
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
                  color: jaParabenisei ? AppColors.brancoOp20 : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  jaParabenisei ? '✓ Enviado' : '🎉 Parabenizar',
                  style: AppTextStyles.corpoMenor.copyWith(
                    fontWeight: FontWeight.w700,
                    color: jaParabenisei
                        ? AppColors.brancoOp70
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
              color: AppColors.magentaOp15,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                dia.toString().padLeft(2, '0'),
                style: AppTextStyles.tituloMedio.copyWith(
                  color: AppColors.magenta,
                ),
              ),
            ),
          ),
          title: Text(
            pessoas.length == 1
                ? pessoas.first.colaborador.primeiroNome
                : '${pessoas.length} aniversariantes',
            style: AppTextStyles.corpoNormal.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: pessoas.length == 1
              ? Text(
                  pessoas.first.colaborador.setor ?? '',
                  style: AppTextStyles.corpoMenor,
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
                  style: AppTextStyles.corpoNormal.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (a.colaborador.setor != null)
                  Text(
                    a.colaborador.setor!,
                    style: AppTextStyles.corpoMenor,
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
                  style: AppTextStyles.corpoNormal.copyWith(
                    color: Colors.white,
                  ),
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
                  style: AppTextStyles.corpoNormal.copyWith(
                    color: Colors.white,
                  ),
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
    return AvatarColaborador(
      fotoUrl: colaborador.fotoUrl,
      nome: colaborador.nome,
      raio: raio,
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
        Text('Erro ao carregar', style: AppTextStyles.corpoCinza),
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
        Text('Nenhum aniversariante este mês', style: AppTextStyles.corpoCinza),
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
                  color: AppColors.cinzaTextoOp30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                AvatarColaborador(
                  fotoUrl: null,
                  nome: a.colaborador.nome,
                  raio: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Parabenizar ${a.colaborador.primeiroNome}',
                        style: AppTextStyles.tituloMedio.copyWith(fontSize: 17),
                      ),
                      if (a.colaborador.setor != null)
                        Text(
                          a.colaborador.setor!,
                          style: AppTextStyles.corpoMenor,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Sugestões',
              style: AppTextStyles.corpoMenor.copyWith(
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
                      color: AppColors.magentaOp15,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.magentaOp18),
                    ),
                    child: Text(
                      _sugestoes[i],
                      style: AppTextStyles.corpoMenor.copyWith(
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
              style: AppTextStyles.corpoNormal,
              decoration: InputDecoration(
                hintText: 'Escreva sua mensagem...',
                hintStyle: AppTextStyles.corpoCinza,
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
                        style: AppTextStyles.botaoPrimario,
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
