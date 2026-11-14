// widgets/notificacoes_sino.dart
import 'dart:async';

import 'package:flutter/material.dart';
import '../screens/gestor/avaliar_periodo_experiencia_gestor_screen.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_navigator.dart';
import '../core/app_theme.dart';
import '../screens/cadastro/atualizacao_cadastral_screen.dart';
import '../screens/feedback/elogiar_screen.dart';
import '../screens/feedback/feedback_gestor_colab_screen.dart';
import '../screens/gestor/candidaturas_gestor_screen.dart';
import '../screens/oportunidades/eu_crio_oportunidades_screen.dart';
import '../screens/solicitacoes/solicitacoes_screen.dart';
import '../screens/gestor/feedback_gestor_screen.dart';
import '../screens/pesquisa/pesquisa_list_screen.dart';
import '../screens/servicos_screen.dart';
import '../screens/ti/chamados_ti_screen.dart';
import '../services/api_service.dart';

/// Sino de notificações — ícone com badge, fixo no topo direito, visível em
/// todas as abas do [MainLayout]. Ao tocar, abre um bottom sheet com a lista
/// unificada de alertas (pesquisa pendente, mensagem direta, parabéns sem
/// resposta, feedback, fim de experiência), calculada por
/// `ApiService.listarNotificacoesSino()`.
class NotificacoesSino extends StatefulWidget {
  const NotificacoesSino({super.key});

  @override
  State<NotificacoesSino> createState() => _NotificacoesSinoState();
}

