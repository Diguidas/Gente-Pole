import 'dart:async';
import 'package:flutter/widgets.dart';
import '../services/api_service.dart';

/// Rascunho de uma avaliação (nota 1-5 + comentário por pergunta) guardado no
/// servidor (`rascunhos_respostas`), para continuar depois — inclusive em outro
/// aparelho ou no web. Formato igual ao do web:
/// `{'notas': {'<perguntaId>': int}, 'coment': {'<perguntaId>': String}}`.
class RascunhoNotas {
  final ApiService api;
  final String tipo; // 'avaliacao_equipe' | 'avaliacao_colega'
  final String chave; // id da avaliação
  final Map<int, int?> notas;
  final Map<int, TextEditingController> comentarios;
  Timer? _debounce;
  bool _encerrado = false;

  RascunhoNotas({
    required this.api,
    required this.tipo,
    required this.chave,
    required this.notas,
    required this.comentarios,
  });

  /// Aplica o rascunho salvo sobre as notas/comentários atuais.
  /// Retorna true se havia algo para restaurar.
  Future<bool> restaurar() async {
    final m = await api.buscarRascunho(tipo, chave);
    if (m == null) return false;
    final n = (m['notas'] as Map?) ?? {};
    final c = (m['coment'] as Map?) ?? {};
    var restaurou = false;
    for (final pid in notas.keys) {
      final nota = n['$pid'];
      if (nota is int) {
        notas[pid] = nota.clamp(1, 5);
        restaurou = true;
      }
      final txt = c['$pid'];
      if (txt is String && txt.isNotEmpty) {
        comentarios[pid]?.text = txt;
        restaurou = true;
      }
    }
    return restaurou;
  }

  Map<String, dynamic> _dados() => {
        'notas': {
          for (final e in notas.entries)
            if (e.value != null) '${e.key}': e.value
        },
        'coment': {
          for (final e in comentarios.entries)
            if (e.value.text.trim().isNotEmpty) '${e.key}': e.value.text
        },
      };

  /// Salva logo após a última alteração (debounce).
  void agendar() {
    if (_encerrado) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), _salvarAgora);
  }

  Future<void> _salvarAgora() async {
    final d = _dados();
    if ((d['notas'] as Map).isEmpty && (d['coment'] as Map).isEmpty) {
      await api.apagarRascunho(tipo, chave);
    } else {
      await api.salvarRascunho(tipo, chave, d);
    }
  }

  /// Ao fechar o diálogo sem enviar: grava o estado final.
  Future<void> salvarEEncerrar() async {
    _debounce?.cancel();
    if (_encerrado) return;
    _encerrado = true;
    await _salvarAgora();
  }

  /// Após enviar com sucesso: descarta o rascunho.
  Future<void> descartar() async {
    _encerrado = true;
    _debounce?.cancel();
    await api.apagarRascunho(tipo, chave);
  }
}
