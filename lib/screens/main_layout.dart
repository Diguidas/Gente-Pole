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

  // HomeScreen recebe callback para navegar até Comunicados
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      HomeScreen(onVerComunicados: () => setState(() => _selectedIndex = 1)),
      const ComunicadosScreen(),
      const AniversariantesScreen(),
      const ServicosScreen(),
      const PessoasScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
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