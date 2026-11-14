import 'package:flutter/material.dart';
import 'package:gentepole/screens/lojinha/lojinha_home_screen.dart';
import 'package:gentepole/screens/cardapio/cardapio_screen.dart';
import 'package:gentepole/screens/reserva_salas/reserva_salas_screen.dart';
import 'package:gentepole/screens/ouvidoria/ouvidoria_screen.dart';
import 'package:gentepole/screens/oportunidades/eu_crio_oportunidades_screen.dart';
import 'package:gentepole/screens/pesquisa/pesquisa_list_screen.dart';
import 'package:gentepole/screens/solicitacoes/solicitacoes_screen.dart';
import 'bem_na_pole_screen.dart';
import 'feedback/elogiar_screen.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import 'gestor/gestor_screen.dart';
import 'performance/performance_colab_screen.dart';
import 'gamificacao/gamificacao_screen.dart';
import 'integracao/integracao_screen.dart';
import 'documentos/documentos_institucionais_screen.dart';
import 'manual_uso/manual_uso_screen.dart';
import 'contracheque/contracheque_screen.dart';
import 'acesso_rapido/acesso_rapido_screen.dart';
import 'ti/chamados_ti_screen.dart';
import 'locomocao/locomocao_screen.dart';
import 'visitantes/visitantes_screen.dart';
import 'cadastro/atualizacao_cadastral_screen.dart';
import '../widgets/cracha_virtual_dialog.dart';

class ServicosScreen extends StatefulWidget {
  const ServicosScreen({super.key});

  @override
  State<ServicosScreen> createState() => _ServicosScreenState();
}

class _ServicosScreenState extends State<ServicosScreen> {
  final _api = ApiService();
  bool _ehGestor = false;
  bool _liderAutorizado = false;
  bool _ehRequisitanteVaga = false;
  bool _ehIntegracao = false;
  bool _polecoinAtivo = true;
  bool _contrachequeAtivo = true;
  bool _massoterapiaDisponivel = false;
  bool _nutricaoDisponivel = false;
  bool _loadingPerfis = true;

  @override
  void initState() {
    super.initState();
    _verificarPerfis();
  }

