import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import 'pesquisa_resposta_screen.dart';

class PesquisaListScreen extends StatefulWidget {
  const PesquisaListScreen({super.key});

  @override
  State<PesquisaListScreen> createState() => _PesquisaListScreenState();
}

class _PesquisaListScreenState extends State<PesquisaListScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _futurePesquisas;

  @override
  void initState() {
    super.initState();
    _futurePesquisas = _api.buscarPesquisasDisponiveis();
  }

  void _recarregar() {
    setState(() {
      _futurePesquisas = _api.buscarPesquisasDisponiveis();
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
                            '📊 Pesquisas',
                            style: AppTextStyles.tituloGrande
                                .copyWith(color: Colors.white),
                          ),
                          Text(
                            'Sua opinião faz a diferença',
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
                      future: _futurePesquisas,
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
                                  Icons.poll_outlined,
                                  size: 56,
                                  color: AppColors.cinzaTexto,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Nenhuma pesquisa disponível',
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
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) =>
                                _cardPesquisa(lista[i]),
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

  Widget _cardPesquisa(Map<String, dynamic> p) {
    final titulo = p['titulo'] as String? ?? '';
    final descricao = p['descricao'] as String?;
    final jaRespondeu = p['ja_respondeu'] as bool? ?? false;
    final dataFim = p['data_fim'] as String?;
    final anonima = p['anonima'] as bool? ?? false;

    return GestureDetector(
      onTap: jaRespondeu
          ? null
          : () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PesquisaRespostaScreen(
                    pesquisaId: p['id'] as int,
                    titulo: titulo,
                    anonima: anonima,
                  ),
                ),
              );
              _recarregar();
            },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: jaRespondeu
              ? Border.all(color: Colors.green.withOpacity(0.3))
              : null,
          boxShadow: [
            BoxShadow(
              color: jaRespondeu
                  ? Colors.green.withOpacity(0.06)
                  : AppColors.magenta.withOpacity(0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: jaRespondeu
                        ? Colors.green.withOpacity(0.1)
                        : AppColors.magenta.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    jaRespondeu
                        ? Icons.check_circle_outline_rounded
                        : Icons.poll_outlined,
                    color: jaRespondeu ? Colors.green : AppColors.magenta,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: AppTextStyles.labelSecao.copyWith(fontSize: 15),
                      ),
                      if (dataFim != null)
                        Text(
                          'Até ${_formatarData(dataFim)}',
                          style: AppTextStyles.corpoCinza.copyWith(
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (jaRespondeu)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Respondida',
                      style: AppTextStyles.corpoMinimo.copyWith(
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.cinzaTexto,
                    size: 22,
                  ),
              ],
            ),
            if (descricao != null && descricao.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                descricao,
                style: AppTextStyles.corpoCinza,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (anonima) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 14,
                    color: AppColors.cinzaTexto,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Pesquisa anônima',
                    style: AppTextStyles.corpoMinimo
                        .copyWith(color: AppColors.cinzaTexto),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatarData(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, "0")}/${dt.month.toString().padLeft(2, "0")}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}

