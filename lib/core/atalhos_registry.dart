import 'package:flutter/material.dart';
import 'package:gentepole/screens/lojinha/lojinha_home_screen.dart';
import 'package:gentepole/screens/fisioterapia/fisioterapia_screen.dart';
import 'package:gentepole/screens/massoterapia/massoterapia_screen.dart';
import 'package:gentepole/screens/nutricionista/nutricionista_screen.dart';
import 'package:gentepole/screens/cardapio/cardapio_screen.dart';
import 'package:gentepole/screens/reserva_salas/reserva_salas_screen.dart';
import 'package:gentepole/screens/conexoes/conexoes_do_bem_screen.dart';
import 'package:gentepole/screens/ouvidoria/ouvidoria_screen.dart';
import 'package:gentepole/screens/oportunidades/eu_crio_oportunidades_screen.dart';
import 'package:gentepole/screens/pesquisa/pesquisa_list_screen.dart';
import 'package:gentepole/screens/plantao_psicologico_screen.dart';

/// Serviços que podem ser marcados como atalho na barra de navegação.
/// Mantém só os serviços "gerais" (visíveis pra todo colaborador) — painéis
/// condicionais por papel (Gestor/Integração) ficam de fora de propósito.
class AtalhoDef {
  final String id;
  final String label;
  final IconData icon;
  final Color cor;
  final WidgetBuilder builder;

  const AtalhoDef({
    required this.id,
    required this.label,
    required this.icon,
    required this.cor,
    required this.builder,
  });
}

final List<AtalhoDef> atalhosDisponiveis = [
  AtalhoDef(
    id: 'lojinha',
    label: 'Lojinha',
    icon: Icons.storefront_outlined,
    cor: AppColorsAtalho.laranja,
    builder: (_) => const LojinhaHomeScreen(),
  ),
  AtalhoDef(
    id: 'pesquisas',
    label: 'Pesquisas',
    icon: Icons.poll_outlined,
    cor: AppColorsAtalho.magenta,
    builder: (_) => const PesquisaListScreen(),
  ),
  AtalhoDef(
    id: 'cardapio',
    label: 'Cardápio',
    icon: Icons.restaurant_menu_outlined,
    cor: const Color(0xFFF59E0B),
    builder: (_) => const CardapioScreen(),
  ),
  // Reserva de Salas desativada temporariamente (em testes) — religar antes
  // de retomar os testes in loco.
  // AtalhoDef(
  //   id: 'reserva_salas',
  //   label: 'Reserva de Salas',
  //   icon: Icons.meeting_room_outlined,
  //   cor: const Color(0xFF0891B2),
  //   builder: (_) => const ReservaSalasScreen(),
  // ),
  AtalhoDef(
    id: 'massoterapia',
    label: 'Massoterapia',
    icon: Icons.self_improvement_rounded,
    cor: AppColorsAtalho.magenta,
    builder: (_) => const MassoterapiaScreen(),
  ),
  AtalhoDef(
    id: 'nutricionista',
    label: 'Nutricionista',
    icon: Icons.local_dining_outlined,
    cor: const Color(0xFF10B981),
    builder: (_) => const NutricionistaScreen(),
  ),
  AtalhoDef(
    id: 'fisioterapia',
    label: 'Fisioterapia',
    icon: Icons.accessibility_new_rounded,
    cor: AppColorsAtalho.magenta,
    builder: (_) => const FisioterapiaScreen(),
  ),
  AtalhoDef(
    id: 'plantao_psicologico',
    label: 'Plantão Psicológico',
    icon: Icons.psychology_outlined,
    cor: const Color(0xFF7C3AED),
    builder: (_) => const PlantaoPsicologicoScreen(),
  ),
  AtalhoDef(
    id: 'conexoes_do_bem',
    label: 'Conexões do Bem',
    icon: Icons.favorite_outline_rounded,
    cor: const Color(0xFFEC4899),
    builder: (_) => const ConexoesDoiemScreen(),
  ),
  AtalhoDef(
    id: 'eu_crio_oportunidades',
    label: 'Eu Crio Oportunidades',
    icon: Icons.volunteer_activism_outlined,
    cor: const Color(0xFF10B981),
    builder: (_) => const EuCrioOportunidadesScreen(),
  ),
  AtalhoDef(
    id: 'ouvidoria',
    label: 'Ouvidoria',
    icon: Icons.record_voice_over_outlined,
    cor: const Color(0xFF64748B),
    builder: (_) => const OuvidoriaScreen(),
  ),
];

AtalhoDef? buscarAtalho(String id) {
  for (final a in atalhosDisponiveis) {
    if (a.id == id) return a;
  }
  return null;
}

/// Cores usadas nos ícones dos atalhos, sem depender de app_theme.dart para
/// evitar import circular.
class AppColorsAtalho {
  static const laranja = Color(0xFFFF6B00);
  static const magenta = Color(0xFFE91E8C);
}