class _NotificacoesSinoState extends State<NotificacoesSino>
    with WidgetsBindingObserver {
  final _api = ApiService();
  int _contador = 0;
  bool _carregandoContador = false;

  Timer? _timer;
  // Última lista calculada: o sino abre direto com ela (sem esperar a rede)
  // e o número do contador acompanha o que foi limpado na hora.
  List<NotificacaoItem> _itens = [];
  bool _jaCarregou = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _carregarContador();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregarContador();
    // Atualiza o contador sozinho de tempos em tempos (sem precisar abrir o sino).
    _timer = Timer.periodic(
        const Duration(minutes: 2), (_) => _carregarContador());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _carregarContador() async {
    if (_carregandoContador) return;
    _carregandoContador = true;
    try {
      final itens = await _api.listarNotificacoesSino();
      if (mounted) {
        setState(() {
          _itens = itens;
          _jaCarregou = true;
          _contador = itens.length;
        });
      }
    } catch (_) {
      // Silencioso: o sino não deve travar a navegação do app se uma das
      // categorias falhar (ex: tabela nova ainda não migrada no banco).
    } finally {
      _carregandoContador = false;
    }
  }

  Future<void> _abrirSino() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NotificacoesSheet(
        itensIniciais: _itens,
        jaCarregou: _jaCarregou,
        onMudou: (lista) {
          if (!mounted) return;
          setState(() {
            _itens = List.of(lista);
            _jaCarregou = true;
            _contador = lista.length;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Posicionamento é responsabilidade de quem usa este widget (ver
    // `MainLayout`, que o coloca flutuando perto da barra inferior) — assim
    // ele nunca sobrepõe os ícones de cada aba (atualizar, sair, etc), que
    // ficam no topo/cabeçalho de cada tela.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _abrirSino,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.pretoOp08,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Center(
                child: Icon(
                  Icons.notifications_outlined,
                  color: AppColors.dark,
                  size: 22,
                ),
              ),
              if (_contador > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: AppColors.erro,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      _contador > 99 ? '99+' : '$_contador',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificacoesSheet extends StatefulWidget {
  final List<NotificacaoItem> itensIniciais;
  final bool jaCarregou;
  final void Function(List<NotificacaoItem>) onMudou;
  const _NotificacoesSheet({
    required this.itensIniciais,
    required this.jaCarregou,
    required this.onMudou,
  });

  @override
  State<_NotificacoesSheet> createState() => _NotificacoesSheetState();
}

class _NotificacoesSheetState extends State<_NotificacoesSheet> {
  final _api = ApiService();
  bool _loading = true;
  List<NotificacaoItem> _itens = [];

  @override
  void initState() {
    super.initState();
    // Já tem uma lista de antes: mostra na hora e atualiza por baixo, sem
    // tela de "carregando".
    if (widget.jaCarregou) {
      _itens = List.of(widget.itensIniciais);
      _loading = false;
    }
    _carregar();
  }

  Future<void> _carregar() async {
    final itens = await _api.listarNotificacoesSino();
    if (!mounted) return;
    setState(() {
      _itens = itens;
      _loading = false;
    });
    widget.onMudou(_itens);
  }

  ({IconData icone, Color cor}) _visualPorTipo(String tipo) {
    switch (tipo) {
      case 'pesquisa':
        return (icone: Icons.poll_outlined, cor: AppColors.magenta);
      case 'mensagem':
        return (icone: Icons.mail_outline_rounded, cor: const Color(0xFF6366F1));
      case 'mencao':
        return (icone: Icons.alternate_email_rounded, cor: const Color(0xFF0EA5E9));
      case 'parabens':
        return (icone: Icons.cake_outlined, cor: const Color(0xFFEC4899));
      case 'feedback':
      case 'feedback_solicitacao':
        return (icone: Icons.forum_outlined, cor: AppColors.laranja);
      case 'elogio':
        return (icone: Icons.favorite_outline_rounded, cor: const Color(0xFFF59E0B));
      case 'solicitacao':
        return (icone: Icons.assignment_outlined, cor: const Color(0xFF6366F1));
      case 'candidatura_gestor':
      case 'candidatura_colab':
        return (icone: Icons.work_outline_rounded, cor: const Color(0xFF10B981));
      case 'cadastro':
        return (icone: Icons.badge_outlined, cor: const Color(0xFF0EA5E9));
      case 'chamado_ti':
        return (icone: Icons.build_outlined, cor: const Color(0xFFE64A19));
      case 'experiencia':
      case 'experiencia_equipe':
        return (icone: Icons.hourglass_bottom_rounded, cor: AppColors.amarelo);
      default:
        return (icone: Icons.notifications_outlined, cor: AppColors.cinzaTexto);
    }
  }

  Future<void> _abrirItem(NotificacaoItem item) async {
    // 1) Dispensa (marca visto) — otimista, não trava a navegação se falhar.
    unawaited(_api.dispensarNotificacao(item.chave));
    // 2) Remove localmente.
    setState(() => _itens.removeWhere((e) => e.chave == item.chave));
    widget.onMudou(_itens);
    // 3) Fecha o sheet.
    if (!mounted) return;
    Navigator.pop(context);
    // 4) Navega para o destino da categoria.
    switch (item.tipo) {
      case 'pesquisa':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PesquisaListScreen()));
        break;
      case 'mensagem':
      case 'mencao':
        AppNavigator.goToTab(0); // aba Feed
        break;
      case 'parabens':
        AppNavigator.goToTab(1); // aba Parabéns
        break;
      case 'elogio':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ElogiarScreen()));
        break;
      case 'solicitacao':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SolicitacoesScreen()));
        break;
      case 'candidatura_gestor':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CandidaturasGestorScreen()));
        break;
      case 'candidatura_colab':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const EuCrioOportunidadesScreen()));
        break;
      case 'cadastro':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AtualizacaoCadastralScreen()));
        break;
      case 'feedback':
      case 'feedback_solicitacao':
        final ehGestor = await _api.verificarSeEhGestor();
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ehGestor ? const FeedbackGestorScreen() : const FeedbackGestorColabScreen(),
          ),
        );
        break;
      case 'chamado_ti':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ChamadosTiScreen()));
        break;
      case 'experiencia':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ServicosScreen()));
        break;
      case 'experiencia_equipe':
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const AvaliarPeriodoExperienciaGestorScreen()),
        );
        break;
    }
  }

  /// Limpa as notificações da lista (marca como dispensadas). Pedidos de
  /// feedback ficam, porque ainda esperam uma resposta.
  Future<void> _limparTudo() async {
    final limpaveis =
        _itens.where((e) => e.tipo != 'feedback_solicitacao').toList();
    if (limpaveis.isEmpty) return;
    setState(() => _itens.removeWhere((e) => e.tipo != 'feedback_solicitacao'));
    widget.onMudou(_itens);
    await Future.wait(limpaveis.map((e) => _api.dispensarNotificacao(e.chave)));
  }

  Future<void> _recusarSolicitacao(NotificacaoItem item) async {
    final id = item.refId;
    if (id == null) return;
    try {
      await _api.recusarSolicitacaoFeedback(id);
      if (!mounted) return;
      setState(() => _itens.removeWhere((e) => e.chave == item.chave));
    widget.onMudou(_itens);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao recusar: $e'), backgroundColor: AppColors.erro),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.notifications_rounded, color: AppColors.magenta),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Notificações',
                      style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark),
                    ),
                  ),
                  if (!_loading && _itens.any((e) => e.tipo != 'feedback_solicitacao'))
                    TextButton(
                      onPressed: _limparTudo,
                      child: Text('Limpar tudo',
                          style: GoogleFonts.poppins(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: AppColors.cinzaTexto),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator(color: AppColors.magenta)),
              )
            else if (_itens.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                child: Center(
                  child: Text(
                    'Nenhuma notificação por aqui.',
                    style: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: _itens.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _card(_itens[i]),
                ),
              ),
            if (!_loading && _itens.any((e) => e.tipo == 'feedback_solicitacao'))
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 8),
                  child: TextButton(
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final ehGestor = await _api.verificarSeEhGestor();
                      nav.pop();
                      nav.push(
                        MaterialPageRoute(
                          builder: (_) => ehGestor ? const FeedbackGestorScreen() : const FeedbackGestorColabScreen(),
                        ),
                      );
                    },
                    child: Text(
                      'Ver tudo em Meus Feedbacks',
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card(NotificacaoItem item) {
    final visual = _visualPorTipo(item.tipo);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _abrirItem(item),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: visual.cor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: visual.cor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(visual.icone, color: visual.cor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.titulo,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto),
                    ),
                    if (item.tipo == 'feedback_solicitacao')
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => _recusarSolicitacao(item),
                              child: Text(
                                'Recusar',
                                style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.cinzaTexto),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () => _abrirItem(item),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              child: Text('Atender', style: GoogleFonts.poppins(fontSize: 11.5)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: visual.cor),
            ],
          ),
        ),
      ),
    );
  }
}
