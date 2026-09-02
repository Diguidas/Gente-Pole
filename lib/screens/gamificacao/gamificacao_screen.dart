import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

/// Nome da moeda do programa de pontos — trocar aqui muda em toda a tela.
const nomeMoeda = 'Polecoin';

class GamificacaoScreen extends StatefulWidget {
  const GamificacaoScreen({super.key});

  @override
  State<GamificacaoScreen> createState() => _GamificacaoScreenState();
}

class _GamificacaoScreenState extends State<GamificacaoScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _acoes = [];
  List<Map<String, dynamic>> _ranking = [];
  Map<String, dynamic>? _meta;
  int _meusPontos = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final acoes = await _api.listarPontosConfig();
      final ranking = await _api.buscarRankingPontosDaMinhaFilial();
      final meta = await _api.buscarMetaPontos();
      final pontos = await _api.buscarMeusPontos();
      if (mounted) {
        setState(() {
          _acoes = acoes;
          _ranking = ranking;
          _meta = meta;
          _meusPontos = pontos;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metaPontos = _meta?['meta_pontos'] as int? ?? 0;
    final recompensa = _meta?['descricao_recompensa'] as String? ?? 'recompensa';
    final progresso =
        metaPontos > 0 ? (_meusPontos / metaPontos).clamp(0.0, 1.0) : 0.0;
    final faltam = (metaPontos - _meusPontos).clamp(0, metaPontos);

    return Scaffold(
      backgroundColor: AppColors.fundo,
      body: Stack(
        children: [
          Container(
            height: 200,
            decoration: const BoxDecoration(gradient: AppColors.gradientePrincipal),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 24, 0),
                  child: Row(children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white, size: 18),
                    ),
                    Text('Meus $nomeMoeda',
                        style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ]),
                ),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white))
                      : RefreshIndicator(
                          onRefresh: _carregar,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            children: [
                              _CardSaldo(
                                pontos: _meusPontos,
                                metaPontos: metaPontos,
                                faltam: faltam,
                                progresso: progresso,
                                recompensa: recompensa,
                              ),
                              const SizedBox(height: 24),
                              Text('Como ganhar $nomeMoeda',
                                  style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.dark)),
                              const SizedBox(height: 10),
                              ..._acoes.map((a) => _AcaoTile(acao: a)),
                              const SizedBox(height: 24),
                              Text('Ranking da minha filial',
                                  style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.dark)),
                              const SizedBox(height: 4),
                              Text(
                                  'Você só vê o ranking de quem é da sua filial.',
                                  style: GoogleFonts.poppins(
                                      fontSize: 12, color: AppColors.cinzaTexto)),
                              const SizedBox(height: 10),
                              if (_ranking.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24),
                                  child: Center(
                                    child: Text('Ninguém pontuou ainda por aqui.',
                                        style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: AppColors.cinzaTexto)),
                                  ),
                                )
                              else
                                ..._ranking.asMap().entries.map((e) => _RankingTile(
                                      posicao: e.key + 1,
                                      nome: e.value['nome'] as String? ?? '',
                                      pontos: e.value['total_pontos'] as int? ?? 0,
                                      souEu: e.value['colaborador_id'] ==
                                          _api.colaboradorAtual?.id,
                                    )),
                            ],
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
}

class _CardSaldo extends StatelessWidget {
  final int pontos;
  final int metaPontos;
  final int faltam;
  final double progresso;
  final String recompensa;
  const _CardSaldo({
    required this.pontos,
    required this.metaPontos,
    required this.faltam,
    required this.progresso,
    required this.recompensa,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: AppColors.pretoOp08, blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.laranjaOp10,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emoji_events_rounded,
                  color: AppColors.laranja, size: 22),
            ),
            const SizedBox(width: 12),
            Text('$pontos',
                style: GoogleFonts.poppins(
                    fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.dark)),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(nomeMoeda,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: AppColors.cinzaTexto)),
            ),
          ]),
          if (metaPontos > 0) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progresso,
                minHeight: 10,
                backgroundColor: AppColors.cinzaClaro,
                valueColor: const AlwaysStoppedAnimation(AppColors.magenta),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              faltam > 0
                  ? 'Faltam $faltam $nomeMoeda para o RH te chamar pro $recompensa 🎉'
                  : 'Você bateu a meta! O RH vai entrar em contato sobre o $recompensa 🎉',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto),
            ),
          ],
        ],
      ),
    );
  }
}

class _AcaoTile extends StatelessWidget {
  final Map<String, dynamic> acao;
  const _AcaoTile({required this.acao});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Expanded(
          child: Text(acao['rotulo'] as String? ?? '',
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.dark)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.magentaOp15,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('+${acao['pontos']}',
              style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.magenta)),
        ),
      ]),
    );
  }
}

class _RankingTile extends StatelessWidget {
  final int posicao;
  final String nome;
  final int pontos;
  final bool souEu;
  const _RankingTile({
    required this.posicao,
    required this.nome,
    required this.pontos,
    required this.souEu,
  });

  @override
  Widget build(BuildContext context) {
    final medalha = switch (posicao) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: souEu ? AppColors.laranjaOp08 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: souEu ? Border.all(color: AppColors.laranja, width: 1.2) : null,
      ),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: medalha != null
              ? Text(medalha, style: const TextStyle(fontSize: 18))
              : Text('$posicao',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.cinzaTexto)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(souEu ? '$nome (você)' : nome,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: souEu ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.dark),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        Text('$pontos pts',
            style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.magenta)),
      ]),
    );
  }
}
