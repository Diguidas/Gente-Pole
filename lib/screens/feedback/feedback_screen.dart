import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import 'enviar_feedback_screen.dart';
import 'feedbacks_recebidos_screen.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _api = ApiService();
  int _naoLidos = 0;

  @override
  void initState() {
    super.initState();
    _carregarBadge();
  }

  Future<void> _carregarBadge() async {
    final n = await _api.contarFeedbacksNaoLidos();
    if (mounted) setState(() => _naoLidos = n);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 200,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💬 Feedback',
                            style: AppTextStyles.tituloGrande
                                .copyWith(color: Colors.white),
                          ),
                          Text(
                            'Reconheça e seja reconhecido',
                            style: AppTextStyles.corpoBranco
                                .copyWith(color: AppColors.brancoOp80),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Corpo
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            'O que você quer fazer?',
                            style: AppTextStyles.corpoMenor
                                .copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 16),

                          // Card — Enviar
                          _cardOpcao(
                            icone: Icons.send_outlined,
                            titulo: 'Enviar Feedback',
                            subtitulo: 'Reconheça ou oriente um colega',
                            cor: AppColors.laranja,
                            badge: 0,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const EnviarFeedbackScreen(),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 14),

                          // Card — Recebidos
                          _cardOpcao(
                            icone: Icons.inbox_outlined,
                            titulo: 'Feedbacks Recebidos',
                            subtitulo: 'Veja o que seus colegas disseram',
                            cor: AppColors.magenta,
                            badge: _naoLidos,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const FeedbacksRecebidosScreen(),
                                ),
                              );
                              // Recarrega badge ao voltar
                              _carregarBadge();
                            },
                          ),
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

  Widget _cardOpcao({
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required Color cor,
    required int badge,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
                      Text(
                        titulo,
                        style: AppTextStyles.labelSecao
                            .copyWith(fontSize: 16),
                      ),
                      if (badge > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$badge',
                            style: AppTextStyles.corpoMinimo.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
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