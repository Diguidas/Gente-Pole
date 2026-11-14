import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'package:gentepole/screens/feed/feed_screen.dart';
import '../core/app_theme.dart';
import '../core/app_navigator.dart';
import 'aniversariante_screen.dart';
import 'perfil_screen.dart';
import 'servicos_screen.dart';
import 'atalhos/atalhos_sheet.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/notificacoes_sino.dart';
import '../widgets/popup_aniversario.dart';
import '../widgets/popup_comunicado.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final Set<int> _visitadas = {0};
  Timer? _timerAcesso;
  bool _encerrando = false;
  // Dia (aaaa-mm-dd) do último acesso registrado nesta execução: o app fica
  // aberto em segundo plano, então ao voltar num dia novo registra de novo.
  String? _acessoRegistradoEm;

  @override
  void initState() {
    super.initState();
    AppNavigator.tabIndex.addListener(_onExternalTab);
    // Confere o acesso de quem já está logado: a cada poucos minutos e
    // quando o app volta ao primeiro plano.
    WidgetsBinding.instance.addObserver(this);
    _timerAcesso = Timer.periodic(
        const Duration(minutes: 5), (_) => _verificarAcesso());
    _registrarAcesso();
    // Aquece os chamados de TI em segundo plano: a tela abre já pronta.
    ApiService().precarregarChamadosTI().catchError((_) {});
    // Pop-up de aniversário (natalício / tempo de empresa), 1x por dia.
    // Depois, os pop-ups de comunicado do endomkt (um por vez, sem sobrepor).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await PopupAniversario.verificar(context);
      if (mounted) await PopupComunicado.verificar(context);
    });
  }

  @override
  void dispose() {
    AppNavigator.tabIndex.removeListener(_onExternalTab);
    WidgetsBinding.instance.removeObserver(this);
    _timerAcesso?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verificarAcesso();
      _registrarAcesso();
    }
  }

  void _registrarAcesso() {
    final h = DateTime.now();
    final hoje =
        '${h.year}-${h.month.toString().padLeft(2, '0')}-${h.day.toString().padLeft(2, '0')}';
    if (_acessoRegistradoEm == hoje) return;
    _acessoRegistradoEm = hoje;
    ApiService().registrarAcessoApp();
  }

  /// Desligado ou bloqueado no painel: encerra a sessão. Se a conferência
  /// falhar (sem internet), não derruba ninguém.
  Future<void> _verificarAcesso() async {
    if (_encerrando) return;
    final api = ApiService();
    final colab = api.colaboradorAtual;
    if (colab == null) return;
    final ok =
        await api.verificarAcessoAtivo(colab.matricula, colab.empresa ?? '');
    if (ok != false || !mounted) return;
    _encerrando = true;
    await api.limparSessao();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Acesso encerrado'),
        content: const Text('Seu acesso ao sistema foi encerrado.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _onExternalTab() => _onTabTap(AppNavigator.tabIndex.value);

  void _onTabTap(int index) {
    if (index == 4) {
      abrirMenuAtalhos(context);
      return;
    }
    setState(() {
      _selectedIndex = index;
      _visitadas.add(index);
    });
  }

  Widget _buildPage(int index) {
    if (!_visitadas.contains(index)) return const SizedBox.shrink();

    switch (index) {
      case 0:
        return const FeedScreen();
      case 1:
        return const AniversariantesScreen();
      case 2:
        return const ServicosScreen();
      case 3:
        return const PessoasScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  static Widget _navItem(IconData icon, String label, bool ativo) {
    final cor = ativo ? AppColors.magenta : AppColors.cinzaTexto;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: cor),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: cor,
            fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ...List.generate(4, (index) {
            return Offstage(
              offstage: _selectedIndex != index,
              child: _buildPage(index),
            );
          }),
          // Flutua perto da barra inferior (não no topo) pra nunca ficar por
          // cima dos ícones de cabeçalho de cada aba (atualizar, sair etc).
          const Positioned(
            right: 16,
            bottom: 16,
            child: NotificacoesSino(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTap,
        selectedItemColor: AppColors.magenta,
        unselectedItemColor: AppColors.cinzaTexto,
        type: BottomNavigationBarType.fixed,
        elevation: 12,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: [
          const BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/pole+conectada.png'),
              size: 50,
            ),
            activeIcon: ImageIcon(
              AssetImage('assets/pole+conectada.png'),
              size: 50,
              color: AppColors.magenta,
            ),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _navItem(Icons.cake_outlined, 'Parabéns', false),
            activeIcon: _navItem(Icons.cake_rounded, 'Parabéns', true),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _navItem(Icons.grid_view_rounded, 'Serviços', false),
            activeIcon: _navItem(Icons.grid_view_rounded, 'Serviços', true),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _navItem(Icons.people_outline_rounded, 'Perfil', false),
            activeIcon: _navItem(Icons.people_rounded, 'Perfil', true),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _navItem(Icons.star_outline_rounded, 'Atalhos', false),
            activeIcon: _navItem(Icons.star_outline_rounded, 'Atalhos', false),
            label: '',
          ),
        ],
      ),
    );
  }
}