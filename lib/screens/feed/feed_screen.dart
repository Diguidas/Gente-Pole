// screens/feed/feed_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gentepole/core/app_theme.dart';
import 'package:gentepole/core/nivel_tempo_casa.dart';
import 'package:gentepole/core/pontos_bus.dart';
import 'package:gentepole/models/aniversariante_model.dart';
import 'package:gentepole/models/feed_post_model.dart';
import 'package:gentepole/screens/feedback/elogiar_screen.dart';
import 'package:gentepole/screens/gamificacao/gamificacao_screen.dart';
import 'package:gentepole/screens/login_screen.dart';
import 'package:gentepole/screens/pesquisa/pesquisa_list_screen.dart';
import 'package:gentepole/services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _douradoResposta = Color(0xFFB8860B);

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _api = ApiService();
  final _scrollCtrl = ScrollController();

  List<FeedPostModel> _posts = [];
  bool _carregando = true;
  bool _carregandoMais = false;
  bool _temMais = true;
  int _pagina = 0;

  // Prévia do feed: mostra só os primeiros posts + botão "Mostrar mais"
  // antes dos cards de celebração (aniversariantes/aniversário de
  // empresa/novos Polevalentes), pra não obrigar a rolar por eles pra
  // chegar no feed de verdade.
  static const _previaPostsCount = 5;
  int _quantidadePostsVisiveis = _previaPostsCount;

  // Humor
  Map<String, dynamic>? _humorHoje;

  // Exame periódico
  Map<String, dynamic>? _exameAgendado;

  // Banners RH (carrossel do topo)
  List<Map<String, dynamic>> _banners = [];

  // Aniversariantes / aniversário de empresa do mês (containers próprios,
  // separados do feed — ver _carregarFeed/isAniversario)
  List<AniversarianteModel> _aniversariantes = [];
  List<Map<String, dynamic>> _aniversariosEmpresa = [];

  // Colaboradores admitidos na semana corrente
  List<Map<String, dynamic>> _novosColaboradoresSemana = [];
  // Celebrações que EU recebi (tempo de empresa / novo polevalente) e ainda valem.
  List<Map<String, dynamic>> _celebracoesRecebidas = [];

  // Pesquisas ainda não respondidas pelo colaborador
  List<Map<String, dynamic>> _pesquisasPendentes = [];
  List<Map<String, dynamic>> _feedbacksPresenciaisPendentes = [];

  // Saldo de Polens (gamificação) — null enquanto carrega, pra não piscar "0"
  int? _meusPontos;
  bool _polecoinAtivo = true;

  RealtimeChannel? _statusChannel;

  @override
  void initState() {
    super.initState();
    _carregarPontos();
    _carregarFotoGentePole();
    _carregarFeed();
    _carregarHumor();
    _carregarExame();
    _carregarBanners();
    _carregarAniversarios();
    _carregarNovosColaboradoresSemana();
    _carregarCelebracoesRecebidas();
    _carregarPesquisasPendentes();
    _carregarFeedbacksPresenciaisPendentes();
    _scrollCtrl.addListener(_onScroll);
    _assinarStatusPosts();
    PontosBus.versao.addListener(_carregarPontos);
  }

  @override
  void dispose() {
    PontosBus.versao.removeListener(_carregarPontos);
    _statusChannel?.unsubscribe();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _assinarStatusPosts() {
    final meuId = _api.colaboradorAtual?.id;
    if (meuId == null) return;
    _statusChannel = Supabase.instance.client
        .channel('feed_status_$meuId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'feed_posts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'autor_id',
            value: meuId,
          ),
          callback: (payload) {
            final novo = payload.newRecord;
            final id = novo['id'] as int?;
            final novoStatus = novo['status'] as String?;
            if (id == null || novoStatus == null) return;
            if (!mounted) return;
            setState(() {
              _posts = _posts.map((p) {
                if (p.id == id) return p.copyWith(status: novoStatus);
                return p;
              }).toList();
            });
          },
        )
        .subscribe();
  }

  // ── Polens (gamificação) ─────────────────────────────────────────────────

  Future<void> _carregarFotoGentePole() async {
    try {
      final f = await _api.buscarFotoGentePole();
      if (!mounted || f == null) return;
      setState(() => _PostCard.fotoGentePole = f);
    } catch (_) {}
  }

  Future<void> _carregarPontos() async {
    try {
      final resultados = await Future.wait([
        _api.buscarMeusPontos(),
        _api.gamificacaoAtiva(),
      ]);
      if (!mounted) return;
      setState(() {
        _meusPontos = resultados[0] as int;
        _polecoinAtivo = resultados[1] as bool;
      });
    } catch (_) {
      // falha silenciosa — chip só não aparece
    }
  }

  // ── Humor ─────────────────────────────────────────────────────────────────────

  Future<void> _carregarHumor() async {
    try {
      final h = await _api.buscarHumorHoje();
      if (!mounted) return;
      setState(() => _humorHoje = h);
    } catch (_) {
      // falha silenciosa — card ainda é exibido
    }
  }

  Future<void> _carregarExame() async {
    try {
      final e = await _api.buscarProximoExamePeriodico();
      if (!mounted) return;
      setState(() => _exameAgendado = e);
    } catch (_) {}
  }

  Future<void> _carregarBanners() async {
    try {
      final b = await _api.listarBannersHome();
      if (!mounted) return;
      setState(() => _banners = b);
    } catch (_) {}
  }

  Future<void> _carregarAniversarios() async {
    try {
      final results = await Future.wait([
        _api.buscarAniversariantesMes(),
        _api.buscarAniversariosEmpresaMesColab(),
      ]);
      if (!mounted) return;
      setState(() {
        _aniversariantes = results[0] as List<AniversarianteModel>;
        _aniversariosEmpresa = results[1] as List<Map<String, dynamic>>;
      });
    } catch (_) {}
  }

  Future<void> _carregarCelebracoesRecebidas() async {
    try {
      final r = await _api.listarCelebracoesRecebidas();
      if (!mounted) return;
      setState(() => _celebracoesRecebidas = r);
    } catch (_) {}
  }

  /// Abre a folha de celebração de um card de tempo de empresa ou de novo
  /// polevalente (aniversariante tem o fluxo de parabéns próprio).
  void _abrirCelebracao({
    required String tipo,
    required Map<String, dynamic> pessoa,
    required String dataEvento,
    required String titulo,
    required String subtitulo,
  }) {
    final meuId = _api.colaboradorAtual?.id;
    final pessoaId = (pessoa['id'] as num?)?.toInt();
    if (meuId == null || pessoaId == null || pessoaId == meuId) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CelebracaoSheet(
        api: _api,
        meuId: meuId,
        tipo: tipo,
        colaboradorId: pessoaId,
        nome: pessoa['nome'] as String? ?? 'Colega',
        setor: pessoa['setor'] as String?,
        dataEvento: dataEvento,
        titulo: titulo,
        subtitulo: subtitulo,
      ),
    );
  }

  Future<void> _carregarNovosColaboradoresSemana() async {
    try {
      final n = await _api.buscarNovosColaboradoresSemana();
      if (!mounted) return;
      setState(() => _novosColaboradoresSemana = n);
    } catch (_) {}
  }

  Future<void> _carregarPesquisasPendentes() async {
    try {
      final p = await _api.buscarPesquisasDisponiveis();
      if (!mounted) return;
      setState(() {
        _pesquisasPendentes = p
            .where((e) => e['ja_respondeu'] != true)
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _carregarFeedbacksPresenciaisPendentes() async {
    final colaboradorId = _api.colaboradorAtual?.id;
    if (colaboradorId == null) return;
    try {
      final f = await _api.listarFeedbacksPresenciaisPendentes(colaboradorId);
      if (!mounted) return;
      setState(() => _feedbacksPresenciaisPendentes = f);
    } catch (_) {}
  }

  List<AniversarianteModel> get _aniversariantesHoje =>
      _aniversariantes.where((a) => a.ehHoje).toList();

  /// Aniversários de empresa de hoje, do maior tempo de casa ao menor (empate
  /// por nome).
  List<Map<String, dynamic>> get _aniversariosEmpresaHoje =>
      (_aniversariosEmpresa
          .where(
            (a) =>
                a['eh_hoje'] == true && (a['anos_completos'] as int? ?? 0) >= 1,
          )
          .toList())
        ..sort((a, b) {
          final anos = ((b['anos_completos'] as num?)?.toInt() ?? 0)
              .compareTo((a['anos_completos'] as num?)?.toInt() ?? 0);
          if (anos != 0) return anos;
          return (a['nome'] as String? ?? '')
              .compareTo(b['nome'] as String? ?? '');
        });

  Future<void> _registrarHumor(int nivel) async {
    const labels = ['Péssimo', 'Ruim', 'Ok', 'Bem', 'Ótimo'];
    final label = labels[nivel - 1];

    // Dialog perguntando o motivo
    final motivoCtrl = TextEditingController();
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Como você está?', style: AppTextStyles.tituloMedio),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Você selecionou: $label', style: AppTextStyles.corpoNormal),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              maxLines: 3,
              style: AppTextStyles.corpoNormal,
              decoration: InputDecoration(
                hintText: 'Por que você está assim? (opcional)',
                hintStyle: GoogleFonts.poppins(
                  color: AppColors.cinzaTexto.withOpacity(0.6),
                  fontSize: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: AppTextStyles.corpoCinza),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.magenta,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text('OK', style: AppTextStyles.botaoPrimario),
          ),
        ],
      ),
    );

    if (confirmou != true || !mounted) return;

    final motivo = motivoCtrl.text.trim();
    final ok = await _api.registrarHumor(
      nivel: nivel,
      motivo: motivo.isNotEmpty ? motivo : null,
    );
    if (!mounted) return;

    if (ok) {
      // Atualiza o card imediatamente sem esperar o DB
      if (mounted) setState(() => _humorHoje = {'nivel': nivel});
      _carregarHumor(); // sincroniza com DB em background

      // Cria post automático no feed. *nome* entre asteriscos é o mesmo
      // padrão usado nos posts de aniversário — o _PostCard reconhece e
      // destaca automaticamente.
      final colab = _api.colaboradorAtual;
      final nome = colab?.primeiroNome ?? 'Alguém';
      final conteudo = motivo.isNotEmpty
          ? '*$nome* está se sentindo $label\n\n$motivo'
          : '*$nome* está se sentindo $label';

      await _api.criarPost(
        conteudo: conteudo,
        destinatario: 'todos',
        tipo: 'humor',
        temTextoLivre: motivo.isNotEmpty,
      );
      _carregarFeed(reiniciar: true);
    }
  }

  // ── Feed ──────────────────────────────────────────────────────────────────────

  Future<void> _carregarFeed({bool reiniciar = false}) async {
    if (reiniciar) {
      setState(() {
        _pagina = 0;
        _temMais = true;
        _carregando = true;
        _posts = [];
      });
    }

    final novos = await _api.buscarFeed(pagina: _pagina);
    if (!mounted) return;

    setState(() {
      _posts.addAll(novos);
      _temMais = novos.length >= 20;
      _carregando = false;
      _carregandoMais = false;
    });
  }

  void _onScroll() {
    if (_carregandoMais || !_temMais) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      setState(() {
        _pagina++;
        _carregandoMais = true;
      });
      _carregarFeed();
    }
  }

  Future<void> _confirmarExclusao(FeedPostModel post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Excluir publicação?',
          style: AppTextStyles.tituloPequeno.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Essa ação não pode ser desfeita.',
          style: AppTextStyles.corpoNormal,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: AppTextStyles.corpoCinza),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Excluir', style: AppTextStyles.botaoPrimario),
          ),
        ],
      ),
    );
    if (ok == true) {
      final excluiu = await _api.excluirPost(post.id);
      if (excluiu && mounted) {
        setState(() => _posts.removeWhere((p) => p.id == post.id));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colaborador = _api.colaboradorAtual;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      body: Stack(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(28),
            ),
            child: Image.asset(
              'assets/banner_app.png',
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Header ────────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      _avatar(colaborador?.nome ?? '', colaborador?.fotoUrl),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Olá, ${colaborador?.primeiroNome ?? ''}',
                              style: AppTextStyles.tituloBranco,
                            ),
                            Text(
                              [colaborador?.cargo, colaborador?.setor]
                                  .where((e) => e != null && e.isNotEmpty)
                                  .join(' · '),
                              style: AppTextStyles.corpoBrancoOpaco,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      _headerIcon(
                        icon: Icons.logout_rounded,
                        tooltip: 'Sair',
                        onTap: () => _confirmarSaida(context),
                      ),
                    ],
                  ),
                ),

                // Chips matrícula + admissão + Polens
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                    children: [
                      _chip(
                        Icons.badge_outlined,
                        'Matrícula',
                        colaborador?.matricula ?? '—',
                      ),
                      const SizedBox(width: 10),
                      _chip(
                        Icons.calendar_today_outlined,
                        'Admissão',
                        colaborador?.dataAdmissaoFormatada ?? '—',
                      ),
                      if (_polecoinAtivo) ...[
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const GamificacaoScreen()),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.emoji_events_rounded,
                                    size: 13, color: Colors.white),
                                const SizedBox(width: 5),
                                Text(
                                  '$_meusPontos $nomeMoeda',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Feed ──────────────────────────────────────────────────────
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: _carregando
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.magenta,
                            ),
                          )
                        : RefreshIndicator(
                            color: AppColors.magenta,
                            onRefresh: () async {
                              await _carregarFeed(reiniciar: true);
                              await _carregarHumor();
                              await _carregarExame();
                              await _carregarBanners();
                              await _carregarAniversarios();
                              await _carregarPesquisasPendentes();
                            },
                            child: Builder(
                              builder: (ctx) {
                                final meuId = _api.colaboradorAtual?.id;
                                // Separa posts pendentes/rejeitados do próprio usuário
                                final meusPendentes = meuId == null
                                    ? <FeedPostModel>[]
                                    : _posts
                                          .where(
                                            (p) =>
                                                p.autorId == meuId &&
                                                !p.isAprovado,
                                          )
                                          .toList();
                                // Feed principal: aprovados + qualquer post de outros —
                                // exceto posts de aniversário (vida/empresa), que agora
                                // têm containers próprios no topo e não devem mais
                                // poluir o feed (mesma regra do _filtrarAprovados do
                                // gentepole_admin).
                                final feedPrincipal = _posts
                                    .where(
                                      (p) =>
                                          !p.isAniversario &&
                                          (p.isAprovado ||
                                              (meuId != null &&
                                                  p.autorId != meuId)),
                                    )
                                    .toList();

                                final temPendentes = meusPendentes.isNotEmpty;
                                final fixos = _buildItensFixos(
                                  meusPendentes: meusPendentes,
                                  temPendentes: temPendentes,
                                );

                                final postsVisiveis = feedPrincipal
                                    .take(_quantidadePostsVisiveis)
                                    .toList();
                                final restantes =
                                    feedPrincipal.length - postsVisiveis.length;
                                final mostrarBotaoMais = restantes > 0;

                                final itens = <Widget>[
                                  ...fixos,
                                  if (feedPrincipal.isEmpty) _vazioWidget(),
                                  ...postsVisiveis.map(
                                    (p) => _PostCard(
                                      post: p,
                                      meuId: meuId,
                                      onExcluir: () => _confirmarExclusao(p),
                                    ),
                                  ),
                                  if (mostrarBotaoMais)
                                    _buildBotaoMostrarMaisPosts(restantes),
                                  ..._buildItensCelebracao(),
                                ];

                                return ListView.builder(
                                  controller: _scrollCtrl,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    40,
                                  ),
                                  itemCount:
                                      itens.length + (_carregandoMais ? 1 : 0),
                                  itemBuilder: (_, i) {
                                    if (i < itens.length) return itens[i];
                                    return const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: AppColors.magenta,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
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

  // ── Pendentes / Rejeitados do próprio usuário ────────────────────────────────

  Widget _buildPendentesSection(List<FeedPostModel> posts) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  size: 16,
                  color: Color(0xFFB45309),
                ),
                const SizedBox(width: 6),
                Text(
                  posts.any((p) => p.isPendente)
                      ? 'Aguardando aprovação do RH'
                      : 'Publicações rejeitadas',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFFDE68A)),
          // Prévia: o post inteiro como vai aparecer no feed (foto, texto
          // formatado, menções, destinatário), não só um trecho.
          ...posts.map(
            (p) => Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.isPendente
                                ? 'É assim que vai aparecer no feed depois de aprovado'
                                : (p.motivoRejeicao != null &&
                                        p.motivoRejeicao!.isNotEmpty
                                    ? 'Post rejeitado pelo RH. Motivo: ${p.motivoRejeicao}'
                                    : 'Este post foi rejeitado pelo RH'),
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: p.isPendente
                                  ? const Color(0xFFB45309)
                                  : const Color(0xFFB91C1C),
                            ),
                          ),
                        ),
                        if (p.isRejeitado)
                          GestureDetector(
                            onTap: () => _confirmarExclusao(p),
                            child: const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: Color(0xFFB91C1C),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _PostCard(
                    post: p,
                    meuId: _api.colaboradorAtual?.id,
                    onExcluir: () {},
                    preview: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Exame Card ────────────────────────────────────────────────────────────────

  Widget _buildExameCard(Map<String, dynamic> exame) {
    final dataRaw = exame['data_agendamento'] as String?;
    String dataFormatada = '—';
    if (dataRaw != null) {
      final dt = DateTime.tryParse(dataRaw);
      if (dt != null) {
        dataFormatada =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      }
    }
    final clinica = exame['clinica'] as String?;
    final obs = exame['observacoes'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFB923C).withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFB923C).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFB923C).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.medical_services_outlined,
              color: Color(0xFFF97316),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Exame Periódico Agendado',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFC2410C),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFB923C).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Lembrete',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFEA580C),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$dataFormatada${clinica != null ? '  ·  $clinica' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF92400E),
                  ),
                ),
                if (obs != null && obs.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    obs,
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF92400E).withOpacity(0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Itens fixos do topo do feed ──────────────────────────────────────────────
  // Ordem: banner RH → humor → pesquisas pendentes → exame → composer →
  // pendentes/rejeitados. Os cards de celebração (aniversariantes/
  // aniversário de empresa/novos Polevalentes) NÃO entram aqui — eles vão
  // depois da prévia do feed (ver _buildItensCelebracao), pra não obrigar a
  // rolar por eles antes de chegar nos posts de verdade.

  List<Widget> _buildItensFixos({
    required List<FeedPostModel> meusPendentes,
    required bool temPendentes,
  }) {
    return [
      if (_banners.isNotEmpty) _buildBannerHome(),
      _buildHumorCard(),
      if (_celebracoesRecebidas.isNotEmpty) _buildCelebracoesRecebidasCard(),
      if (_feedbacksPresenciaisPendentes.isNotEmpty) _buildFeedbackPresencialPendenteCard(),
      if (_pesquisasPendentes.isNotEmpty) _buildPesquisasPendentesCard(),
      if (_exameAgendado != null) _buildExameCard(_exameAgendado!),
      _InlineComposer(
        api: _api,
        onPublicado: () => _carregarFeed(reiniciar: true),
      ),
      if (temPendentes) _buildPendentesSection(meusPendentes),
    ];
  }

  // ── Cards de celebração (aparecem só depois da prévia do feed) ───────────────

  List<Widget> _buildItensCelebracao() {
    return [
      if (_aniversariantesHoje.isNotEmpty) _buildAniversariantesCard(),
      if (_aniversariosEmpresaHoje.isNotEmpty) _buildAniversarioEmpresaCard(),
      if (_novosColaboradoresSemana.isNotEmpty) _buildNovosPolevalentesCard(),
    ];
  }

  Widget _buildBotaoMostrarMaisPosts(int restantes) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () =>
              setState(() => _quantidadePostsVisiveis += _previaPostsCount),
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          label: Text(
            'Mostrar mais posts ($restantes)',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.magenta,
            side: const BorderSide(color: AppColors.magenta),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  // ── Banner RH (carrossel) ─────────────────────────────────────────────────────

  Widget _buildBannerHome() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      // Proporção da imagem cadastrada no RH (1128x191) — evita cortar ou
      // distorcer o banner independente da largura da tela.
      child: AspectRatio(
        aspectRatio: 1128 / 191,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: _banners.length == 1
              ? Image.network(
                  _banners.first['url'] as String,
                  fit: BoxFit.cover,
                  width: double.infinity,
                )
              : _BannerCarrossel(banners: _banners),
        ),
      ),
    );
  }

  // ── Aniversariantes / aniversário de empresa de hoje ─────────────────────────

  Widget _buildAniversariantesCard() {
    final hoje = _aniversariantesHoje;
    final meuSetor = _api.colaboradorAtual?.setor;
    return _CardAniversarioMes(
      titulo: 'Aniversariantes de hoje',
      itens: hoje
          .map(
            (a) => _LinhaAniversario(
              nome: a.colaborador.nome,
              setor: a.colaborador.setor,
              fotoUrl: a.colaborador.fotoUrl,
              cor: AppColors.magenta,
              mensagem: 'Feliz aniversário!',
              destaqueMeuSetor: meuSetor != null &&
                  meuSetor.isNotEmpty &&
                  a.colaborador.setor == meuSetor,
            ),
          )
          .toList(),
    );
  }

  Widget _buildAniversarioEmpresaCard() {
    final hoje = _aniversariosEmpresaHoje;
    return _CardAniversarioMes(
      titulo: 'Aniversário de empresa hoje',
      itens: hoje.map((a) {
        final anos = (a['anos_completos'] as num?)?.toInt() ?? 0;
        final nivel = NivelTempoCasa.deCategoria(
          NivelTempoCasa.categoriaDeAnos(anos),
        );
        return _LinhaAniversario(
          nome: a['nome'] as String? ?? '—',
          setor: a['setor'] as String?,
          fotoUrl: a['foto_url'] as String?,
          cor: nivel?.cor ?? AppColors.laranja,
          mensagem: '$anos ${anos == 1 ? 'ano' : 'anos'} de empresa',
          nivel: nivel,
          onTap: (a['id'] as num?)?.toInt() == _api.colaboradorAtual?.id
              ? null
              : () => _abrirCelebracao(
                    tipo: 'tempo_empresa',
                    pessoa: a,
                    dataEvento: ApiService.dataHojeIso(),
                    titulo:
                        'Celebrar ${(a['nome'] as String? ?? '').split(' ').first}',
                    subtitulo:
                        '$anos ${anos == 1 ? 'ano' : 'anos'} de empresa',
                  ),
        );
      }).toList(),
    );
  }

  Widget _buildNovosPolevalentesCard() {
    return _CardAniversarioMes(
      titulo: 'Novos Polevalentes essa semana',
      itens: _novosColaboradoresSemana.map((c) {
        final dataAdmissao = DateTime.tryParse(
          c['data_admissao'] as String? ?? '',
        );
        final dataFormatada = dataAdmissao != null
            ? '${dataAdmissao.day.toString().padLeft(2, '0')}/${dataAdmissao.month.toString().padLeft(2, '0')}'
            : '';
        return _LinhaAniversario(
          nome: c['nome'] as String? ?? '—',
          setor: c['setor'] as String?,
          fotoUrl: c['foto_url'] as String?,
          cor: AppColors.laranja,
          mensagem: dataFormatada.isNotEmpty
              ? 'Chegou dia $dataFormatada'
              : 'Seja bem-vindo(a)!',
          onTap: (c['id'] as num?)?.toInt() == _api.colaboradorAtual?.id ||
                  c['data_admissao'] == null
              ? null
              : () => _abrirCelebracao(
                    tipo: 'novo_colaborador',
                    pessoa: c,
                    dataEvento: c['data_admissao'] as String,
                    titulo:
                        'Boas-vindas, ${(c['nome'] as String? ?? '').split(' ').first}!',
                    subtitulo: dataFormatada.isNotEmpty
                        ? 'Chegou dia $dataFormatada'
                        : 'Novo polevalente',
                  ),
        );
      }).toList(),
    );
  }

  /// Card (só de quem foi celebrado) com quem celebrou e as mensagens. Só
  /// existe se pelo menos uma pessoa celebrou.
  Widget _buildCelebracoesRecebidasCard() {
    return Column(
      children: [
        for (final g in _celebracoesRecebidas)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.laranja.withOpacity(0.35)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 10,
                    offset: Offset(0, 3)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g['tipo'] == 'tempo_empresa'
                      ? '🎉 Celebraram seu tempo de Pole!'
                      : '👋 Deram boas-vindas a você!',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 10),
                for (final c in (g['celebracoes'] as List))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _avatarCelebracao(c['autor'] as Map?),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (c['autor']?['nome'] as String?) ?? 'Alguém',
                                style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.dark,
                                ),
                              ),
                              Text(
                                c['mensagem'] as String? ?? '',
                                style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  color: AppColors.cinzaTexto,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Feedback presencial pendente de confirmação ───────────────────────────────

  Widget _buildFeedbackPresencialPendenteCard() {
    final qtd = _feedbacksPresenciaisPendentes.length;
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ElogiarScreen()),
        );
        _carregarFeedbacksPresenciaisPendentes();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.groups_outlined, color: Color(0xFFF59E0B)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    qtd == 1
                        ? 'Confirme 1 feedback presencial'
                        : 'Confirme $qtd feedbacks presenciais',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Seu gestor marcou que essa conversa foi presencial — confirme ou negue.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.cinzaTexto,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFF59E0B)),
          ],
        ),
      ),
    );
  }

  // ── Pesquisas pendentes (nudge) ───────────────────────────────────────────────

  Widget _buildPesquisasPendentesCard() {
    final qtd = _pesquisasPendentes.length;
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PesquisaListScreen()),
        );
        _carregarPesquisasPendentes();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.magenta.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.magenta.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.magenta.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.poll_outlined, color: AppColors.magenta),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    qtd == 1
                        ? 'Você tem 1 pesquisa para responder'
                        : 'Você tem $qtd pesquisas para responder',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sua opinião ajuda a Pole a melhorar',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.cinzaTexto,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.magenta),
          ],
        ),
      ),
    );
  }

  // ── Humor Card ────────────────────────────────────────────────────────────────

  Widget _buildHumorCard() {
    return _HumorCard(humorHoje: _humorHoje, onRegistrar: _registrarHumor);
  }

  // ── Widgets auxiliares ────────────────────────────────────────────────────────

  Widget _vazioWidget() => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dynamic_feed_rounded,
            size: 64,
            color: AppColors.cinzaTexto.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma publicação ainda',
            style: AppTextStyles.corpoCinza.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Seja o primeiro a publicar algo!',
            style: AppTextStyles.corpoCinza,
          ),
        ],
      ),
    ),
  );

  Widget _avatar(String nome, String? fotoUrl) {
    if (fotoUrl != null && fotoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: CachedNetworkImageProvider(fotoUrl),
      );
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.white.withOpacity(0.3),
      child: Text(
        _iniciais(nome),
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _headerIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    icon: Icon(icon, color: Colors.white),
  );

  Widget _chip(IconData icon, String label, String valor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.18),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white70),
        const SizedBox(width: 5),
        Text(
          '$label: $valor',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  String _iniciais(String nome) {
    final p = nome.trim().split(' ');
    return p.length >= 2
        ? '${p.first[0]}${p.last[0]}'.toUpperCase()
        : nome.isNotEmpty
        ? nome[0].toUpperCase()
        : '?';
  }

  // ── Modais ────────────────────────────────────────────────────────────────────

  void _confirmarSaida(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Sair da conta?',
          style: AppTextStyles.tituloPequeno.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Você precisará digitar seu CPF e senha novamente.',
          style: AppTextStyles.corpoNormal,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: AppTextStyles.corpoCinza),
          ),
          ElevatedButton(
            onPressed: () async {
              await _api.limparSessao();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            child: Text('Sair', style: AppTextStyles.botaoPrimario),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// _MencaoController — destaca @menções em tempo real no TextField
// ════════════════════════════════════════════════════════════════════════════════

class _MencaoController extends TextEditingController {
  // Armazena os labels de menções confirmadas (ex: "@HELIO PESSOA DE LIMA FILHO")
  final Set<String> _mentionLabels = {};

  void addMention(String label) => _mentionLabels.add(label);
  void clearMentions() => _mentionLabels.clear();

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final txt = text;
    if (_mentionLabels.isEmpty || txt.isEmpty) {
      return TextSpan(text: txt, style: style);
    }

    final mencaoStyle = (style ?? const TextStyle()).copyWith(
      color: AppColors.magenta,
      fontWeight: FontWeight.w700,
      backgroundColor: AppColors.magenta.withOpacity(0.1),
    );

    // Regex que bate exatamente nos labels confirmados
    final escaped = _mentionLabels.map(RegExp.escape).join('|');
    final regex = RegExp(escaped);
    final matches = regex.allMatches(txt).toList();
    if (matches.isEmpty) return TextSpan(text: txt, style: style);

    final spans = <TextSpan>[];
    int last = 0;
    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: txt.substring(last, m.start), style: style));
      }
      spans.add(TextSpan(text: m.group(0)!, style: mencaoStyle));
      last = m.end;
    }
    if (last < txt.length) {
      spans.add(TextSpan(text: txt.substring(last), style: style));
    }
    return TextSpan(children: spans);
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// _InlineComposer — card de composição de post inline no feed
// ════════════════════════════════════════════════════════════════════════════════

