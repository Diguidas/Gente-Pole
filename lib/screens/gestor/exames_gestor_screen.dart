import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const _rotulosTipo = {
  'periodico': 'Periódico',
  'demissional': 'Demissional',
  'retorno': 'Retorno',
  'mudanca_funcao': 'Mudança de Função',
  'consulta': 'Consulta',
};

/// Exames agendados pelo SESMT pra equipe do gestor, aguardando confirmação
/// — só depois de confirmado o colaborador vê no feed.
class ExamesGestorScreen extends StatefulWidget {
  const ExamesGestorScreen({super.key});

  @override
  State<ExamesGestorScreen> createState() => _ExamesGestorScreenState();
}

class _ExamesGestorScreenState extends State<ExamesGestorScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _erro;
  List<Map<String, dynamic>> _exames = [];
  final Set<int> _confirmando = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final exames = await _api.listarExamesAguardandoConfirmacao();
      if (!mounted) return;
      setState(() {
        _exames = exames;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar exames: $e';
        _loading = false;
      });
    }
  }

  Future<void> _confirmar(int exameId) async {
    setState(() => _confirmando.add(exameId));
    try {
      await _api.confirmarExame(exameId);
      if (!mounted) return;
      setState(() {
        _exames.removeWhere((e) => e['id'] == exameId);
        _confirmando.remove(exameId);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Exame confirmado — já aparece para o colaborador.',
            style: GoogleFonts.poppins()),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _confirmando.remove(exameId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao confirmar: $e', style: GoogleFonts.poppins()),
        backgroundColor: AppColors.magenta,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  String _formatarData(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
          '${dt.hour != 0 || dt.minute != 0 ? ' às ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}' : ''}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: AppColors.dark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Exames',
            style: GoogleFonts.poppins(
                fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.magenta))
          : _erro != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: AppColors.cinzaTexto),
                      const SizedBox(height: 12),
                      Text(_erro!,
                          style: GoogleFonts.poppins(color: AppColors.cinzaTexto),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _carregar,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.magenta),
                        child: Text('Tentar novamente',
                            style: GoogleFonts.poppins(color: Colors.white)),
                      ),
                    ],
                  ),
                )
              : _exames.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 48, color: AppColors.cinzaTexto),
                          const SizedBox(height: 12),
                          Text('Nenhum exame aguardando confirmação.',
                              style:
                                  GoogleFonts.poppins(color: AppColors.cinzaTexto)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _carregar,
                      color: AppColors.magenta,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _exames.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final e = _exames[i];
                          final colaborador =
                              e['colaborador'] as Map<String, dynamic>? ?? {};
                          final nome = colaborador['nome'] as String? ?? '—';
                          final cargo = colaborador['cargo'] as String? ?? '';
                          final tipo = _rotulosTipo[e['tipo']] ?? e['tipo'] ?? '';
                          final clinica = e['clinica'] as String?;
                          final confirmando = _confirmando.contains(e['id']);

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(nome,
                                    style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.dark)),
                                if (cargo.isNotEmpty)
                                  Text(cargo,
                                      style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: AppColors.cinzaTexto)),
                                const SizedBox(height: 10),
                                Wrap(spacing: 6, runSpacing: 6, children: [
                                  _chip(tipo, AppColors.magenta),
                                  _chip(
                                      _formatarData(
                                          e['data_agendamento'] as String?),
                                      AppColors.cinzaTexto),
                                  if (clinica != null && clinica.isNotEmpty)
                                    _chip(clinica, const Color(0xFF0EA5E9)),
                                ]),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: confirmando
                                        ? null
                                        : () => _confirmar(e['id'] as int),
                                    icon: confirmando
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white))
                                        : const Icon(Icons.check,
                                            size: 16, color: Colors.white),
                                    label: Text('Confirmar',
                                        style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF16A34A),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
}
