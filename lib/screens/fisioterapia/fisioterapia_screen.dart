import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/fisioterapia_model.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FisioterapiaScreen (colaborador)
// Somente leitura: caso atual (patologia), sessões e exercícios prescritos.
// ─────────────────────────────────────────────────────────────────────────────

class FisioterapiaScreen extends StatefulWidget {
  const FisioterapiaScreen({super.key});

  @override
  State<FisioterapiaScreen> createState() => _FisioterapiaScreenState();
}

class _FisioterapiaScreenState extends State<FisioterapiaScreen> {
  final _api = ApiService();

  bool _loading = true;
  String? _erro;
  FisioterapiaCaso? _caso;
  List<FisioterapiaSessao> _sessoes = [];
  List<FisioterapiaExercicio> _exercicios = [];

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
      final caso = await _api.buscarMeuCasoFisioterapia();
      List<FisioterapiaSessao> sessoes = [];
      List<FisioterapiaExercicio> exercicios = [];
      if (caso != null) {
        final resultados = await Future.wait([
          _api.listarSessoesDoCasoFisioterapia(caso.id),
          _api.listarExerciciosFisioterapia(caso.id),
        ]);
        sessoes = resultados[0] as List<FisioterapiaSessao>;
        exercicios = resultados[1] as List<FisioterapiaExercicio>;
      }
      setState(() {
        _caso = caso;
        _sessoes = sessoes;
        _exercicios = exercicios;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao carregar. Tente novamente.';
        _loading = false;
      });
    }
  }

  String get _statusLabel => switch (_caso?.status) {
        'em_espera' => 'Em espera',
        'ativo' => 'Em tratamento',
        'alta' => 'Alta',
        'encerrado_sesmt' => 'Encerrado',
        _ => '—',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                child: Container(
                  height: 160,
                  width: double.infinity,
                  decoration: const BoxDecoration(gradient: AppColors.gradientePrincipal),
                  child: const Center(
                    child: Icon(Icons.accessibility_new_rounded, size: 56, color: Colors.white70),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fisioterapia', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700)),
                Text('Acompanhe seu tratamento',
                    style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.laranja))
                  : _erro != null
                      ? _buildErro()
                      : _caso == null
                          ? _buildSemCaso()
                          : _buildConteudo(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_erro!, textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _carregar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.laranja,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Tentar novamente', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSemCaso() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: AppColors.laranja.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.event_busy_rounded, size: 40, color: AppColors.laranja),
            ),
            const SizedBox(height: 20),
            Text('Nenhum caso de fisioterapia',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
            const SizedBox(height: 8),
            Text('Você ainda não possui um caso de fisioterapia cadastrado pelo SESMT.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _buildConteudo() {
    final caso = _caso!;
    return RefreshIndicator(
      color: AppColors.laranja,
      onRefresh: _carregar,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCasoBanner(caso),
            const SizedBox(height: 24),
            _buildSectionLabel('🏋️ Exercícios prescritos'),
            const SizedBox(height: 10),
            _buildExercicios(),
            const SizedBox(height: 24),
            _buildSectionLabel('📅 Sessões'),
            const SizedBox(height: 10),
            _buildSessoes(),
          ],
        ),
      ),
    );
  }

  Widget _buildCasoBanner(FisioterapiaCaso caso) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.gradientePrincipal,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(caso.patologia,
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_statusLabel,
                  style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ]),
          if (caso.sessoesPrevistas != null) ...[
            const SizedBox(height: 8),
            Text('${caso.sessoesPrevistas} sessões previstas',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.white.withOpacity(0.85))),
          ],
        ],
      ),
    );
  }

  Widget _buildExercicios() {
    if (_exercicios.isEmpty) {
      return _buildVazioCard('Nenhum exercício prescrito ainda.');
    }
    return Column(
      children: _exercicios.map((ex) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.laranja.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.fitness_center_rounded, color: AppColors.laranja, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ex.descricao, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                    if (ex.frequencia != null)
                      Text(ex.frequencia!, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSessoes() {
    if (_sessoes.isEmpty) {
      return _buildVazioCard('Nenhuma sessão registrada ainda.');
    }
    return Column(
      children: _sessoes.map((s) {
        final cor = switch (s.status) {
          'VEIO' => AppColors.sucesso,
          'NAO_VEIO' => AppColors.erro,
          _ => AppColors.laranja,
        };
        final label = switch (s.status) {
          'VEIO' => 'Atendido',
          'NAO_VEIO' => 'Faltou',
          _ => 'Agendado',
        };
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('${s.data.day.toString().padLeft(2, '0')}/${s.data.month.toString().padLeft(2, '0')}/${s.data.year} às ${s.horario}',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cor.withOpacity(0.3)),
                  ),
                  child: Text(label, style: GoogleFonts.poppins(fontSize: 10, color: cor, fontWeight: FontWeight.w600)),
                ),
              ]),
              if (s.evolucao != null && s.evolucao!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(s.evolucao!, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildVazioCard(String texto) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Center(
        child: Text(texto, style: GoogleFonts.poppins(color: Colors.grey.shade500, fontSize: 13)),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(label,
        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87));
  }
}
