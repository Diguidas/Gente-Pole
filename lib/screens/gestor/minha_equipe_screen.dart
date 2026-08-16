import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';

class MinhaEquipeScreen extends StatefulWidget {
  const MinhaEquipeScreen({super.key});

  @override
  State<MinhaEquipeScreen> createState() => _MinhaEquipeScreenState();
}

class _MinhaEquipeScreenState extends State<MinhaEquipeScreen> {
  final _api = ApiService();
  late Future<List<ColaboradorModel>> _futureEquipe;
  final _buscaCtrl = TextEditingController();
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _futureEquipe = _api.buscarMinhaEquipe();
    _buscaCtrl.addListener(() => setState(() => _busca = _buscaCtrl.text));
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  List<ColaboradorModel> _filtrar(List<ColaboradorModel> equipe) {
    final q = _busca.trim().toLowerCase();
    if (q.isEmpty) return equipe;
    return equipe.where((c) {
      final nome = c.nome.toLowerCase();
      final cargo = (c.cargo ?? '').toLowerCase();
      final matricula = c.matricula.toLowerCase();
      return nome.contains(q) || cargo.contains(q) || matricula.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final setor = _api.colaboradorAtual?.setor ?? '';

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
                              'Minha Equipe',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (setor.isNotEmpty)
                              Text(
                                setor,
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
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 24),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: FutureBuilder<List<ColaboradorModel>>(
                      future: _futureEquipe,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.magenta),
                          );
                        }

                        final equipeCompleta = snap.data ?? [];
                        final equipe = _filtrar(equipeCompleta);

                        if (equipeCompleta.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.group_outlined,
                                    size: 56, color: AppColors.cinzaTexto),
                                const SizedBox(height: 16),
                                Text(
                                  'Nenhum colaborador encontrado',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.dark,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Nenhum colaborador no seu setor.',
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
                          onRefresh: () async {
                            setState(() {
                              _futureEquipe = _api.buscarMinhaEquipe();
                            });
                          },
                          child: ListView(
                            padding:
                                const EdgeInsets.fromLTRB(16, 20, 16, 32),
                            children: [
                              TextField(
                                controller: _buscaCtrl,
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText:
                                      'Buscar por nome, cargo ou matrícula...',
                                  hintStyle: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: AppColors.cinzaTexto),
                                  prefixIcon: const Icon(Icons.search_rounded,
                                      size: 20),
                                  suffixIcon: _busca.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(
                                              Icons.close_rounded,
                                              size: 18),
                                          onPressed: () =>
                                              _buscaCtrl.clear(),
                                        ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '${equipe.length} colaborador${equipe.length == 1 ? '' : 'es'}',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.cinzaTexto,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (equipe.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 24),
                                  child: Center(
                                    child: Text(
                                      'Nenhum colaborador encontrado.',
                                      style: GoogleFonts.poppins(
                                          color: AppColors.cinzaTexto),
                                    ),
                                  ),
                                )
                              else
                                ...equipe.map((c) => _cardColaborador(c)),
                            ],
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

  Widget _cardColaborador(ColaboradorModel c) {
    final iniciais = c.nome
        .trim()
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.laranja.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: c.fotoUrl != null
                ? ClipOval(
                    child: Image.network(c.fotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _avatarIniciais(iniciais)),
                  )
                : _avatarIniciais(iniciais),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.nome,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.dark,
                  ),
                ),
                if (c.cargo != null && c.cargo!.isNotEmpty)
                  Text(
                    c.cargo!,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.cinzaTexto),
                  ),
              ],
            ),
          ),
          Text(
            c.matricula,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.cinzaTexto,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarIniciais(String iniciais) {
    return Center(
      child: Text(
        iniciais,
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.laranja,
        ),
      ),
    );
  }
}
