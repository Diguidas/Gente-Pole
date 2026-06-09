import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import 'home_screen.dart';
import 'comunicados_screen.dart';
import 'aniversariante_screen.dart';
import 'pessoas_screen.dart';
import 'servicos_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  final Set<int> _visitadas = {0}; // Home já abre na primeira vez

  void _onTabTap(int index) {
    setState(() {
      _selectedIndex = index;
      _visitadas.add(index);
    });
  }

  Widget _buildPage(int index) {
    if (!_visitadas.contains(index)) return const SizedBox.shrink();

    switch (index) {
      case 0:
        return HomeScreen(
          onVerComunicados: () => _onTabTap(1),
        );
      case 1:
        return const ComunicadosScreen();
      case 2:
        return const AniversariantesScreen();
      case 3:
        return const ServicosScreen();
      case 4:
        return const PessoasScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: List.generate(5, (index) {
          return Offstage(
            offstage: _selectedIndex != index,
            child: _buildPage(index),
          );
        }),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTap,
        selectedItemColor: AppColors.magenta,
        unselectedItemColor: AppColors.cinzaTexto,
        type: BottomNavigationBarType.fixed,
        elevation: 12,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Início',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.campaign_outlined),
            activeIcon: Icon(Icons.campaign_rounded),
            label: 'Comunicados',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.cake_outlined),
            activeIcon: Icon(Icons.cake_rounded),
            label: 'Parabéns',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            activeIcon: Icon(Icons.grid_view_rounded),
            label: 'Serviços',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline_rounded),
            activeIcon: Icon(Icons.people_rounded),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}