import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

class FeedbacksRecebidosScreen extends StatefulWidget {
  const FeedbacksRecebidosScreen({super.key});

  @override
  State<FeedbacksRecebidosScreen> createState() =>
      _FeedbacksRecebidosScreenState();
}

class _FeedbacksRecebidosScreenState
    extends State<FeedbacksRecebidosScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _futureFeedbacks;

  @override
  void initState() {
    super.initState();
    _futureFeedbacks = _api.buscarFeedbacksRecebidos();
  }

  void _recarregar() {
    if (!mounted) return;
    setState(() {
      _futureFeedbacks = _api.buscarFeedbacksRecebidos();
    });
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
                            '📥 Feedbacks Recebidos',
                            style: AppTextStyles.tituloGrande
                                .copyWith(color: Colors.white),
                          ),
                          Text(
                            'O que seus colegas disseram',
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
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _futureFeedbacks,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.magenta,
                            ),
                          );
                        }

                        final lista = snap.data ?? [];

                        if (lista.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.inbox_outlined,
                                  size: 56,
                                  color: AppColors.cinzaTexto,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Nenhum feedback recebido ainda',
                                  style: AppTextStyles.corpoCinza
                                      .copyWith(fontSize: 15),
                                ),
                              ],
                            ),
                          );
                        }

                        return RefreshIndicator(
                          color: AppColors.magenta,
                          onRefresh: () async => _recarregar(),
                          child: ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(16, 20, 16, 32),
                            itemCount: lista.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) =>
                                _cardFeedback(lista[i]),
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

  Widget _cardFeedback(Map<String, dynamic> fb) {
    final lido = fb['lido'] as bool? ?? false;
    final anonimo = fb['anonimo'] as bool? ?? false;
    final remetenteNome = fb['remetente_nome'] as String?;
    final remetenteSetor = fb['remetente_setor'] as String?;
    final texto = fb['texto'] as String? ?? '';
    final criadoEm = fb['criado_em'] as String? ?? '';

    final nomeExibido = anonimo ? 'Anônimo' : (remetenteNome ?? 'Colega');
    final setorExibido = anonimo ? null : remetenteSetor;

    return GestureDetector(
      onTap: () => _abrirDetalhe(fb),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: lido
              ? null
              : Border.all(color: AppColors.magenta.withOpacity(0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: lido
                  ? Colors.black.withOpacity(0.04)
                  : AppColors.magenta.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: anonimo
                      ? Colors.grey.withOpacity(0.15)
                      : AppColors.magenta.withOpacity(0.12),
                  child: Icon(
                    anonimo ? Icons.person_outline : Icons.person_rounded,
                    size: 20,
                    color: anonimo ? AppColors.cinzaTexto : AppColors.magenta,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nomeExibido,
                        style: AppTextStyles.labelSecao.copyWith(fontSize: 14),
                      ),
                      if (setorExibido != null)
                        Text(setorExibido, style: AppTextStyles.corpoCinza),
                    ],
                  ),
                ),
                if (!lido)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.magenta,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Novo',
                      style: AppTextStyles.corpoMinimo.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Text(_dataRelativa(criadoEm), style: AppTextStyles.corpoCinza),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              texto,
              style: AppTextStyles.corpoNormal,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _abrirDetalhe(Map<String, dynamic> fb) async {
    final fbId = fb['id'] as int?;
    final lido = fb['lido'] as bool? ?? true;

    // Marca como lido
    if (fbId != null && !lido) {
      await _api.marcarFeedbackLido(fbId);
      _recarregar();
    }

    if (!mounted) return;

    final anonimo = fb['anonimo'] as bool? ?? false;
    final remetenteNome = fb['remetente_nome'] as String?;
    final remetenteSetor = fb['remetente_setor'] as String?;
    final texto = fb['texto'] as String? ?? '';
    final criadoEm = fb['criado_em'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: anonimo
                      ? Colors.grey.withOpacity(0.15)
                      : AppColors.magenta.withOpacity(0.12),
                  child: Icon(
                    anonimo ? Icons.person_outline : Icons.person_rounded,
                    color: anonimo ? AppColors.cinzaTexto : AppColors.magenta,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anonimo ? 'Anônimo' : (remetenteNome ?? 'Colega'),
                      style: AppTextStyles.labelSecao,
                    ),
                    Text(
                      anonimo
                          ? _dataRelativa(criadoEm)
                          : [remetenteSetor, _dataRelativa(criadoEm)]
                              .where((e) => e != null && e.isNotEmpty)
                              .join(' · '),
                      style: AppTextStyles.corpoCinza,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FC),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(texto, style: AppTextStyles.corpoNormal),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _dataRelativa(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return 'Há ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Há ${diff.inHours}h';
      if (diff.inDays == 1) return 'Ontem';
      if (diff.inDays < 7) return 'Há ${diff.inDays} dias';
      return '${dt.day.toString().padLeft(2, "0")}/${dt.month.toString().padLeft(2, "0")}';
    } catch (_) {
      return '';
    }
  }
}


