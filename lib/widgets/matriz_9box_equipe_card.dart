import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import 'grid_9box.dart';

/// Matriz 9Box da equipe do gestor logado, em formato de cartão — fica dentro
/// de "Avaliar Equipe" (igual ao web). Reúne todos os setores sob a
/// responsabilidade do gestor, com as avaliações concluídas do ciclo mais
/// recente de cada setor.
class Matriz9BoxEquipeCard extends StatefulWidget {
  const Matriz9BoxEquipeCard({super.key});

  @override
  State<Matriz9BoxEquipeCard> createState() => _Matriz9BoxEquipeCardState();
}

class _Matriz9BoxEquipeCardState extends State<Matriz9BoxEquipeCard> {
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
    try {
      final setores = await _api.buscarSetoresEfetivosDoGestor();
      final avaliacoes = await _api.listarAvaliacoesMatrizEquipe(setores,
          responsavelId: _api.colaboradorAtual?.id);
      final ids = avaliacoes
          .map((a) => a['template_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();
      final r = await Future.wait([
        _api.buscarPesosTemplates(ids),
        _api.listarNineBoxLegendas(),
        _api.buscarPesosCiclos(avaliacoes
            .map((a) => a['ciclo_id'] as int?)
            .whereType<int>()
            .toSet()
            .toList()),
      ]);
      if (!mounted) return;
      setState(() {
        _avaliacoes = avaliacoes;
        // Pesos do ciclo (chave negativa) convivem com os do template.
        _pesos = {
          ...r[0] as Map<int, Map<String, int>>,
          ...r[2] as Map<int, Map<String, int>>,
        };
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
      builder: (_) => DetalheColaboradorAvaliacaoDialog(
          avaliacao: avaliacao, pesos: _pesos, legendas: _legendas),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator(color: AppColors.laranja)),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Matriz 9Box da equipe',
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark)),
          const SizedBox(height: 4),
          Text(
              _avaliacoes.isEmpty
                  ? 'Nenhuma avaliação concluída ainda. Quando você concluir avaliações, os colaboradores aparecem na matriz.'
                  : 'Toque num quadrante para ver a descrição e as pessoas.',
              style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.cinzaTexto)),
          const SizedBox(height: 14),
          Grid9Box(
            avaliacoes: _avaliacoes,
            pesos: _pesos,
            legendas: _legendas,
            onTapColaborador: _abrirDetalhe,
          ),
        ],
      ),
    );
  }
}