class _InlineComposer extends StatefulWidget {
  final ApiService api;
  final VoidCallback onPublicado;

  const _InlineComposer({required this.api, required this.onPublicado});

  @override
  State<_InlineComposer> createState() => _InlineComposerState();
}

class _InlineComposerState extends State<_InlineComposer> {
  final _ctrl = _MencaoController();
  final _focusNode = FocusNode();

  List<int>? _imagemBytes;
  String? _imagemNome;

  String _destinatario = 'todos';
  String _destinatarioLabel = 'Todos';

  // "Para:" (quem vê o post) — separado das @marcações do texto, como no
  // painel web: o @ só marca/notifica a pessoa; o "Para" é o direcionamento.
  String _tipoDestino = 'todos'; // 'todos' | 'setor' | 'pessoas'
  Set<String> _setoresSel = {};
  List<({String id, String nome})> _pessoasSel = [];
  List<String>? _setoresDisponiveis;

  bool _showSugestoes = false;
  List<Map<String, String>> _sugestoes = [];
  bool _buscandoSugestoes = false;
  String _queryMencao = '';

  bool _enviando = false;
  bool _expandido = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextoMudou);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && !_expandido) {
        setState(() => _expandido = true);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextoMudou);
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Posição do @ ativo (início) e fim da última menção confirmada
  int _mencaoStart = -1;
  int _mencaoEnd =
      -1; // posição após o último label inserido; ignora @s anteriores

  /// Recalcula `_destinatario`/rótulo a partir da escolha no seletor "Para".
  void _atualizarDestino() {
    switch (_tipoDestino) {
      case 'setor':
        final lista = _setoresSel.toList()..sort();
        _destinatario = lista.isEmpty ? 'todos' : '@setor:${lista.join(',')}';
        _destinatarioLabel = lista.map((x) => '@$x').join(', ');
      case 'pessoas':
        if (_pessoasSel.isEmpty) {
          _destinatario = 'todos';
          _destinatarioLabel = 'Todos';
        } else {
          _destinatario =
              '@colaborador:${_pessoasSel.map((x) => x.id).join(',')}|${_pessoasSel.map((x) => x.nome).join(', ')}';
          _destinatarioLabel = _pessoasSel.map((x) => '@${x.nome}').join(', ');
        }
      default:
        _destinatario = 'todos';
        _destinatarioLabel = 'Todos';
    }
  }

  Future<void> _abrirSeletorDestino() async {
    _setoresDisponiveis ??= await widget.api.listarSetoresDistintos()
      ..sort();
    if (!mounted) return;
    final r = await showModalBottomSheet<_DestinoEscolhido>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SeletorDestinoSheet(
        api: widget.api,
        setores: _setoresDisponiveis ?? const [],
        tipo: _tipoDestino,
        setoresSel: _setoresSel,
        pessoasSel: _pessoasSel,
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      _tipoDestino = r.tipo;
      _setoresSel = r.setores;
      _pessoasSel = r.pessoas;
      _atualizarDestino();
    });
  }

  void _onTextoMudou() {
    setState(() {});
    final texto = _ctrl.text;
    final cursor = _ctrl.selection.baseOffset;
    if (cursor < 0) return;

    final antes = texto.substring(0, cursor);
    // Só procura @ que aparece DEPOIS do fim da última menção confirmada
    final buscaFrom = _mencaoEnd > 0 ? _mencaoEnd.clamp(0, antes.length) : 0;
    final regiao = antes.substring(buscaFrom);

    final match = RegExp(r'@').allMatches(regiao).lastOrNull;
    if (match != null) {
      final absStart = buscaFrom + match.start;
      final fragmento = antes.substring(absStart);
      if (!fragmento.contains('\n')) {
        final query = fragmento.substring(1);
        // Dispara sugestões mesmo para query vazia (logo após o @)
        if (_mencaoStart != absStart || query != _queryMencao) {
          _mencaoStart = absStart;
          _queryMencao = query;
          _buscarSugestoes(query);
        }
        return;
      }
    }

    if (_showSugestoes) {
      setState(() {
        _showSugestoes = false;
        _sugestoes = [];
        _mencaoStart = -1;
      });
    }
  }

  Future<void> _buscarSugestoes(String query) async {
    setState(() => _buscandoSugestoes = true);
    final resultados = (await widget.api.buscarSugestoesMencao(query))
        .where((r) => r['tipo'] != 'todos')
        .toList();
    if (!mounted) return;
    setState(() {
      _sugestoes = resultados;
      _showSugestoes = resultados.isNotEmpty;
      _buscandoSugestoes = false;
    });
  }

  /// Insere a marcação no texto — NÃO mexe no "Para:". Nomes com espaço ficam
  /// entre colchetes (`@[Nome Completo]`), que é o formato que o servidor
  /// reconhece pra mandar o push/sino pra pessoa marcada.
  void _selecionarMencao(Map<String, String> sugestao) {
    final nome = sugestao['label']!.replaceFirst('@', '');
    final marcado = nome.contains(' ') ? '@[$nome]' : '@$nome';
    final texto = _ctrl.text;
    final cursor = _ctrl.selection.baseOffset;
    final depois = texto.substring(cursor);
    final novoAntes = _mencaoStart >= 0
        ? '${texto.substring(0, _mencaoStart)}$marcado '
        : texto.substring(0, cursor).replaceAll(RegExp(r'@\S*$'), '$marcado ');

    // Registra o trecho pro controller destacá-lo no campo de texto
    _ctrl.addMention(marcado);

    _ctrl.value = TextEditingValue(
      text: novoAntes + depois,
      selection: TextSelection.collapsed(offset: novoAntes.length),
    );
    setState(() {
      _showSugestoes = false;
      _sugestoes = [];
      _mencaoStart = -1;
      _mencaoEnd = novoAntes.length; // ignora @s anteriores a este ponto
    });
  }

  static const int _limiteImagemBytes = 2 * 1024 * 1024; // 2 MB

  Future<void> _escolherImagem() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _limiteImagemBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imagem muito grande (máx. 2 MB). Escolha outra foto.',
            style: AppTextStyles.corpoNormal.copyWith(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      _imagemBytes = bytes;
      _imagemNome = picked.name;
      _expandido = true;
    });
  }

  void _removerImagem() => setState(() {
    _imagemBytes = null;
    _imagemNome = null;
  });

  Future<void> _publicar() async {
    final conteudo = _ctrl.text.trim();
    if (conteudo.isEmpty && _imagemBytes == null) return;

    setState(() => _enviando = true);

    final ok = await widget.api.criarPost(
      conteudo: conteudo,
      destinatario: _destinatario,
      imagemBytes: _imagemBytes,
      imagemNome: _imagemNome,
    );

    if (!mounted) return;
    if (ok) {
      _ctrl.clear();
      _ctrl.clearMentions();
      final pendente = _destinatario == 'todos';
      setState(() {
        _imagemBytes = null;
        _imagemNome = null;
        _tipoDestino = 'todos';
        _setoresSel = {};
        _pessoasSel = [];
        _destinatario = 'todos';
        _mencaoEnd = -1;
        _destinatarioLabel = 'Todos';
        _enviando = false;
        _expandido = false;
      });
      _focusNode.unfocus();
      widget.onPublicado();
      if (pendente && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Post enviado para aprovação do RH.',
              style: AppTextStyles.corpoNormal.copyWith(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao publicar. Tente novamente.',
            style: AppTextStyles.corpoNormal.copyWith(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colab = widget.api.colaboradorAtual;
    final temConteudo = _ctrl.text.trim().isNotEmpty || _imagemBytes != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _avatarWidget(colab?.nome ?? '', colab?.fotoUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // "Para:" — sempre visível; toque abre o seletor
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _abrirSeletorDestino,
                          child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.magenta.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.magenta.withOpacity(0.25),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _destinatario == 'todos'
                                    ? Icons.public_rounded
                                    : _destinatario.startsWith('@setor:')
                                    ? Icons.group_rounded
                                    : Icons
                                          .person_rounded, // @colaborador:id|nome
                                size: 13,
                                color: AppColors.magenta,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                _destinatario == 'todos'
                                    ? 'Para todos'
                                    : _destinatarioLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  color: AppColors.magenta,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              ),
                              const SizedBox(width: 4),
                              if (_destinatario != 'todos')
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() {
                                    _tipoDestino = 'todos';
                                    _setoresSel = {};
                                    _pessoasSel = [];
                                    _atualizarDestino();
                                  }),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: AppColors.magenta,
                                  ),
                                )
                              else
                                Icon(
                                  Icons.expand_more_rounded,
                                  size: 14,
                                  color: AppColors.magenta,
                                ),
                            ],
                          ),
                        ),
                        ),
                      ),

                      // Campo de texto
                      TextField(
                        controller: _ctrl,
                        focusNode: _focusNode,
                        maxLines: _expandido ? null : 1,
                        minLines: _expandido ? 3 : 1,
                        style: AppTextStyles.corpoNormal,
                        decoration: InputDecoration(
                          hintText: 'No que você está pensando?',
                          hintStyle: GoogleFonts.poppins(
                            color: AppColors.cinzaTexto.withOpacity(0.6),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),

                      // Sugestões de @menção
                      if (_showSugestoes) ...[
                        const SizedBox(height: 8),
                        _buildSugestoes(),
                      ],

                      // Preview da imagem
                      if (_imagemBytes != null) ...[
                        const SizedBox(height: 12),
                        Stack(
                          alignment: Alignment.topRight,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                Uint8List.fromList(_imagemBytes!),
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            GestureDetector(
                              onTap: _removerImagem,
                              child: Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Barra de ações (só aparece expandido)
          if (_expandido) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  _actionBtn(Icons.image_outlined, 'Foto', _escolherImagem),
                  const SizedBox(width: 8),
                  _actionBtn(Icons.alternate_email_rounded, 'Mencionar', () {
                    final offset = _ctrl.selection.baseOffset.clamp(
                      0,
                      _ctrl.text.length,
                    );
                    final texto = _ctrl.text;
                    _ctrl.value = TextEditingValue(
                      text:
                          '${texto.substring(0, offset)}@${texto.substring(offset)}',
                      selection: TextSelection.collapsed(offset: offset + 1),
                    );
                    _focusNode.requestFocus();
                  }),
                  const Spacer(),
                  _enviando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.magenta,
                          ),
                        )
                      : TextButton(
                          onPressed: temConteudo ? _publicar : null,
                          style: TextButton.styleFrom(
                            backgroundColor: temConteudo
                                ? AppColors.magenta
                                : AppColors.cinzaTexto.withOpacity(0.15),
                            foregroundColor: temConteudo
                                ? Colors.white
                                : AppColors.cinzaTexto,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            'Publicar',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSugestoes() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: _buscandoSugestoes
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.magenta,
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sugestoes.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
              itemBuilder: (_, i) {
                final s = _sugestoes[i];
                final tipo = s['tipo']!;
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: tipo == 'setor'
                        ? AppColors.laranja.withOpacity(0.15)
                        : tipo == 'todos'
                        ? AppColors.magenta.withOpacity(0.15)
                        : const Color(0xFFEEEEEE),
                    child: Icon(
                      tipo == 'setor'
                          ? Icons.group_rounded
                          : tipo == 'todos'
                          ? Icons.people_alt_rounded
                          : Icons.person_rounded,
                      size: 18,
                      color: tipo == 'setor'
                          ? AppColors.laranja
                          : AppColors.magenta,
                    ),
                  ),
                  title: Text(
                    s['label']!,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: s['sublabel']!.isNotEmpty
                      ? Text(
                          s['sublabel']!,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AppColors.cinzaTexto,
                          ),
                        )
                      : null,
                  onTap: () => _selecionarMencao(s),
                );
              },
            ),
    );
  }

  Widget _avatarWidget(String nome, String? fotoUrl) {
    if (fotoUrl != null && fotoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: CachedNetworkImageProvider(fotoUrl),
      );
    }
    final iniciais = () {
      final p = nome.trim().split(' ');
      return p.length >= 2
          ? '${p.first[0]}${p.last[0]}'.toUpperCase()
          : nome.isNotEmpty
          ? nome[0].toUpperCase()
          : '?';
    }();
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.magenta,
      child: Text(
        iniciais,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.cinzaTexto),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.cinzaTexto,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
}

