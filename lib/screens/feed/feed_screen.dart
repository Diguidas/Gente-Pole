// screens/feed/feed_screen.dart
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gentepole/core/app_theme.dart';
import 'package:gentepole/models/feed_post_model.dart';
import 'package:gentepole/screens/login_screen.dart';
import 'package:gentepole/services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // Humor
  Map<String, dynamic>? _humorHoje;

  // Exame periódico
  Map<String, dynamic>? _exameAgendado;

  RealtimeChannel? _statusChannel;

  @override
  void initState() {
    super.initState();
    _carregarFeed();
    _carregarHumor();
    _carregarExame();
    _scrollCtrl.addListener(_onScroll);
    _assinarStatusPosts();
  }

  @override
  void dispose() {
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

  Future<void> _registrarHumor(int nivel) async {
    const emojis = ['😞', '😕', '😐', '🙂', '😄'];
    const labels = ['Péssimo', 'Ruim', 'Ok', 'Bem', 'Ótimo'];
    final emoji = emojis[nivel - 1];
    final label = labels[nivel - 1];

    // Dialog perguntando o motivo
    final motivoCtrl = TextEditingController();
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '$emoji Como você está?',
          style: AppTextStyles.tituloMedio,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Você selecionou: $label',
              style: AppTextStyles.corpoNormal,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              maxLines: 3,
              style: AppTextStyles.corpoNormal,
              decoration: InputDecoration(
                hintText: 'Por que você está assim? (opcional)',
                hintStyle: GoogleFonts.poppins(
                    color: AppColors.cinzaTexto.withOpacity(0.6),
                    fontSize: 13),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
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
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: Text('OK', style: AppTextStyles.botaoPrimario),
          ),
        ],
      ),
    );

    if (confirmou != true || !mounted) return;

    final motivo = motivoCtrl.text.trim();
    final ok = await _api.registrarHumor(
        nivel: nivel, motivo: motivo.isNotEmpty ? motivo : null);
    if (!mounted) return;

    if (ok) {
      // Atualiza o card imediatamente sem esperar o DB
      if (mounted) setState(() => _humorHoje = {'nivel': nivel});
      _carregarHumor(); // sincroniza com DB em background

      // Cria post automático no feed
      final colab = _api.colaboradorAtual;
      final nome = colab?.primeiroNome ?? 'Alguém';
      final conteudo = motivo.isNotEmpty
          ? '$nome está se sentindo $label $emoji\n\n"$motivo"'
          : '$nome está se sentindo $label $emoji';

      await _api.criarPost(conteudo: conteudo, destinatario: 'todos');
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
        title: Text('Excluir publicação?',
            style: AppTextStyles.tituloPequeno
                .copyWith(fontWeight: FontWeight.w600)),
        content: Text('Essa ação não pode ser desfeita.',
            style: AppTextStyles.corpoNormal),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar', style: AppTextStyles.corpoCinza)),
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
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(28)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      _avatar(colaborador?.nome ?? '', colaborador?.fotoUrl),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Olá, ${colaborador?.primeiroNome ?? ''} 👋',
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

                // Chips matrícula + admissão
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _chip(Icons.badge_outlined, 'Matrícula',
                          colaborador?.matricula ?? '—'),
                      const SizedBox(width: 10),
                      _chip(Icons.calendar_today_outlined, 'Admissão',
                          colaborador?.dataAdmissaoFormatada ?? '—'),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Feed ──────────────────────────────────────────────────────
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: _carregando
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.magenta))
                        : RefreshIndicator(
                            color: AppColors.magenta,
                            onRefresh: () async {
                              await _carregarFeed(reiniciar: true);
                              await _carregarHumor();
                              await _carregarExame();
                            },
                            child: ListView.builder(
                              controller: _scrollCtrl,
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 40),
                              itemCount: _posts.length +
                                  2 + // humor + composer
                                  (_exameAgendado != null ? 1 : 0) +
                                  (_carregandoMais ? 1 : 0),
                              itemBuilder: (ctx, i) {
                                // Item 0: humor card
                                if (i == 0) return _buildHumorCard();
                                // Item 1: exame card (se houver)
                                if (i == 1 && _exameAgendado != null) {
                                  return _buildExameCard(_exameAgendado!);
                                }
                                final offset = _exameAgendado != null ? 1 : 0;
                                // Item 1 ou 2: composer inline
                                if (i == 1 + offset) {
                                  return _InlineComposer(
                                    api: _api,
                                    onPublicado: () =>
                                        _carregarFeed(reiniciar: true),
                                  );
                                }
                                final postIdx = i - 2 - offset;
                                if (postIdx == _posts.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                          color: AppColors.magenta),
                                    ),
                                  );
                                }
                                if (_posts.isEmpty) return _vazioWidget();
                                return _PostCard(
                                  post: _posts[postIdx],
                                  meuId: _api.colaboradorAtual?.id,
                                  onExcluir: () =>
                                      _confirmarExclusao(_posts[postIdx]),
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
            child: const Icon(Icons.medical_services_outlined,
                color: Color(0xFFF97316), size: 24),
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
                          horizontal: 7, vertical: 2),
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
                  '📅  $dataFormatada${clinica != null ? '  ·  $clinica' : ''}',
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
                        color: const Color(0xFF92400E).withOpacity(0.7)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Humor Card ────────────────────────────────────────────────────────────────

  Widget _buildHumorCard() {
    return _HumorCard(
      humorHoje: _humorHoje,
      onRegistrar: _registrarHumor,
    );
  }

  // ── Widgets auxiliares ────────────────────────────────────────────────────────

  Widget _vazioWidget() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dynamic_feed_rounded,
                  size: 64,
                  color: AppColors.cinzaTexto.withOpacity(0.4)),
              const SizedBox(height: 16),
              Text('Nenhuma publicação ainda',
                  style: AppTextStyles.corpoCinza
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Seja o primeiro a publicar algo!',
                  style: AppTextStyles.corpoCinza),
            ],
          ),
        ),
      );

  Widget _avatar(String nome, String? fotoUrl) {
    if (fotoUrl != null && fotoUrl.isNotEmpty) {
      return CircleAvatar(
          radius: 22, backgroundImage: CachedNetworkImageProvider(fotoUrl));
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.white.withOpacity(0.3),
      child: Text(_iniciais(nome),
          style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14)),
    );
  }

  Widget _headerIcon(
          {required IconData icon,
          required String tooltip,
          required VoidCallback onTap}) =>
      IconButton(
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
                  fontWeight: FontWeight.w500),
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
        title: Text('Sair da conta?',
            style: AppTextStyles.tituloPequeno
                .copyWith(fontWeight: FontWeight.w600)),
        content: Text(
            'Você precisará digitar seu CPF e senha novamente.',
            style: AppTextStyles.corpoNormal),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar', style: AppTextStyles.corpoCinza)),
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
  int _mencaoEnd = -1; // posição após o último label inserido; ignora @s anteriores

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
    final resultados = await widget.api.buscarSugestoesMencao(query);
    if (!mounted) return;
    setState(() {
      _sugestoes = resultados;
      _showSugestoes = resultados.isNotEmpty;
      _buscandoSugestoes = false;
    });
  }

  void _selecionarMencao(Map<String, String> sugestao) {
    final valor = sugestao['valor']!;
    final label = sugestao['label']!;
    final texto = _ctrl.text;
    final cursor = _ctrl.selection.baseOffset;
    final depois = texto.substring(cursor);
    final novoAntes = _mencaoStart >= 0
        ? '${texto.substring(0, _mencaoStart)}$label '
        : texto.substring(0, cursor).replaceAll(RegExp(r'@\S*$'), '$label ');

    // Para colaboradores, embute o nome no destinatario: '@colaborador:42|NOME'
    final destinatarioFinal = valor.startsWith('@colaborador:')
        ? '$valor|${label.replaceFirst('@', '')}'
        : valor;

    // Registra o label para o controller destacar exatamente esse trecho
    _ctrl.addMention(label);

    _ctrl.value = TextEditingValue(
      text: novoAntes + depois,
      selection: TextSelection.collapsed(offset: novoAntes.length),
    );
    setState(() {
      _destinatario = destinatarioFinal;
      _destinatarioLabel = label;
      _showSugestoes = false;
      _sugestoes = [];
      _mencaoStart = -1;
      _mencaoEnd = novoAntes.length; // ignora @s anteriores a este ponto
    });
  }

  Future<void> _escolherImagem() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
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
            content: Text('Post enviado para aprovação do RH.',
                style: AppTextStyles.corpoNormal.copyWith(color: Colors.white)),
            backgroundColor: const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao publicar. Tente novamente.',
              style: AppTextStyles.corpoNormal
                  .copyWith(color: Colors.white)),
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
              offset: const Offset(0, 2))
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
                      // Chip de destinatário — sempre visível
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.magenta.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: AppColors.magenta.withOpacity(0.25),
                                width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _destinatario == 'todos'
                                    ? Icons.public_rounded
                                    : _destinatario.startsWith('@setor:')
                                        ? Icons.group_rounded
                                        : Icons.person_rounded, // @colaborador:id|nome
                                size: 13,
                                color: AppColors.magenta,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _destinatario == 'todos'
                                    ? 'Para todos'
                                    : _destinatarioLabel,
                                style: GoogleFonts.poppins(
                                  color: AppColors.magenta,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_destinatario != 'todos') ...[
                                const SizedBox(width: 4),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() {
                                    _destinatario = 'todos';
                                    _destinatarioLabel = 'Todos';
                                    _mencaoEnd = -1;
                                  }),
                                  child: Icon(Icons.close_rounded,
                                      size: 14, color: AppColors.magenta),
                                ),
                              ],
                            ],
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
                                child: const Icon(Icons.close_rounded,
                                    color: Colors.white, size: 18),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  _actionBtn(Icons.image_outlined, 'Foto', _escolherImagem),
                  const SizedBox(width: 8),
                  _actionBtn(Icons.alternate_email_rounded, 'Mencionar', () {
                    final offset = _ctrl.selection.baseOffset
                        .clamp(0, _ctrl.text.length);
                    final texto = _ctrl.text;
                    _ctrl.value = TextEditingValue(
                      text:
                          '${texto.substring(0, offset)}@${texto.substring(offset)}',
                      selection:
                          TextSelection.collapsed(offset: offset + 1),
                    );
                    _focusNode.requestFocus();
                  }),
                  const Spacer(),
                  _enviando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.magenta),
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
                                horizontal: 20, vertical: 8),
                          ),
                          child: Text('Publicar',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              )),
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
              offset: const Offset(0, 4))
        ],
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: _buscandoSugestoes
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.magenta)),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sugestoes.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16),
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
                  title: Text(s['label']!,
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: s['sublabel']!.isNotEmpty
                      ? Text(s['sublabel']!,
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: AppColors.cinzaTexto))
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
          radius: 20, backgroundImage: CachedNetworkImageProvider(fotoUrl));
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
      child: Text(iniciais,
          style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13)),
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
              Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.cinzaTexto,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
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
    const emojis = ['😞', '😕', '😐', '🙂', '😄'];
    const labels = ['Péssimo', 'Ruim', 'Ok', 'Bem', 'Ótimo'];
    final jaRegistrou = widget.humorHoje != null;
    final nivelAtual =
        jaRegistrou ? (widget.humorHoje!['nivel'] as int? ?? 0) : -1;

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
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💬', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                jaRegistrou
                    ? 'Humor de hoje: ${labels[nivelAtual - 1]}'
                    : 'Como você está hoje?',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.dark),
              ),
              if (_salvando) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.magenta),
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
                      horizontal: 10, vertical: 8),
                  backgroundColor: selecionado
                      ? AppColors.magenta.withOpacity(0.12)
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: selecionado
                        ? BorderSide(
                            color: AppColors.magenta.withOpacity(0.4),
                            width: 1.5)
                        : BorderSide.none,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      emojis[idx],
                      style: TextStyle(
                        fontSize: selecionado ? 30 : 26,
                        color: jaRegistrou && !selecionado
                            ? Colors.black.withOpacity(0.25)
                            : null,
                      ),
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
  final FeedPostModel post;
  final int? meuId;
  final VoidCallback onExcluir;

  const _PostCard({
    required this.post,
    required this.meuId,
    required this.onExcluir,
  });

  @override
  Widget build(BuildContext context) {
    final isAniversario = post.isAniversario;
    final isDoSistema = post.isDoSistema;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isAniversario
            ? Border.all(
                color: AppColors.laranja.withOpacity(0.4), width: 1.5)
            : isDoSistema
                ? Border.all(
                    color: AppColors.magenta.withOpacity(0.3), width: 1.5)
                : null,
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
                        post.autorNome ?? '', post.autorFotoUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDoSistema
                            ? (isAniversario ? '🎉 Gente Pole' : '📢 Gente Pole')
                            : (post.autorNome ?? 'Colaborador'),
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.dark,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            post.tempoRelativo,
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: AppColors.cinzaTexto),
                          ),
                          ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 1),
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
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Pill de status para posts do próprio usuário que estão pendentes ou rejeitados
                if (meuId != null && post.autorId == meuId && !post.isAprovado)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: post.isPendente
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      post.isPendente ? '⏳ Aguardando' : '✕ Rejeitado',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: post.isPendente
                            ? const Color(0xFFB45309)
                            : const Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                if (meuId != null && post.autorId == meuId)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'excluir') onExcluir();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'excluir',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline_rounded,
                                color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Text('Excluir',
                                style: GoogleFonts.poppins(
                                    color: Colors.red, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                    icon:
                        Icon(Icons.more_horiz_rounded, color: AppColors.cinzaTexto),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
              ],
            ),
          ),

          // ── Imagem ──────────────────────────────────────────────────────────
          if (post.temImagem)
            CachedNetworkImage(
              imageUrl: post.imagemUrl!,
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(height: 200, color: const Color(0xFFF3F4F6)),
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),

          // ── Conteúdo ────────────────────────────────────────────────────────
          if (post.conteudo != null && post.conteudo!.isNotEmpty)
            Padding(
              padding:
                  EdgeInsets.fromLTRB(14, post.temImagem ? 12 : 0, 14, 16),
              child: _buildConteudo(post.conteudo!, isAniversario),
            ),

          if (post.conteudo == null || post.conteudo!.isEmpty)
            const SizedBox(height: 14),
        ],
      ),
    );
  }

  // Renderiza texto com @menções em destaque
  Widget _buildConteudo(String texto, bool isAniversario) {
    final baseStyle = GoogleFonts.poppins(
      fontSize: isAniversario ? 15 : 14,
      color: AppColors.dark,
      height: 1.5,
      fontWeight:
          isAniversario ? FontWeight.w500 : FontWeight.normal,
    );

    // Extrai o texto exato da menção a partir do destinatario (nome completo)
    String? mencaoTexto;
    if (post.destinatario.startsWith('@colaborador:')) {
      final pipeIdx = post.destinatario.indexOf('|');
      if (pipeIdx >= 0) mencaoTexto = '@${post.destinatario.substring(pipeIdx + 1)}';
    } else if (post.destinatario.startsWith('@setor:')) {
      mencaoTexto = '@${post.destinatario.substring(7)}';
    }
    // Padrão: tenta o nome completo primeiro (inclui espaços), depois @palavra
    final regexStr = mencaoTexto != null
        ? '${RegExp.escape(mencaoTexto)}|@\\S+'
        : r'@\S+';
    final regex = RegExp(regexStr);
    final matches = regex.allMatches(texto).toList();
    if (matches.isEmpty) return Text(texto, style: baseStyle);

    final spans = <TextSpan>[];
    int last = 0;
    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: texto.substring(last, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: GoogleFonts.poppins(
          fontSize: isAniversario ? 15 : 14,
          color: AppColors.magenta,
          fontWeight: FontWeight.w700,
          height: 1.5,
          backgroundColor: AppColors.magenta.withOpacity(0.08),
        ),
      ));
      last = m.end;
    }
    if (last < texto.length) {
      spans.add(TextSpan(text: texto.substring(last)));
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }

  Widget _avatarSistema(bool isAniversario) => Container(
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
          child: Text(
            isAniversario ? '🎉' : '📢',
            style: const TextStyle(fontSize: 20),
          ),
        ),
      );

  Widget _avatarColaborador(String nome, String? fotoUrl) {
    if (fotoUrl != null && fotoUrl.isNotEmpty) {
      return CircleAvatar(
          radius: 20, backgroundImage: CachedNetworkImageProvider(fotoUrl));
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
      child: Text(iniciais,
          style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13)),
    );
  }
}
