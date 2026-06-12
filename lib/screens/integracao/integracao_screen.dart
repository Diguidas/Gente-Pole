import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

class IntegracaoScreen extends StatefulWidget {
  const IntegracaoScreen({super.key});

  @override
  State<IntegracaoScreen> createState() => _IntegracaoScreenState();
}

class _IntegracaoScreenState extends State<IntegracaoScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _futureAdmissoes;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _carregar() {
    setState(() {
      _futureAdmissoes = _api.buscarAdmisoesIntegracao();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 220,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 24, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Integração',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Novos colaboradores aguardando integração',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Lista ────────────────────────────────────────────────
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 24),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _futureAdmissoes,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.magenta),
                          );
                        }

                        final lista = snap.data ?? [];

                        if (lista.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.people_alt_outlined,
                                    size: 56, color: AppColors.cinzaTexto),
                                const SizedBox(height: 16),
                                Text(
                                  'Nenhuma integração pendente',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.dark,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Todos os novos colaboradores\nforam integrados.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: AppColors.cinzaTexto),
                                ),
                              ],
                            ),
                          );
                        }

                        return RefreshIndicator(
                          color: AppColors.magenta,
                          onRefresh: () async => _carregar(),
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 20, 16, 40),
                            itemCount: lista.length,
                            itemBuilder: (ctx, i) =>
                                _cardAdmissao(lista[i]),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardAdmissao(Map<String, dynamic> adm) {
    final candidato = adm['candidatos'] as Map<String, dynamic>? ?? {};
    final nome = candidato['nome'] as String? ?? 'Candidato';
    final email = candidato['email'] as String? ?? '';
    final telefone = candidato['telefone'] as String? ?? '';
    final cidade = candidato['cidade'] as String?;
    final estado = candidato['estado'] as String?;
    final cargo = adm['cargo_admitido'] as String? ?? '';
    final setor = adm['setor_admitido'] as String? ?? '';
    final dataInicio = adm['data_inicio'] as String?;
    final admissaoId = adm['id'] as int;

    final iniciais = nome
        .trim()
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          // ── Info do candidato ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      iniciais,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF6366F1),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: AppColors.cinzaTexto),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Badge integração pendente
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Integração',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Detalhes do candidato ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                if (cargo.isNotEmpty)
                  _detalhe(Icons.work_outline_rounded, cargo),
                if (setor.isNotEmpty)
                  _detalhe(Icons.business_outlined, setor),
                if (telefone.isNotEmpty)
                  _detalhe(Icons.phone_outlined, telefone),
                if (cidade != null || estado != null)
                  _detalhe(Icons.location_on_outlined,
                      [cidade, estado].where((e) => e != null).join(', ')),
                if (dataInicio != null)
                  _detalhe(Icons.calendar_today_outlined,
                      'Início: ${_formatarData(dataInicio)}'),
              ],
            ),
          ),

          // ── Divisor ────────────────────────────────────────────────────
          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // ── Botão ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _confirmarConclusao(admissaoId, nome),
                icon: const Icon(Icons.check_circle_outline_rounded,
                    size: 18, color: Colors.white),
                label: Text(
                  'Integração realizada',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detalhe(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.cinzaTexto),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 12, color: AppColors.cinzaTexto)),
      ],
    );
  }

  String _formatarData(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.year}';
    } catch (_) {
      return iso;
    }
  }

  Future<void> _confirmarConclusao(int admissaoId, String nome) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Confirmar integração',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Text(
          'Confirmar que $nome concluiu a integração e está 100% na empresa?',
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: AppColors.cinzaTexto)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981), elevation: 0),
            child: Text('Confirmar',
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final ok = await _api.concluirIntegracao(admissaoId);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '$nome integrado com sucesso!' : 'Erro ao concluir integração',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: ok ? const Color(0xFF10B981) : AppColors.magenta,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    if (ok) _carregar();
  }
}