class _DestinoEscolhido {
  final String tipo; // 'todos' | 'setor' | 'pessoas'
  final Set<String> setores;
  final List<({String id, String nome})> pessoas;
  const _DestinoEscolhido(this.tipo, this.setores, this.pessoas);
}

/// Seletor do "Para:" do post — mesmas opções do painel web: Todos, Por setor
/// (vários) e Pessoas (várias).
class _SeletorDestinoSheet extends StatefulWidget {
  final ApiService api;
  final List<String> setores;
  final String tipo;
  final Set<String> setoresSel;
  final List<({String id, String nome})> pessoasSel;

  const _SeletorDestinoSheet({
    required this.api,
    required this.setores,
    required this.tipo,
    required this.setoresSel,
    required this.pessoasSel,
  });

  @override
  State<_SeletorDestinoSheet> createState() => _SeletorDestinoSheetState();
}

class _SeletorDestinoSheetState extends State<_SeletorDestinoSheet> {
  late String _tipo = widget.tipo;
  late final Set<String> _setores = {...widget.setoresSel};
  late final List<({String id, String nome})> _pessoas = [...widget.pessoasSel];
  final _buscaSetorCtrl = TextEditingController();
  final _buscaPessoaCtrl = TextEditingController();
  List<Map<String, dynamic>> _resultados = [];
  bool _buscando = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaSetorCtrl.dispose();
    _buscaPessoaCtrl.dispose();
    super.dispose();
  }

  void _buscarPessoas(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _resultados = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _buscando = true);
      final r = await widget.api.buscarColaboradoresParaDestinatario(q.trim());
      if (!mounted) return;
      setState(() {
        _resultados = r;
        _buscando = false;
      });
    });
  }

  bool get _valido => switch (_tipo) {
        'setor' => _setores.isNotEmpty,
        'pessoas' => _pessoas.isNotEmpty,
        _ => true,
      };

  void _alternarPessoa(String id, String nome) {
    setState(() {
      final i = _pessoas.indexWhere((p) => p.id == id);
      if (i >= 0) {
        _pessoas.removeAt(i);
      } else {
        _pessoas.add((id: id, nome: nome));
      }
    });
  }

  Widget _opcaoTipo(String valor, String rotulo, IconData icone) {
    final sel = _tipo == valor;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tipo = valor),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel
                ? AppColors.magenta.withOpacity(0.1)
                : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: sel ? AppColors.magenta : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(icone,
                  size: 20,
                  color: sel ? AppColors.magenta : AppColors.cinzaTexto),
              const SizedBox(height: 4),
              Text(
                rotulo,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel ? AppColors.magenta : AppColors.cinzaTexto,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final termoSetor = _buscaSetorCtrl.text.trim().toLowerCase();
    final setoresFiltrados = widget.setores
        .where((x) => termoSetor.isEmpty || x.toLowerCase().contains(termoSetor))
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Para quem vai esse post?', style: AppTextStyles.tituloMedio),
            const SizedBox(height: 4),
            Text(
              'Use @ no texto para marcar alguém sem mudar quem vê o post.',
              style: AppTextStyles.corpoCinza,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _opcaoTipo('todos', 'Todos', Icons.public_rounded),
                const SizedBox(width: 8),
                _opcaoTipo('setor', 'Por setor', Icons.group_rounded),
                const SizedBox(width: 8),
                _opcaoTipo('pessoas', 'Pessoas', Icons.person_rounded),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_tipo == 'todos')
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Precisa de aprovação do RH antes de aparecer no feed.',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: const Color(0xFFB45309),
                          ),
                        ),
                      ),
                    if (_tipo == 'setor') ...[
                      TextField(
                        controller: _buscaSetorCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Buscar setor...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final x in setoresFiltrados)
                            FilterChip(
                              label: Text('@$x',
                                  style: GoogleFonts.poppins(fontSize: 12)),
                              selected: _setores.contains(x),
                              selectedColor:
                                  AppColors.laranja.withOpacity(0.15),
                              checkmarkColor: AppColors.laranja,
                              onSelected: (v) => setState(() {
                                v ? _setores.add(x) : _setores.remove(x);
                              }),
                            ),
                        ],
                      ),
                    ],
                    if (_tipo == 'pessoas') ...[
                      if (_pessoas.isNotEmpty) ...[
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final pe in _pessoas)
                              InputChip(
                                avatar: const Icon(Icons.person_rounded,
                                    size: 14, color: AppColors.magenta),
                                label: Text(pe.nome,
                                    style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: AppColors.magenta,
                                        fontWeight: FontWeight.w600)),
                                backgroundColor:
                                    AppColors.magenta.withOpacity(0.08),
                                onDeleted: () => _alternarPessoa(pe.id, pe.nome),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: _buscaPessoaCtrl,
                        onChanged: _buscarPessoas,
                        decoration: InputDecoration(
                          hintText: _pessoas.isEmpty
                              ? 'Buscar pessoas pelo nome...'
                              : 'Adicionar mais pessoas...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (_buscando)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: LinearProgressIndicator(
                              color: AppColors.magenta),
                        ),
                      for (final c in _resultados)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor:
                                AppColors.magenta.withOpacity(0.12),
                            child: Text(
                              (c['nome'] as String? ?? '?').isNotEmpty
                                  ? (c['nome'] as String)[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.magenta,
                              ),
                            ),
                          ),
                          title: Text(c['nome'] as String? ?? '',
                              style: GoogleFonts.poppins(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text(c['setor'] as String? ?? '',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: AppColors.cinzaTexto)),
                          trailing: _pessoas.any((x) => x.id == '${c['id']}')
                              ? const Icon(Icons.check_circle_rounded,
                                  color: AppColors.magenta, size: 18)
                              : null,
                          onTap: () {
                            _alternarPessoa(
                                '${c['id']}', c['nome'] as String? ?? '');
                            setState(() {
                              _resultados = [];
                              _buscaPessoaCtrl.clear();
                            });
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _valido
                    ? () => Navigator.pop(
                          context,
                          _DestinoEscolhido(_tipo, _setores, _pessoas),
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.magenta,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text('Concluir',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// _HumorCard — widget separado para garantir tap correto dentro de ListView
// ════════════════════════════════════════════════════════════════════════════════

class _HumorCard extends StatefulWidget {
  final Map<String, dynamic>? humorHoje;
  final Future<void> Function(int nivel) onRegistrar;

  const _HumorCard({required this.humorHoje, required this.onRegistrar});

  @override
  State<_HumorCard> createState() => _HumorCardState();
}

class _HumorCardState extends State<_HumorCard> {
  bool _salvando = false;

  @override
  Widget build(BuildContext context) {
    const humorIcones = [
      Icons.sentiment_very_dissatisfied_rounded,
      Icons.sentiment_dissatisfied_rounded,
      Icons.sentiment_neutral_rounded,
      Icons.sentiment_satisfied_rounded,
      Icons.sentiment_very_satisfied_rounded,
    ];
    const labels = ['Péssimo', 'Ruim', 'Ok', 'Bem', 'Ótimo'];
    final jaRegistrou = widget.humorHoje != null;
    final nivelAtual = jaRegistrou
        ? (widget.humorHoje!['nivel'] as int? ?? 0)
        : -1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mood_outlined, size: 16, color: AppColors.magenta),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  jaRegistrou
                      ? 'Humor de hoje: ${labels[nivelAtual - 1]}'
                      : 'Como você está hoje?',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.dark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_salvando) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.magenta,
                  ),
                ),
              ],
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(5, (idx) {
              final nivel = idx + 1;
              final selecionado = nivelAtual == nivel;
              return TextButton(
                onPressed: (jaRegistrou || _salvando)
                    ? null
                    : () async {
                        // _registrarHumor já mostra o dialog e salva
                        await widget.onRegistrar(nivel);
                      },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: selecionado
                      ? AppColors.magenta.withOpacity(0.12)
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: selecionado
                        ? BorderSide(
                            color: AppColors.magenta.withOpacity(0.4),
                            width: 1.5,
                          )
                        : BorderSide.none,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      humorIcones[idx],
                      size: selecionado ? 30 : 26,
                      color: jaRegistrou && !selecionado
                          ? Colors.black.withOpacity(0.25)
                          : AppColors.magenta,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      labels[idx],
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: selecionado
                            ? AppColors.magenta
                            : jaRegistrou
                            ? AppColors.cinzaTexto.withOpacity(0.5)
                            : AppColors.cinzaTexto,
                        fontWeight: selecionado
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// _PostCard
// ════════════════════════════════════════════════════════════════════════════════

class _PostCard extends StatelessWidget {
  /// Foto do usuário Gente Pole (avatar dos comunicados); carregada pela tela.
  static String? fotoGentePole;

  final FeedPostModel post;
  final int? meuId;
  final VoidCallback onExcluir;
  /// Prévia de um post ainda pendente/rejeitado: sem menu de excluir nem
  /// reações.
  final bool preview;

  const _PostCard({
    required this.post,
    required this.meuId,
    required this.onExcluir,
    this.preview = false,
  });

  @override
  Widget build(BuildContext context) {
    final isAniversario = post.isAniversario;
    final isDoSistema = post.isDoSistema;
    final isHumor = post.isHumor;
    final isRespostaParabens = post.isRespostaParabens;
    // Card de humor não tem mais destaque de cor forte (fundo/borda) — só a
    // etiqueta "Humor do dia" no cabeçalho já avisa o tipo, e o card fica
    // discreto/branco igual aos demais, sem o gradiente magenta que ficava
    // pesado visualmente.

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: isRespostaParabens
            ? LinearGradient(
                colors: [_douradoResposta.withOpacity(0.08), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : (isDoSistema && !isAniversario)
            ? LinearGradient(
                colors: [AppColors.laranja.withOpacity(0.07), Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : null,
        color: (isRespostaParabens || (isDoSistema && !isAniversario))
            ? null
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: (isDoSistema && !isAniversario)
            ? Border.all(color: AppColors.laranja.withOpacity(0.55), width: 1.5)
            : isRespostaParabens
            ? Border.all(color: _douradoResposta.withOpacity(0.35), width: 1.5)
            : isAniversario
            ? Border.all(color: AppColors.laranja.withOpacity(0.4), width: 1.5)
            : Border.all(color: const Color(0xFFEFEFEF)),
        boxShadow: [
          BoxShadow(
            color: isAniversario
                ? AppColors.laranja.withOpacity(0.08)
                : const Color(0x08000000),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                isDoSistema
                    ? _avatarSistema(isAniversario)
                    : _avatarColaborador(
                        post.autorNome ?? '',
                        post.autorFotoUrl,
                      ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              isDoSistema
                                  ? 'Gente Pole'
                                  : (post.autorNome ?? 'Colaborador'),
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.dark,
                              ),
                            ),
                          ),
                          if (isDoSistema && !isAniversario) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 16,
                              color: AppColors.laranja,
                            ),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            post.tempoRelativo,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.cinzaTexto,
                            ),
                          ),
                          ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.magenta.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  post.destinatarioLabel,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: AppColors.magenta,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (isHumor)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.magenta.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Humor do dia',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.magenta,
                      ),
                    ),
                  ),
                if (isDoSistema && !isAniversario)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.laranja,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.campaign_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Comunicado oficial',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!isDoSistema && !isHumor && !isRespostaParabens)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.laranja.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Post',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.laranja,
                      ),
                    ),
                  ),
                if (isRespostaParabens)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _douradoResposta.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Resposta de aniversário',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _douradoResposta,
                      ),
                    ),
                  ),
                // Pill de status para posts do próprio usuário que estão pendentes ou rejeitados
                if (meuId != null && post.autorId == meuId && !post.isAprovado)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: post.isPendente
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      post.isPendente ? '⏳ Aguardando' : 'Rejeitado',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: post.isPendente
                            ? const Color(0xFFB45309)
                            : const Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                // Post de humor não pode ser excluído — é um registro de
                // bem-estar, não um post social comum.
                if (!preview && meuId != null && post.autorId == meuId && !isHumor)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'excluir') onExcluir();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'excluir',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Excluir',
                              style: GoogleFonts.poppins(
                                color: Colors.red,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: AppColors.cinzaTexto,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
              ],
            ),
          ),

          // ── Imagem ──────────────────────────────────────────────────────────
          if (post.temImagem) _imagensDoPost(),

          // ── Título (comunicados) ───────────────────────────────────────────
          if (post.titulo != null && post.titulo!.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                post.temImagem ? 12 : 0,
                14,
                post.conteudo != null && post.conteudo!.isNotEmpty ? 2 : 16,
              ),
              child: Text(
                post.titulo!,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.dark,
                ),
              ),
            ),

          // ── Conteúdo ────────────────────────────────────────────────────────
          if (post.conteudo != null && post.conteudo!.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                (post.titulo != null && post.titulo!.isNotEmpty)
                    ? 0
                    : (post.temImagem ? 12 : 0),
                14,
                16,
              ),
              child: _buildConteudo(
                post.conteudo!,
                isAniversario,
                isHumor,
                isRespostaParabens,
              ),
            ),

          if ((post.conteudo == null || post.conteudo!.isEmpty) &&
              (post.titulo == null || post.titulo!.isEmpty))
            const SizedBox(height: 14),

          // ── Reações ─────────────────────────────────────────────────────────
          if (!preview) _ReacoesBar(postId: post.id, meuId: meuId),
        ],
      ),
    );
  }

  // Renderiza texto com @menções e *nomes* (aniversário/humor) em destaque
  Widget _buildConteudo(
    String texto,
    bool isAniversario,
    bool isHumor,
    bool isRespostaParabens,
  ) {
    final fontSize = isAniversario ? 15.0 : 14.0;
    final baseStyle = GoogleFonts.poppins(
      fontSize: fontSize,
      color: AppColors.dark,
      height: 1.5,
      fontWeight: isAniversario ? FontWeight.w500 : FontWeight.normal,
    );

    // Posts de aniversário, humor e resposta de aniversário destacam *nome*
    // — laranja no aniversário, magenta no humor, dourado na resposta.
    if (isAniversario || isHumor || isRespostaParabens) {
      final corNome = isRespostaParabens
          ? _douradoResposta
          : (isHumor ? AppColors.magenta : AppColors.laranja);
      final regex = RegExp(r'\*([^*]+)\*');
      final matches = regex.allMatches(texto).toList();
      if (matches.isNotEmpty) {
        final spans = <TextSpan>[];
        int last = 0;
        for (final m in matches) {
          if (m.start > last) {
            spans.add(TextSpan(text: texto.substring(last, m.start)));
          }
          spans.add(
            TextSpan(
              text: m.group(1), // sem os asteriscos
              style: GoogleFonts.poppins(
                fontSize: fontSize,
                color: corNome,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
          );
          last = m.end;
        }
        if (last < texto.length) {
          final resto = texto.substring(last);
          // Motivo do humor / texto da resposta (depois da quebra dupla de
          // linha), sem aspas literais.
          if ((isHumor || isRespostaParabens) && resto.contains('\n\n')) {
            final partes = resto.split('\n\n');
            spans.add(TextSpan(text: partes.first));
            // Motivo com o mesmo estilo da legenda de um post normal;
            // hashtags em laranja.
            final motivo = '\n\n${partes.sublist(1).join('\n\n')}';
            var ult = 0;
            for (final h in RegExp(r'#[\p{L}\p{N}_]+', unicode: true)
                .allMatches(motivo)) {
              if (h.start > ult) {
                spans.add(TextSpan(text: motivo.substring(ult, h.start)));
              }
              spans.add(TextSpan(
                text: h.group(0),
                style: GoogleFonts.poppins(
                  fontSize: fontSize,
                  color: AppColors.laranja,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                  backgroundColor: AppColors.laranja.withOpacity(0.08),
                ),
              ));
              ult = h.end;
            }
            if (ult < motivo.length) {
              spans.add(TextSpan(text: motivo.substring(ult)));
            }
          } else {
            spans.add(TextSpan(text: resto));
          }
        }
        return RichText(
          text: TextSpan(style: baseStyle, children: spans),
        );
      }
      return Text(texto, style: baseStyle);
    }

    // Posts normais: destaca @menções em magenta
    String? mencaoTexto;
    if (post.destinatario.startsWith('@colaborador:')) {
      final pipeIdx = post.destinatario.indexOf('|');
      // Uma ou várias pessoas ('NOME1, NOME2'): cada nome vira uma
      // alternativa do regex (separadas por '\n' em mencaoTexto).
      if (pipeIdx >= 0) {
        mencaoTexto = post.destinatario
            .substring(pipeIdx + 1)
            .split(', ')
            .map((n) => '@$n')
            .join('\n');
      }
    } else if (post.destinatario.startsWith('@setor:')) {
      mencaoTexto = '@${post.destinatario.substring(7)}';
    }
    final regexStr = mencaoTexto != null
        ? '${mencaoTexto.split('\n').map(RegExp.escape).join('|')}|@\\[[^\\]]+\\]|@\\S+'
        : r'@\[[^\]]+\]|@\S+';
    // Hashtags (#tipole) também ganham destaque, em laranja.
    final regex = RegExp('$regexStr|#[\\p{L}\\p{N}_]+', unicode: true);
    final matches = regex.allMatches(texto).toList();
    if (matches.isEmpty) {
      return RichText(
        text: TextSpan(style: baseStyle, children: _comLinks(texto, fontSize)),
      );
    }

    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in matches) {
      if (m.start > last) {
        spans.addAll(_comLinks(texto.substring(last, m.start), fontSize));
      }
      final bruto = m.group(0)!;
      final exibido = bruto.startsWith('@[') && bruto.endsWith(']')
          ? '@${bruto.substring(2, bruto.length - 1)}'
          : bruto;
      spans.add(
        TextSpan(
          text: exibido,
          style: GoogleFonts.poppins(
            fontSize: fontSize,
            color: bruto.startsWith('#') ? AppColors.laranja : AppColors.magenta,
            fontWeight: FontWeight.w700,
            height: 1.5,
            backgroundColor:
                (bruto.startsWith('#') ? AppColors.laranja : AppColors.magenta)
                    .withOpacity(0.08),
          ),
        ),
      );
      last = m.end;
    }
    if (last < texto.length) {
      spans.addAll(_comLinks(texto.substring(last), fontSize));
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }

  static final _regexLink = RegExp(
    r'(https?://[^\s]+|www\.[^\s]+|\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|org|net|gov|edu)(?:\.br)?(?:/[^\s]*)?)',
    caseSensitive: false,
  );

  /// Quebra o texto em trechos normais e links (clicáveis, em azul).
  static List<InlineSpan> _comLinks(String texto, double fontSize) {
    final out = <InlineSpan>[];
    var ult = 0;
    for (final m in _regexLink.allMatches(texto)) {
      var link = m.group(0)!;
      final sobra = RegExp(r'[.,;:!?)]+$').firstMatch(link)?.group(0) ?? '';
      link = link.substring(0, link.length - sobra.length);
      final fim = m.end - sobra.length;
      if (link.isEmpty) continue;
      if (m.start > ult) out.add(TextSpan(text: texto.substring(ult, m.start)));
      final destino = link.toLowerCase().startsWith('http')
          ? link
          : 'https://$link';
      out.add(
        TextSpan(
          text: link,
          style: GoogleFonts.poppins(
            fontSize: fontSize,
            color: const Color(0xFF1D6FD8),
            decoration: TextDecoration.underline,
            height: 1.5,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => launchUrl(
              Uri.parse(destino),
              mode: LaunchMode.externalApplication,
            ),
        ),
      );
      ult = fim;
    }
    if (ult < texto.length) out.add(TextSpan(text: texto.substring(ult)));
    return out;
  }

  /// Uma imagem: como sempre (inteira, na largura do card). Várias (separadas
  /// por quebra de linha em imagem_url): carrossel com contador e bolinhas.
  Widget _imagensDoPost() {
    final urls = post.imagemUrl!
        .split('\n')
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    if (urls.length <= 1) {
      return CachedNetworkImage(
        imageUrl: urls.isEmpty ? post.imagemUrl! : urls.first,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (_, __) =>
            Container(height: 200, color: const Color(0xFFF3F4F6)),
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return _GaleriaImagensPost(urls: urls);
  }

  Widget _avatarSistema(bool isAniversario) {
    final foto = _PostCard.fotoGentePole;
    if (!isAniversario && foto != null && foto.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: CachedNetworkImageProvider(foto),
      );
    }
    return _avatarSistemaPadrao(isAniversario);
  }

  Widget _avatarSistemaPadrao(bool isAniversario) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: isAniversario
            ? [AppColors.laranja, const Color(0xFFFF8C42)]
            : [AppColors.laranja, AppColors.magenta],
      ),
      shape: BoxShape.circle,
    ),
    child: Center(
      child: Icon(
        isAniversario ? Icons.celebration_rounded : Icons.campaign_rounded,
        color: Colors.white,
        size: 20,
      ),
    ),
  );

  Widget _avatarColaborador(String nome, String? fotoUrl) {
    if (fotoUrl != null && fotoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: CachedNetworkImageProvider(fotoUrl),
      );
    }
    final iniciais = () {
      final p = nome.trim().split(' ');
      return p.length >= 2
          ? '${p.first[0]}${p.last[0]}'.toUpperCase()
          : nome.isNotEmpty
          ? nome[0].toUpperCase()
          : '?';
    }();
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.magenta.withOpacity(0.85),
      child: Text(
        iniciais,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// _ReacoesBar — reações estilo LinkedIn (gostei/parabéns/amei/estrela) por
// post: contagem por tipo (tocável, abre "quem reagiu") + botões pra reagir.
// ════════════════════════════════════════════════════════════════════════════════

class _ReacoesBar extends StatefulWidget {
  final int postId;
  final int? meuId;
  const _ReacoesBar({required this.postId, required this.meuId});

  @override
  State<_ReacoesBar> createState() => _ReacoesBarState();
}

class _ReacoesBarState extends State<_ReacoesBar> {
  static const _rotulos = {
    'gostei': 'Curtir',
    'parabens': 'Parabéns',
    'amei': 'Amei',
    'estrela': 'Destaque',
  };

  final _api = ApiService();
  List<Map<String, dynamic>> _reacoes = [];
  bool _enviando = false;
  bool _mostrandoSeletor = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await _api.buscarReacoesPost(widget.postId);
      if (mounted) setState(() => _reacoes = r);
    } catch (_) {
      // falha silenciosa — a barra some, mas não trava o post
    }
  }

  String? get _minhaReacao =>
      _reacoes.firstWhere(
            (r) => r['colaborador_id'] == widget.meuId,
            orElse: () => const {},
          )['tipo']
          as String?;

  Map<String, int> get _contagens {
    final mapa = <String, int>{};
    for (final r in _reacoes) {
      final tipo = r['tipo'] as String;
      mapa[tipo] = (mapa[tipo] ?? 0) + 1;
    }
    return mapa;
  }

  Future<void> _reagir(String tipo) async {
    _fecharOverlay();
    if (widget.meuId == null || _enviando) return;
    setState(() => _enviando = true);
    try {
      await _api.reagirPost(postId: widget.postId, tipo: tipo);
      await _carregar();
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  // Clique no botão "Curtir": abre o balão de opções (ou fecha, se já
  // estiver aberto). Só reage a clique — não a hover/scroll — pra não abrir
  // sozinho enquanto o usuário rola o feed. O balão é posicionado localmente
  // (Stack dentro do próprio post), sem Overlay/LayerLink — evita o erro de
  // "paint transform" do CompositedTransformFollower durante o scroll.
  void _alternarOverlay() {
    if (widget.meuId == null) return;
    setState(() => _mostrandoSeletor = !_mostrandoSeletor);
  }

  void _fecharOverlay() {
    if (_mostrandoSeletor) setState(() => _mostrandoSeletor = false);
  }

  void _abrirQuemReagiu() {
    if (_reacoes.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuemReagiuSheet(reacoes: _reacoes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contagens = _contagens;
    final minhaReacao = _minhaReacao;
    final reagiu = minhaReacao != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        if (_mostrandoSeletor)
          // TapRegion fecha o balão com um toque em qualquer outro lugar da
          // tela (fora do próprio balão) — sem precisar de Overlay. Usa o
          // mesmo groupId do botão "Curtir" pra um toque nele não contar
          // como "fora" (evita fechar e reabrir ao mesmo tempo).
          TapRegion(
            groupId: widget.postId,
            onTapOutside: (_) => _fecharOverlay(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _SeletorReacoes(
                  minhaReacao: minhaReacao,
                  onSelecionar: _reagir,
                ),
              ),
            ),
          ),
        if (contagens.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: GestureDetector(
              onTap: _abrirQuemReagiu,
              child: Row(
                children: [
                  for (final tipo in ApiService.tiposReacaoPost.keys)
                    if ((contagens[tipo] ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Tooltip(
                          message: _ReacoesBarState._rotulos[tipo]!,
                          waitDuration: const Duration(milliseconds: 200),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                ApiService.tiposReacaoPost[tipo]!,
                                size: 13,
                                color: AppColors.magenta,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${contagens[tipo]}',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.cinzaTexto,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        TapRegion(
          groupId: widget.postId,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
            child: GestureDetector(
              onTap: _alternarOverlay,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: reagiu ? 1 : 0.45,
                      child: Icon(
                        reagiu
                            ? ApiService.tiposReacaoPost[minhaReacao]!
                            : Icons.thumb_up_rounded,
                        size: 16,
                        color: reagiu ? AppColors.magenta : AppColors.cinzaTexto,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      reagiu ? _rotulos[minhaReacao]! : 'Curtir',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: reagiu
                            ? AppColors.magenta
                            : AppColors.cinzaTexto.withOpacity(0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Balão flutuante com as opções de reação (aparece ao passar o mouse por
// cima do botão "Curtir" no desktop/web, ou ao tocar e segurar no celular).
class _SeletorReacoes extends StatelessWidget {
  final String? minhaReacao;
  final void Function(String tipo) onSelecionar;
  const _SeletorReacoes({required this.minhaReacao, required this.onSelecionar});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in ApiService.tiposReacaoPost.entries)
              Tooltip(
                message: _ReacoesBarState._rotulos[entry.key]!,
                waitDuration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: () => onSelecionar(entry.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: EdgeInsets.all(minhaReacao == entry.key ? 4 : 6),
                    decoration: BoxDecoration(
                      color: minhaReacao == entry.key
                          ? AppColors.magentaOp15
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      entry.value,
                      size: minhaReacao == entry.key ? 26 : 24,
                      color: AppColors.magenta,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuemReagiuSheet extends StatelessWidget {
  final List<Map<String, dynamic>> reacoes;
  const _QuemReagiuSheet({required this.reacoes});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('${reacoes.length} reações', style: AppTextStyles.tituloMedio),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: reacoes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final r = reacoes[i];
                final colab = r['colaboradores'] as Map<String, dynamic>?;
                final nome = colab?['nome'] as String? ?? 'Colaborador';
                final fotoUrl = colab?['foto_url'] as String?;
                final iconeReacao =
                    ApiService.tiposReacaoPost[r['tipo']] ?? Icons.thumb_up_rounded;
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.laranjaOp15,
                      backgroundImage: (fotoUrl != null && fotoUrl.isNotEmpty)
                          ? NetworkImage(fotoUrl)
                          : null,
                      child: (fotoUrl == null || fotoUrl.isEmpty)
                          ? Text(nome.isNotEmpty ? nome[0].toUpperCase() : '?')
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(nome, style: AppTextStyles.corpoMedio),
                    ),
                    Icon(iconeReacao, size: 18, color: AppColors.magenta),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// _BannerCarrossel — carrossel de banners RH do topo do feed
// (espelha _BannerCarrossel do gentepole_admin/dashboard_screen.dart)
// ════════════════════════════════════════════════════════════════════════════════

class _BannerCarrossel extends StatefulWidget {
  final List<Map<String, dynamic>> banners;
  const _BannerCarrossel({required this.banners});

  @override
  State<_BannerCarrossel> createState() => _BannerCarrosselState();
}

class _BannerCarrosselState extends State<_BannerCarrossel> {
  final _controller = PageController();
  int _pagina = 0;
  Timer? _autoPlay;

  @override
  void initState() {
    super.initState();
    _iniciarAutoPlay();
  }

  void _iniciarAutoPlay() {
    _autoPlay?.cancel();
    if (widget.banners.length <= 1) return;
    _autoPlay = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      final proxima = (_pagina + 1) % widget.banners.length;
      _controller.animateToPage(
        proxima,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoPlay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.banners.length,
          onPageChanged: (i) {
            setState(() => _pagina = i);
            _iniciarAutoPlay();
          },
          itemBuilder: (_, i) => Image.network(
            widget.banners[i]['url'] as String,
            fit: BoxFit.cover,
            width: double.infinity,
          ),
        ),
        Positioned(
          bottom: 10,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.banners.length, (i) {
              final ativo = i == _pagina;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: ativo ? 8 : 6,
                height: ativo ? 8 : 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(ativo ? 0.95 : 0.5),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// _CardAniversarioMes / _LinhaAniversario — containers de aniversariantes e
// aniversário de empresa do dia (espelham os equivalentes do
// gentepole_admin/dashboard_screen.dart)
// ════════════════════════════════════════════════════════════════════════════════

class _CardAniversarioMes extends StatefulWidget {
  final String titulo;
  final List<Widget> itens;

  const _CardAniversarioMes({required this.titulo, required this.itens});

  @override
  State<_CardAniversarioMes> createState() => _CardAniversarioMesState();
}

class _CardAniversarioMesState extends State<_CardAniversarioMes> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              widget.titulo,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.dark,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 128,
            child: Scrollbar(
              controller: _controller,
              thumbVisibility: true,
              child: ListView.separated(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                itemCount: widget.itens.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => widget.itens[i],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaAniversario extends StatelessWidget {
  final String nome;
  final String? setor;
  final String? fotoUrl;
  final Color cor;
  final String mensagem;
  final NivelTempoCasa? nivel;
  final bool destaqueMeuSetor;
  /// Quando preenchido, o card inteiro é clicável (abre a celebração) e
  /// mostra um ícone de festa à direita.
  final VoidCallback? onTap;

  const _LinhaAniversario({
    required this.nome,
    required this.setor,
    required this.fotoUrl,
    required this.cor,
    required this.mensagem,
    this.nivel,
    this.destaqueMeuSetor = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iniciais = nome.trim().isNotEmpty
        ? nome.trim().split(' ').take(2).map((p) => p[0]).join().toUpperCase()
        : '?';

    final card = Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: destaqueMeuSetor ? cor.withOpacity(0.6) : cor.withOpacity(0.15),
          width: destaqueMeuSetor ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: cor.withOpacity(0.15),
            backgroundImage: (fotoUrl != null && fotoUrl!.isNotEmpty)
                ? CachedNetworkImageProvider(fotoUrl!)
                : null,
            child: (fotoUrl == null || fotoUrl!.isEmpty)
                ? Text(
                    iniciais,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      color: cor,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark,
                  ),
                ),
                if (setor != null && setor!.isNotEmpty && setor != '—')
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          setor!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AppColors.cinzaTexto,
                          ),
                        ),
                      ),
                      if (destaqueMeuSetor) ...[
                        const SizedBox(width: 5),
                        Text(
                          '· seu setor',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: cor,
                          ),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 4),
                Text(
                  mensagem,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: cor,
                  ),
                ),
                if (nivel != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: nivel!.cor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: nivel!.cor.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(nivel!.icone, size: 11, color: nivel!.cor),
                        const SizedBox(width: 3),
                        Text(
                          nivel!.label,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: nivel!.cor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: cor,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.celebration_rounded,
                  size: 16, color: Colors.white),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

Widget _avatarCelebracao(Map? autor) {
  final foto = autor?['foto_url'] as String?;
  final nome = (autor?['nome'] as String?)?.trim() ?? '?';
  return CircleAvatar(
    radius: 16,
    backgroundColor: AppColors.laranja.withOpacity(0.15),
    backgroundImage: (foto != null && foto.isNotEmpty)
        ? CachedNetworkImageProvider(foto)
        : null,
    child: (foto != null && foto.isNotEmpty)
        ? null
        : Text(
            nome.isNotEmpty ? nome[0].toUpperCase() : '?',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.laranja,
            ),
          ),
  );
}

/// Folha de celebração (tempo de empresa / novo polevalente): em cima, quem
/// já celebrou; embaixo, o campo para celebrar também.
class _CelebracaoSheet extends StatefulWidget {
  final ApiService api;
  final int meuId;
  final String tipo;
  final int colaboradorId;
  final String nome;
  final String? setor;
  final String dataEvento;
  final String titulo;
  final String subtitulo;

  const _CelebracaoSheet({
    required this.api,
    required this.meuId,
    required this.tipo,
    required this.colaboradorId,
    required this.nome,
    required this.setor,
    required this.dataEvento,
    required this.titulo,
    required this.subtitulo,
  });

  @override
  State<_CelebracaoSheet> createState() => _CelebracaoSheetState();
}

class _CelebracaoSheetState extends State<_CelebracaoSheet> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _celebracoes = [];
  bool _carregando = true;
  bool _enviando = false;

  bool get _jaCelebrei =>
      _celebracoes.any((c) => c['autor_id'].toString() == '${widget.meuId}');

  @override
  void initState() {
    super.initState();
    final primeiro = widget.nome.split(' ').first;
    _ctrl.text = widget.tipo == 'tempo_empresa'
        ? 'Parabéns pelo seu tempo de Pole, $primeiro! 🎉'
        : 'Seja muito bem-vindo(a), $primeiro! 👋';
    _carregar();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final r = await widget.api.listarCelebracoes(
        tipo: widget.tipo,
        colaboradorId: widget.colaboradorId,
        dataEvento: widget.dataEvento,
      );
      if (mounted) setState(() => _celebracoes = r);
    } catch (_) {}
    if (mounted) setState(() => _carregando = false);
  }

  Future<void> _celebrar() async {
    final msg = _ctrl.text.trim();
    if (msg.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    final ok = await widget.api.celebrar(
      tipo: widget.tipo,
      colaboradorId: widget.colaboradorId,
      dataEvento: widget.dataEvento,
      mensagem: msg,
    );
    if (!mounted) return;
    if (ok) await _carregar();
    if (!mounted) return;
    setState(() => _enviando = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível enviar. Você já pode ter celebrado.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(widget.titulo, style: AppTextStyles.tituloMedio),
            Text(
              [
                widget.subtitulo,
                if ((widget.setor ?? '').isNotEmpty) widget.setor!,
              ].join(' · '),
              style: AppTextStyles.corpoCinza,
            ),
            const SizedBox(height: 14),
            Text(
              _celebracoes.isEmpty
                  ? 'Ninguém celebrou ainda — seja o primeiro!'
                  : 'Quem já celebrou (${_celebracoes.length})',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.cinzaTexto,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: _carregando
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.magenta,
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final c in _celebracoes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _avatarCelebracao(c['autor'] as Map?),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (c['autor']?['nome'] as String?) ??
                                            'Alguém',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.dark,
                                        ),
                                      ),
                                      Text(
                                        c['mensagem'] as String? ?? '',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12.5,
                                          color: AppColors.cinzaTexto,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const Divider(height: 24),
            if (_jaCelebrei)
              Text(
                'Você já celebrou ${widget.nome.split(' ').first}. ✓',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.magenta,
                ),
              )
            else ...[
              TextField(
                controller: _ctrl,
                maxLines: 3,
                maxLength: 280,
                style: GoogleFonts.poppins(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Escreva sua mensagem...',
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _enviando ? null : _celebrar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.magenta,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Celebrar',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// Galeria de imagens do post
// ════════════════════════════════════════════════════════════════════════════════

class _GaleriaImagensPost extends StatefulWidget {
  final List<String> urls;
  const _GaleriaImagensPost({required this.urls});

  @override
  State<_GaleriaImagensPost> createState() => _GaleriaImagensPostState();
}

class _GaleriaImagensPostState extends State<_GaleriaImagensPost> {
  int _atual = 0;

  void _abrir(int i) => Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _VisualizadorImagens(urls: widget.urls, inicial: i),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    return Container(
      color: const Color(0xFFF3F4F6),
      height: 300,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _atual = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _abrir(i),
              child: CachedNetworkImage(
                imageUrl: urls[i],
                fit: BoxFit.contain,
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_atual + 1}/${urls.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < urls.length; i++)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _atual ? AppColors.laranja : Colors.black26,
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

/// Visualizador em tela cheia: arrastar para trocar de foto, pinça para zoom.
class _VisualizadorImagens extends StatefulWidget {
  final List<String> urls;
  final int inicial;
  const _VisualizadorImagens({required this.urls, required this.inicial});

  @override
  State<_VisualizadorImagens> createState() => _VisualizadorImagensState();
}

class _VisualizadorImagensState extends State<_VisualizadorImagens> {
  late final PageController _controller = PageController(
    initialPage: widget.inicial,
  );
  late int _atual = widget.inicial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_atual + 1}/${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _atual = i),
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.urls[i],
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const Icon(
                Icons.broken_image,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
