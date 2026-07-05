import 'package:flutter/material.dart';
import 'package:gentepole/screens/feedback/feedback_screen.dart';
import 'package:gentepole/screens/lojinha/lojinha_home_screen.dart';
import 'package:gentepole/screens/massoterapia/massoterapia_screen.dart';
import 'package:gentepole/screens/nutricionista/nutricionista_screen.dart';
import 'package:gentepole/screens/cardapio/cardapio_screen.dart';
import 'package:gentepole/screens/ponto/ponto_screen.dart';
import 'package:gentepole/screens/reserva_salas/reserva_salas_screen.dart';
import 'package:gentepole/screens/conexoes/conexoes_do_bem_screen.dart';
import 'package:gentepole/screens/ouvidoria/ouvidoria_screen.dart';
import 'package:gentepole/screens/oportunidades/eu_crio_oportunidades_screen.dart';
import 'package:gentepole/screens/pesquisa/pesquisa_list_screen.dart';
import 'plantao_psicologico_screen.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import 'gestor/gestor_screen.dart';
import 'integracao/integracao_screen.dart';

class ServicosScreen extends StatefulWidget {
  const ServicosScreen({super.key});

  @override
  State<ServicosScreen> createState() => _ServicosScreenState();
}

class _ServicosScreenState extends State<ServicosScreen> {
  final _api = ApiService();
  bool _ehGestor = false;
  bool _ehIntegracao = false;
  bool _loadingPerfis = true;
  bool _nutricionistaAtivo = false;

  @override
  void initState() {
    super.initState();
    _verificarPerfis();
  }

  Future<void> _verificarPerfis() async {
    final resultados = await Future.wait([
      _api.verificarSeEhGestor(),
      _api.verificarSeEhIntegracao(),
      _api.buscarDiasDisponiveisNutricionista(),
    ]);
    if (mounted) {
      setState(() {
        _ehGestor = resultados[0] as bool;
        _ehIntegracao = resultados[1] as bool;
        _nutricionistaAtivo = (resultados[2] as List).isNotEmpty;
        _loadingPerfis = false;
      });
    }
  }

