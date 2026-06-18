import 'package:flutter/material.dart';

/// Controla a navegação entre abas a partir de qualquer lugar do app
/// (inclusive quando uma notificação push é tocada).
class AppNavigator {
  static final tabIndex = ValueNotifier<int>(0);
  static void goToTab(int index) => tabIndex.value = index;
}
