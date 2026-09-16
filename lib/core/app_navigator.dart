import 'package:flutter/material.dart';

/// Controla a navegação entre abas a partir de qualquer lugar do app
/// (inclusive quando uma notificação push é tocada).
class AppNavigator {
  static final tabIndex = ValueNotifier<int>(0);
  static void goToTab(int index) => tabIndex.value = index;

  /// Navigator raiz do app — usado pra empurrar uma tela específica por
  /// cima de tudo (ex: abrir direto o chamado de TI ao tocar na push),
  /// sem depender de qual aba está aberta no momento.
  static final navigatorKey = GlobalKey<NavigatorState>();
}
