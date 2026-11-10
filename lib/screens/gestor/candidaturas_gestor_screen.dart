import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

/// Candidaturas de colaboradores da equipe (via "Eu Crio Oportunidades")
/// aguardando a decisão do gestor direto. Só depois de aprovadas chegam ao
/// RH/Seleção; ao reprovar, o gestor informa o motivo e o colaborador vê.
/// Espelha `candidaturas_gestor_screen.dart` do painel web.
class CandidaturasGestorScreen extends StatefulWidget {
  const CandidaturasGestorScreen({super.key});

  @override
  State<CandidaturasGestorScreen> createState() =>
      _CandidaturasGestorScreenState();
}

class _CandidaturasGestorScreenState extends State<CandidaturasGestorScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _erro;
  List<Map<String, dynamic>> _pedidos = [];
  final Set<dynamic> _processando = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final meuId = _api.colaboradorAtual?.id;
    if (meuId == null) {
      setState(() {
        _loading = false;
        _erro = 'Perfil de colaborador não encontrado.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final pedidos = await _api.listarCandidaturasPendentesGestor(meuId);
      if (!mounted) return;
      setState(() {
        _pedidos = pedidos;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar as candidaturas.';
        _loading = false;
      });
    }
  }

  Future<void> _decidir(Map<String, dynamic> p, bool aprovado) async {
    String? motivo;
    if (!aprovado) {
      motivo = await _pedirMotivo();
      if (motivo == null) return; // cancelou
    }
    setState(() => _processando.add(p['id']));
    try {
      await _api.decidirCandidaturaGestor(
          pedido: p, aprovado: aprovado, motivo: motivo);
      if (!mounted) return;
      setState(() {
        _pedidos.removeWhere((e) => e['id'] == p['id']);
        _processando.remove(p['id']);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(aprovado
            ? 'Candidatura aprovada — enviada ao RH.'
            : 'Candidatura reprovada — o colaborador verá o motivo.'),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _processando.remove(p['id']));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não foi possível registrar a decisão. Tente novamente.'),
        backgroundColor: AppColors.erro,
      ));
    }
  }

  Future<String?> _pedirMotivo() async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Motivo da reprovação',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            autofocus: true,
            onChanged: (_) => setD(() {}),
            decoration: const InputDecoration(
                hintText: 'Explique ao colaborador o motivo...'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: ctrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Reprovar'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return res;
  }

  String _data(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        title: Text('Candidaturas',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppColors.dark)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.dark,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text(_erro!))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text('Candidaturas da equipe',
                          style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dark)),
                      const SizedBox(height: 4),
                      Text(
                          'Colaboradores que se candidataram a vagas e aguardam a sua aprovação.',
                          style: GoogleFonts.poppins(
                              fontSize: 12.5, color: AppColors.cinzaTexto)),
                      const SizedBox(height: 16),
                      if (_pedidos.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                              child: Text('Nenhuma candidatura pendente.',
                                  style: GoogleFonts.poppins(
                                      color: AppColors.cinzaTexto))),
                        )
                      else
                        for (final p in _pedidos)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p['colaborador_nome'] as String,
                                    style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.dark)),
                                const SizedBox(height: 2),
                                Text(
                                    'Vaga: ${p['vaga_titulo'] ?? '-'} · ${_data(p['criado_em'] as String?)}',
                                    style: GoogleFonts.poppins(
                                        fontSize: 12.5,
                                        color: AppColors.cinzaTexto)),
                                const SizedBox(height: 12),
                                Row(children: [
                                  ElevatedButton.icon(
                                    onPressed: _processando.contains(p['id'])
                                        ? null
                                        : () => _decidir(p, true),
                                    icon: const Icon(Icons.check_rounded,
                                        size: 18),
                                    label: const Text('Aprovar'),
                                  ),
                                  const SizedBox(width: 10),
                                  OutlinedButton.icon(
                                    onPressed: _processando.contains(p['id'])
                                        ? null
                                        : () => _decidir(p, false),
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18, color: AppColors.erro),
                                    label: const Text('Reprovar',
                                        style:
                                            TextStyle(color: AppColors.erro)),
                                  ),
                                ]),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
    );
  }
}
