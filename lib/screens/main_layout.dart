import 'package:flutter/material.dart';
import 'package:gentepole/screens/feed/feed_screen.dart';
import 'package:gentepole/services/api_service.dart';
// Polebot desativado temporariamente.
// import 'package:polebot_widget/polebot_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_theme.dart';
import '../core/app_navigator.dart';
import 'aniversariante_screen.dart';
import 'perfil_screen.dart';
import 'pesquisa/pesquisa_list_screen.dart';
import 'servicos_screen.dart';
import 'atalhos/atalhos_sheet.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/notificacoes_sino.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  final Set<int> _visitadas = {0};

  @override
  void initState() {
    super.initState();
    AppNavigator.tabIndex.addListener(_onExternalTab);
  }

  @override
  void dispose() {
    AppNavigator.tabIndex.removeListener(_onExternalTab);
    super.dispose();
  }

  void _onExternalTab() => _onTabTap(AppNavigator.tabIndex.value);

  void _onPolebotNavegar(String destino) {
    switch (destino) {
      case 'pesquisas_pendentes':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PesquisaListScreen()));
        break;
    }
  }

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
    final colaboradorId = ApiService().colaboradorAtual?.id;
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
      // Polebot desativado temporariamente.
      // floatingActionButton: PolebotLauncherButton(
      //   service: PolebotService(Supabase.instance.client),
      //   theme: const PolebotTheme(corPrimaria: AppColors.magenta),
      //   appContexto: 'colaborador',
      //   origemApp: 'gente_pole',
      //   solicitanteTipo: 'colaborador',
      //   colaboradorId: colaboradorId,
      //   onNavegar: _onPolebotNavegar,
      // ),
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