  void _abrirCardapio() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CardapioScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(28),
            ),
            child: Image.asset(
              'assets/banner_servicos.png',
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Serviços',
                              style: AppTextStyles.tituloGrande.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Benefícios para você',
                              style: AppTextStyles.corpoBranco.copyWith(
                                color: AppColors.brancoOp80,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _loadingPerfis ? null : _verificarPerfis,
                        icon: _loadingPerfis
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.refresh_rounded,
                                color: Colors.white,
                              ),
                        tooltip: 'Atualizar',
                      ),
                    ],
                  ),
                ),

                // ── Corpo ────────────────────────────────────────────────────
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_loadingPerfis) const SizedBox.shrink(),

                          // ── Painel do Gestor ──────────────────────────────
                          if (!_loadingPerfis && _ehGestor) ...[
                            _sectionLabel(
                              'Painel do Gestor',
                              AppColors.laranja,
                            ),
                            const SizedBox(height: 10),
                            _botaoServico(
                              context,
                              icone: Icons.work_outline_rounded,
                              titulo: 'Painel do Gestor',
                              subtitulo:
                                  'Solicite vagas e acompanhe candidatos',
                              cor: AppColors.laranja,
                              emBreve: false,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const GestorScreen(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // ── Integração ────────────────────────────────────
                          if (!_loadingPerfis && _ehIntegracao) ...[
                            _sectionLabel(
                              'Integração',
                              const Color(0xFF6366F1),
                            ),
                            const SizedBox(height: 10),
                            _botaoServico(
                              context,
                              icone: Icons.people_alt_outlined,
                              titulo: 'Integração',
                              subtitulo: 'Receba e integre novos colaboradores',
                              cor: const Color(0xFF6366F1),
                              emBreve: false,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const IntegracaoScreen(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // ── Serviços para Colaboradores ───────────────────
                          if (!_loadingPerfis)
                            _sectionLabel(
                              'Serviços para Colaboradores',
                              AppColors.cinzaTexto,
                            ),
                          const SizedBox(height: 16),

                          _botaoServico(
                            context,
                            icone: Icons.storefront_outlined,
                            titulo: 'Lojinha',
                            subtitulo: 'Produtos e benefícios exclusivos',
                            cor: AppColors.laranja,
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LojinhaHomeScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Mude para true para exibir nas demonstrações
                          if (false) ...[
                            _botaoServico(
                              context,
                              icone: Icons.forum_outlined,
                              titulo: 'Feedback',
                              subtitulo: 'Envie e receba feedbacks dos colegas',
                              cor: AppColors.laranja,
                              emBreve: false,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const FeedbackScreen(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          _botaoServico(
                            context,
                            icone: Icons.poll_outlined,
                            titulo: 'Pesquisas',
                            subtitulo: 'Responda às pesquisas da empresa',
                            cor: AppColors.magenta,
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PesquisaListScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ── Cardápio ──────────────────────────────────────
                          _botaoServico(
                            context,
                            icone: Icons.restaurant_menu_outlined,
                            titulo: 'Cardápio do Refeitório',
                            subtitulo: 'Veja o cardápio do dia',
                            cor: const Color(0xFFF59E0B),
                            emBreve: false,
                            onTap: _abrirCardapio,
                          ),
                          const SizedBox(height: 14),

                          // ── Ponto ─────────────────────────────────────────
                          _botaoServico(
                            context,
                            icone: Icons.access_time_rounded,
                            titulo: 'Calculadora de Ponto',
                            subtitulo: 'Registre e acompanhe suas horas',
                            cor: const Color(0xFF0EA5E9),
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PontoScreen()),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ── Reserva de Salas ──────────────────────────────
                          _botaoServico(
                            context,
                            icone: Icons.meeting_room_outlined,
                            titulo: 'Reserva de Salas',
                            subtitulo: 'Copa, salas de reunião e auditório',
                            cor: const Color(0xFF0891B2),
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ReservaSalasScreen()),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // ── Bem na Pole ───────────────────────────────────
                          _sectionLabel('Bem na Pole', AppColors.magenta),
                          const SizedBox(height: 10),

                          _botaoServico(
                            context,
                            icone: Icons.self_improvement_rounded,
                            titulo: 'Massoterapia',
                            subtitulo: 'Agende sua sessão de bem-estar',
                            cor: AppColors.magenta,
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MassoterapiaScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          _botaoServico(
                            context,
                            icone: Icons.local_dining_outlined,
                            titulo: 'Nutricionista',
                            subtitulo: _nutricionistaAtivo
                                ? 'Agende uma consulta nutricional'
                                : 'Sem datas disponíveis no momento',
                            cor: const Color(0xFF10B981),
                            emBreve: !_nutricionistaAtivo,
                            onTap: _nutricionistaAtivo
                                ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const NutricionistaScreen(),
                                    ),
                                  )
                                : () => ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Sem datas disponíveis no momento.',
                                          ),
                                          backgroundColor: Color(0xFF10B981),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      ),
                          ),
                          const SizedBox(height: 14),

                          _botaoServico(
                            context,
                            icone: Icons.psychology_outlined,
                            titulo: 'Plantão Psicológico',
                            subtitulo: 'Apoio emocional e saúde mental',
                            cor: const Color(0xFF7C3AED),
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const PlantaoPsicologicoScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          _botaoServico(
                            context,
                            icone: Icons.favorite_outline_rounded,
                            titulo: 'Conexões do Bem',
                            subtitulo:
                                'Voluntariado e indicação de instituições',
                            cor: const Color(0xFFEC4899),
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ConexoesDoiemScreen(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // ── Eu Crio Oportunidades ─────────────────────────
                          _sectionLabel(
                            'Eu Crio Oportunidades',
                            const Color(0xFF10B981),
                          ),
                          const SizedBox(height: 10),

                          _botaoServico(
                            context,
                            icone: Icons.volunteer_activism_outlined,
                            titulo: 'Eu Crio Oportunidades',
                            subtitulo:
                                'Candidate-se ou indique para vagas abertas',
                            cor: const Color(0xFF10B981),
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const EuCrioOportunidadesScreen(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // ── Canal de Comunicação ──────────────────────────
                          _sectionLabel(
                            'Canal de Comunicação',
                            const Color(0xFF64748B),
                          ),
                          const SizedBox(height: 10),

                          _botaoServico(
                            context,
                            icone: Icons.record_voice_over_outlined,
                            titulo: 'Ouvidoria',
                            subtitulo: 'Relate ocorrências e dê sugestões',
                            cor: const Color(0xFF64748B),
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const OuvidoriaScreen(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
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

  Widget _sectionLabel(String label, Color cor) {
    return Text(
      label,
      style: AppTextStyles.corpoMenor.copyWith(
        color: cor,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _botaoServico(
    BuildContext context, {
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required Color cor,
    required bool emBreve,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap:
          onTap ??
          () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$titulo estará disponível em breve! 🚀',
                  style: AppTextStyles.corpoNormal.copyWith(
                    color: Colors.white,
                  ),
                ),
                backgroundColor: cor,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: cor.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icone, color: cor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          titulo,
                          style: AppTextStyles.labelSecao.copyWith(
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (emBreve) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Em breve',
                            style: AppTextStyles.corpoMinimo.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: cor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitulo, style: AppTextStyles.corpoCinza),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.cinzaTexto,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
