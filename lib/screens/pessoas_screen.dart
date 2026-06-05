import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';
import '../models/colaborador_model.dart';
import '../services/api_service.dart';

class PessoasScreen extends StatefulWidget {
  const PessoasScreen({super.key});

  @override
  State<PessoasScreen> createState() => _PessoasScreenState();
}

class _PessoasScreenState extends State<PessoasScreen> {
  final _api = ApiService();
  ColaboradorModel? _supervisor;
  bool _loadingSupervisor = false;

  @override
  void initState() {
    super.initState();
    _carregarSupervisor();
  }

  Future<void> _carregarSupervisor() async {
    final supId = _api.colaboradorAtual?.supervisorId;
    if (supId == null) return;
    setState(() => _loadingSupervisor = true);
    final sup = await _api.buscarSupervisor(supId);
    if (mounted) setState(() { _supervisor = sup; _loadingSupervisor = false; });
  }

  @override
  Widget build(BuildContext context) {
    final c = _api.colaboradorAtual;
    if (c == null) {
      return const Center(child: Text('Sem dados de colaborador.'));
    }

    return Scaffold(
      body: Stack(
        children: [
          // Fundo gradiente
          Container(
            height: 220,
            decoration: const BoxDecoration(gradient: AppColors.gradientePrincipal),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // ── Header ──────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Row(children: [
                      Expanded(
                        child: Text('Meu Perfil',
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // ── Card principal ───────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 6))
                        ],
                      ),
                      child: Column(
                        children: [
                          // Avatar + nome + cargo
                          const SizedBox(height: 28),
                          _avatar(c, raio: 40),
                          const SizedBox(height: 14),
                          Text(c.nome,
                              style: GoogleFonts.poppins(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.dark),
                              textAlign: TextAlign.center,
                              maxLines: 2),
                          if (c.cargo != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(c.cargo!,
                                  style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: AppColors.cinzaTexto)),
                            ),
                          const SizedBox(height: 20),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),

                          // Dados em lista
                          _itemInfo(
                              Icons.badge_outlined, 'Matrícula', c.matricula),
                          if (c.setor != null)
                            _itemInfo(Icons.business_outlined, 'Setor', c.setor!),
                          if (c.dataAdmissaoFormatada != null)
                            _itemInfo(Icons.calendar_today_outlined,
                                'Admissão', c.dataAdmissaoFormatada!),
                          if (c.cpf != null)
                            _itemInfo(Icons.fingerprint_outlined, 'CPF',
                                _mascaraCpf(c.cpf!)),

                          // Supervisor
                          if (_loadingSupervisor)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                  color: AppColors.laranja, strokeWidth: 2),
                            )
                          else if (_supervisor != null)
                            _itemInfoWidget(
                              Icons.person_outline,
                              'Supervisor',
                              Row(children: [
                                _avatar(_supervisor!, raio: 12),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_supervisor!.nome,
                                      style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.dark),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ]),
                            ),

                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(ColaboradorModel c, {double raio = 22}) {
    final iniciais = _iniciais(c.nome);
    return CircleAvatar(
      radius: raio,
      backgroundColor: AppColors.laranja.withOpacity(0.15),
      backgroundImage: c.fotoUrl != null ? NetworkImage(c.fotoUrl!) : null,
      child: c.fotoUrl == null
          ? Text(iniciais,
              style: GoogleFonts.poppins(
                  fontSize: raio * 0.55,
                  fontWeight: FontWeight.w700,
                  color: AppColors.laranja))
          : null,
    );
  }

  Widget _itemInfo(IconData icon, String label, String valor) =>
      _itemInfoWidget(icon, label,
          Text(valor,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.dark)));

  Widget _itemInfoWidget(IconData icon, String label, Widget valor) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.laranja.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: AppColors.laranja),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: AppColors.cinzaTexto)),
                  const SizedBox(height: 2),
                  valor,
                ],
              ),
            ),
          ],
        ),
      );

  String _iniciais(String nome) {
    final p = nome.trim().split(' ');
    return p.length >= 2
        ? '${p.first[0]}${p.last[0]}'.toUpperCase()
        : nome.isNotEmpty ? nome[0].toUpperCase() : '?';
  }

  String _mascaraCpf(String cpf) {
    if (cpf.length != 11) return cpf;
    return '${cpf.substring(0, 3)}.${cpf.substring(3, 6)}.${cpf.substring(6, 9)}-${cpf.substring(9)}';
  }
}