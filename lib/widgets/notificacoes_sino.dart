// widgets/notificacoes_sino.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_navigator.dart';
import '../core/app_theme.dart';
import '../screens/feedback/elogiar_screen.dart';
import '../screens/gestor/feedback_gestor_screen.dart';
import '../screens/pesquisa/pesquisa_list_screen.dart';
import '../screens/servicos_screen.dart';
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

class _NotificacoesSinoState extends State<NotificacoesSino> {
  final _api = ApiService();
  int _contador = 0;
  bool _carregandoContador = false;

  @override
  void initState() {
    super.initState();
    _carregarContador();
  }

  Future<void> _carregarContador() async {
    if (_carregandoContador) return;
    _carregandoContador = true;
    try {
      final itens = await _api.listarNotificacoesSino();
      if (mounted) setState(() => _contador = itens.length);
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
      builder: (_) => const _NotificacoesSheet(),
    );
    // Ao fechar o sheet, o contador pode ter mudado (itens dispensados).
    _carregarContador();
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
  const _NotificacoesSheet();

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
    _carregar();
  }

  Future<void> _carregar() async {
    final itens = await _api.listarNotificacoesSino();
    if (!mounted) return;
    setState(() {
      _itens = itens;
      _loading = false;
    });
  }

  ({IconData icone, Color cor}) _visualPorTipo(String tipo) {
    switch (tipo) {
      case 'pesquisa':
        return (icone: Icons.poll_outlined, cor: AppColors.magenta);
      case 'mensagem':
        return (icone: Icons.mail_outline_rounded, cor: const Color(0xFF6366F1));
      case 'parabens':
        return (icone: Icons.cake_outlined, cor: const Color(0xFFEC4899));
      case 'feedback':
        return (icone: Icons.forum_outlined, cor: AppColors.laranja);
      case 'experiencia':
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
    // 3) Fecha o sheet.
    if (!mounted) return;
    Navigator.pop(context);
    // 4) Navega para o destino da categoria.
    switch (item.tipo) {
      case 'pesquisa':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PesquisaListScreen()));
        break;
      case 'mensagem':
        AppNavigator.goToTab(0); // aba Feed
        break;
      case 'parabens':
        AppNavigator.goToTab(1); // aba Parabéns
        break;
      case 'feedback':
        final ehGestor = await _api.verificarSeEhGestor();
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ehGestor ? const FeedbackGestorScreen() : const ElogiarScreen(),
          ),
        );
        break;
      case 'experiencia':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ServicosScreen()));
        break;
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
