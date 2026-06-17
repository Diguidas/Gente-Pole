import 'package:flutter/material.dart';
import 'package:gentepole/screens/feed/feed_screen.dart';
import '../core/app_theme.dart';
import 'aniversariante_screen.dart';
import 'perfil_screen.dart';
import 'servicos_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  final Set<int> _visitadas = {0};

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
        children: List.generate(4, (index) {
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
        ],
      ),
    );
  }
}