  Future<void> _verificarPerfis() async {
    final filial = _api.colaboradorAtual?.filialEfetiva;
    final resultados = await Future.wait([
      _api.verificarSeEhGestor(),
      _api.colaboradorEhLiderAutorizado(),
      _api.verificarSeEhIntegracao(),
      _api.gamificacaoAtiva(),
      _api.filialTemMassoterapiaConfigurada(filial),
      _api.filialTemNutricaoConfigurada(filial),
      _api.folhaContrachequeAtiva(),
      _api.verificarSeEhRequisitanteDeVaga(),
    ]);
    Set<String> bloqueadas = {};
    try {
      bloqueadas = await _api.listarFuncionalidadesGestorBloqueadas();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _ehGestor = resultados[0];
        _liderAutorizado = resultados[1];
        _ehIntegracao = resultados[2];
        _polecoinAtivo = resultados[3];
        _massoterapiaDisponivel = resultados[4];
        _nutricaoDisponivel = resultados[5];
        _contrachequeAtivo = resultados[6];
        // Requisitante puro com Vagas bloqueada não tem nada pra ver em
        // Gestão de Equipe (no web a área inteira some).
        _ehRequisitanteVaga =
            resultados[7] && !bloqueadas.contains('vagas_gestor');
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
                    clipBehavior: Clip.antiAlias,
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

                          // ── Gestão de Equipe ──────────────────────────────
                          // Aparece pra quem lidera alguém de verdade
                          // (colaborador_hierarquia) — ter o cadastro
                          // eh_gestor/nível de gestão sozinho não basta mais —
                          // ou pra quem é só requisitante de vaga, mas nesse
                          // caso a tela abre restrita só à aba Vagas (mesma
                          // regra do painel web: requisitante nunca ganha as
                          // demais telas de gestor).
                          if (!_loadingPerfis &&
                              ((_ehGestor && _liderAutorizado) || _ehRequisitanteVaga)) ...[
                            _sectionLabel(
                              'Gestão de Equipe',
                              AppColors.laranja,
                            ),
                            const SizedBox(height: 10),
                            _botaoServico(
                              context,
                              icone: Icons.work_outline_rounded,
                              titulo: 'Gestão de Equipe',
                              subtitulo:
                                  'Solicite vagas e acompanhe candidatos',
                              cor: AppColors.laranja,
                              emBreve: false,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => GestorScreen(
                                    apenasVagas: !(_ehGestor && _liderAutorizado),
                                  ),
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

                          _botaoServico(
                            context,
                            icone: Icons.directions_car_outlined,
                            titulo: 'Locomoção',
                            subtitulo: 'Como você vai para a empresa',
                            cor: AppColors.laranja,
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LocomocaoScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          _botaoServico(
                            context,
                            icone: Icons.badge_outlined,
                            titulo: 'Visitantes',
                            subtitulo: 'Cadastre quem vai te visitar',
                            cor: const Color(0xFF0D9488),
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const VisitantesScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          if (!_loadingPerfis && _polecoinAtivo) ...[
                            _botaoServico(
                              context,
                              icone: Icons.emoji_events_outlined,
                              titulo: 'Polecoin',
                              subtitulo: 'Seus pontos e o ranking da sua filial',
                              cor: AppColors.magenta,
                              emBreve: false,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const GamificacaoScreen(),
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

                          _botaoServico(
                            context,
                            icone: Icons.favorite_rounded,
                            titulo: 'Elogiar',
                            subtitulo: 'Reconheça e seja reconhecido por colegas',
                            cor: AppColors.magenta,
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ElogiarScreen(),
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
                          const SizedBox(height: 14),

                          const SizedBox(height: 28),

                          // ── Bem na Pole ───────────────────────────────────
                          _botaoServico(
                            context,
                            icone: Icons.spa_outlined,
                            titulo: 'Bem na Pole',
                            subtitulo: 'Massoterapia, nutrição, fisioterapia e mais',
                            cor: AppColors.magenta,
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BemNaPoleScreen(
                                  massoterapiaDisponivel: _massoterapiaDisponivel,
                                  nutricaoDisponivel: _nutricaoDisponivel,
                                ),
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
                            titulo: 'Fale com a Gente',
                            subtitulo: 'Relate ocorrências, sugestões ou denúncias',
                            cor: const Color(0xFF64748B),
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const OuvidoriaScreen(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // ── Meu Desenvolvimento ───────────────────────────
                          // Os 4 itens aparecem sempre — cada tela de destino
                          // já trata sozinha o caso de não ter nada
                          // pendente/aberto no momento (mensagem própria).
                          _sectionLabel(
                            'Meu Desenvolvimento',
                            const Color(0xFF6366F1),
                          ),
                          const SizedBox(height: 10),

                          _botaoServico(
                            context,
                            icone: Icons.trending_up_rounded,
                            titulo: 'Performance',
                            subtitulo:
                                'PDI, avaliações e período de experiência',
                            cor: const Color(0xFF6366F1),
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const PerformanceColabScreen()),
                            ),
                          ),
                          const SizedBox(height: 28),

                          // ── Solicitações ──────────────────────────────────
                          _sectionLabel('Solicitações', const Color(0xFF7C3AED)),
                          const SizedBox(height: 10),

                          _botaoServico(
                            context,
                            icone: Icons.assignment_outlined,
                            titulo: 'Solicitações',
                            subtitulo: 'Abra pedidos e acompanhe o andamento',
                            cor: const Color(0xFF7C3AED),
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SolicitacoesScreen()),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // ── Chamados de TI ────────────────────────────────
                          _sectionLabel('Suporte de TI', const Color(0xFFE64A19)),
                          const SizedBox(height: 10),

                          _botaoServico(
                            context,
                            icone: Icons.build_outlined,
                            titulo: 'Chamados de TI',
                            subtitulo: 'Abra e acompanhe chamados no Azure Boards',
                            cor: const Color(0xFFE64A19),
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ChamadosTiScreen()),
                            ),
                          ),

                          const SizedBox(height: 28),

                          if (!_loadingPerfis && _contrachequeAtivo) ...[
                            // ── Financeiro ───────────────────────────────
                            _sectionLabel('Financeiro', const Color(0xFF0F766E)),
                            const SizedBox(height: 10),

                            _botaoServico(
                              context,
                              icone: Icons.receipt_long_outlined,
                              titulo: 'Contracheque',
                              subtitulo: 'Consulte seus proventos e descontos',
                              cor: const Color(0xFF0F766E),
                              emBreve: false,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ContrachequeScreen(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                          ],

                          // ── Meu Cadastro ──────────────────────────────────
                          _sectionLabel('Meu Cadastro', const Color(0xFF0369A1)),
                          const SizedBox(height: 10),

                          _botaoServico(
                            context,
                            icone: Icons.folder_shared_outlined,
                            titulo: 'Atualização cadastral',
                            subtitulo: 'Envie seus documentos e de seus dependentes',
                            cor: const Color(0xFF0369A1),
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AtualizacaoCadastralScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          _botaoServico(
                            context,
                            icone: Icons.badge_outlined,
                            titulo: 'Crachá virtual',
                            subtitulo: 'Veja a frente e o verso do seu crachá',
                            cor: const Color(0xFF0369A1),
                            emBreve: false,
                            onTap: () {
                              final id = ApiService().colaboradorAtual?.id;
                              if (id != null) {
                                abrirCrachaVirtual(context, colaboradorId: id);
                              }
                            },
                          ),
                          const SizedBox(height: 28),

                          // ── Utilitários ───────────────────────────────────
                          _sectionLabel('Utilitários', AppColors.laranja),
                          const SizedBox(height: 10),

                          _botaoServico(
                            context,
                            icone: Icons.folder_outlined,
                            titulo: 'Documentos Institucionais',
                            subtitulo: 'Consulte documentos disponibilizados pela empresa',
                            cor: AppColors.laranja,
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DocumentosInstitucionaisScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          _botaoServico(
                            context,
                            icone: Icons.video_library_outlined,
                            titulo: 'Manual de Uso',
                            subtitulo: 'Vídeos e PDFs de como usar o app',
                            cor: AppColors.laranja,
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ManualUsoScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          _botaoServico(
                            context,
                            icone: Icons.bolt_outlined,
                            titulo: 'Acesso Rápido',
                            subtitulo: 'Links de serviços da empresa',
                            cor: AppColors.laranja,
                            emBreve: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AcessoRapidoScreen(),
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
                  '$titulo estará disponível em breve!',
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
