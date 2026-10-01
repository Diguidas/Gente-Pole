import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/grid_9box.dart';

/// Matriz 9Box fixa da equipe do gestor: sempre acessível, mostra as
/// avaliações concluídas do ciclo mais recente de cada setor.
class Matriz9BoxScreen extends StatefulWidget {
  const Matriz9BoxScreen({super.key});

  @override
  State<Matriz9BoxScreen> createState() => _Matriz9BoxScreenState();
}

class _Matriz9BoxScreenState extends State<Matriz9BoxScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _avaliacoes = [];
  Map<int, Map<String, int>> _pesos = {};
  Map<String, String> _legendas = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final setores = await _api.buscarSetoresEfetivosDoGestor();
      final avaliacoes = await _api.listarAvaliacoesMatrizEquipe(setores);
      final ids = avaliacoes
          .map((a) => a['template_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();
      final r = await Future.wait([
        _api.buscarPesosTemplates(ids),
        _api.listarNineBoxLegendas(),
      ]);
      if (!mounted) return;
      setState(() {
        _avaliacoes = avaliacoes;
        _pesos = r[0] as Map<int, Map<String, int>>;
        _legendas = r[1] as Map<String, String>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _abrirDetalhe(Map<String, dynamic> avaliacao) {
    showDialog(
      context: context,
      builder: (_) =>
          DetalheColaboradorAvaliacaoDialog(avaliacao: avaliacao, pesos: _pesos),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Matriz 9Box',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                      _avaliacoes.isEmpty
                          ? 'Nenhuma avaliação concluída ainda. Quando você concluir avaliações, os colaboradores aparecem aqui.'
                          : 'Toque num nome para ver o detalhe.',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.cinzaTexto)),
                  const SizedBox(height: 14),
                  Grid9Box(
                    avaliacoes: _avaliacoes,
                    pesos: _pesos,
                    legendas: _legendas,
                    onTapColaborador: _abrirDetalhe,
                  ),
                ],
              ),
            ),
    );
  }
}
