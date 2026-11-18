import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';
import '../core/nome_foto.dart';
import '../services/api_service.dart';
import 'avatar_colaborador.dart';

const _icones = [
  Icons.sentiment_very_dissatisfied_rounded,
  Icons.sentiment_dissatisfied_rounded,
  Icons.sentiment_neutral_rounded,
  Icons.sentiment_satisfied_rounded,
  Icons.sentiment_very_satisfied_rounded,
];
const _labels = ['Péssimo', 'Ruim', 'Ok', 'Bem', 'Ótimo(a)'];
const _cores = [
  Color(0xFFE53935),
  Color(0xFFFB8C00),
  Color(0xFFFBC02D),
  Color(0xFF7CB342),
  Color(0xFF43A047),
];

/// "Termômetro da empresa": quantos colaboradores estão em cada um dos 5
/// humores hoje, um embaixo do outro (mesmo card do web). Todos veem as
/// quantidades; só quem é admin/endomkt toca num humor e vê quem está nele e
/// se escreveu mensagem (privacidade dos colegas) — mesma regra do web.
class HumorPainelCard extends StatefulWidget {
  const HumorPainelCard({super.key});

  @override
  State<HumorPainelCard> createState() => _HumorPainelCardState();
}

class _HumorPainelCardState extends State<HumorPainelCard> {
  final _api = ApiService();
  List<int> _niveis = [];
  bool _carregando = true;
  bool _podeVerDetalhes = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await Future.wait([
        _api.buscarNiveisHumorDoDia(),
        _api.podeVerDetalhesHumor(),
      ]);
      if (!mounted) return;
      setState(() {
        _niveis = r[0] as List<int>;
        _podeVerDetalhes = r[1] as bool;
        _carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  int _qtd(int nivel) => _niveis.where((n) => n == nivel).length;

  void _abrirDetalhes(int nivel) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _HumorDetalhes(nivel: nivel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _niveis.length;
    final maior = [for (var n = 1; n <= 5; n++) _qtd(n)]
        .fold<int>(0, (a, b) => a > b ? a : b);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Termômetro de humor diário',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark)),
            ),
            if (!_carregando)
              Text('$total ${total == 1 ? 'registro' : 'registros'}',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppColors.cinzaTexto)),
          ]),
          Text('Acompanhe como nossos colaboradores estão se sentindo hoje.',
              style: GoogleFonts.poppins(
                  fontSize: 11.5, color: AppColors.cinzaTexto)),
          const SizedBox(height: 8),
          if (_carregando)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.laranja))),
            )
          else
            Column(children: [
              for (var nivel = 5; nivel >= 1; nivel--)
                _linha(nivel, _qtd(nivel), maior),
            ]),
        ],
      ),
    );
  }

  Widget _linha(int nivel, int qtd, int maior) {
    final i = nivel - 1;
    // De "Ok" para baixo só admin/RH/endomkt abrem quem registrou.
    final abre = qtd > 0 && (nivel >= 4 || _podeVerDetalhes);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: abre ? () => _abrirDetalhes(nivel) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(children: [
          Icon(_icones[i], size: 22, color: _cores[i]),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(_labels[i],
                  maxLines: 1,
                  softWrap: false,
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: maior == 0 ? 0 : qtd / maior,
                minHeight: 8,
                backgroundColor: const Color(0xFFF1F5F9),
                valueColor: AlwaysStoppedAnimation(_cores[i]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 30,
            child: Text('$qtd',
                textAlign: TextAlign.right,
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 18,
              color: abre ? AppColors.cinzaTexto : Colors.transparent),
        ]),
      ),
    );
  }
}

/// Quem está nesse humor hoje e se escreveu mensagem.
class _HumorDetalhes extends StatefulWidget {
  final int nivel;
  const _HumorDetalhes({required this.nivel});

  @override
  State<_HumorDetalhes> createState() => _HumorDetalhesState();
}

class _HumorDetalhesState extends State<_HumorDetalhes> {
  final _api = ApiService();
  late final Future<List<Map<String, dynamic>>> _futuro =
      _api.buscarHumoresDoDiaDetalhado(widget.nivel);
  bool _soComMensagem = false;
  double _arraste = 0;

  /// Puxar a lista para baixo estando no topo fecha o modal. A lista rola e
  /// "engole" o gesto, então o fechar-ao-arrastar padrão do sheet não chega.
  /// Android emite OverscrollNotification; iOS (bounce) deixa o scroll negativo.
  bool _aoRolar(ScrollNotification n) {
    var fechar = false;
    if (n is OverscrollNotification && n.overscroll < 0 && n.dragDetails != null) {
      _arraste += -n.overscroll;
      fechar = _arraste > 90;
    } else if (n is ScrollUpdateNotification &&
        n.dragDetails != null &&
        n.metrics.pixels < -90) {
      fechar = true;
    } else if (n is ScrollEndNotification) {
      _arraste = 0;
    }
    if (fechar) {
      _arraste = 0;
      Navigator.of(context).maybePop();
    }
    return false;
  }

  String _hora(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  bool _temMensagem(Map<String, dynamic> r) =>
      '${r['motivo'] ?? ''}'.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final i = widget.nivel - 1;
    // Altura fixa (sem DraggableScrollableSheet): o sheet sobe uma vez só,
    // sem a sensação de "dois modais" abrindo em sequência.
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futuro,
        builder: (context, snap) {
          final carregando = snap.connectionState != ConnectionState.done;
          final todos = snap.data ?? const <Map<String, dynamic>>[];
          final comMensagem = todos.where(_temMensagem).length;
          final lista =
              todos.where((r) => !_soComMensagem || _temMensagem(r)).toList();
          return NotificationListener<ScrollNotification>(
            onNotification: _aoRolar,
            child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Icon(_icones[i], size: 30, color: _cores[i]),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Humor: ${_labels[i]}',
                            style: GoogleFonts.poppins(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                        if (!carregando)
                          Text(
                              '${todos.length} ${todos.length == 1 ? 'colaborador' : 'colaboradores'} · $comMensagem com mensagem',
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: AppColors.cinzaTexto)),
                      ]),
                ),
              ]),
              if (comMensagem > 0) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    label: Text('Só com mensagem',
                        style: GoogleFonts.poppins(fontSize: 12)),
                    selected: _soComMensagem,
                    onSelected: (v) => setState(() => _soComMensagem = v),
                  ),
                ),
              ],
              const Divider(height: 24),
              if (carregando)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                      child: CircularProgressIndicator(color: AppColors.laranja)),
                )
              else if (snap.hasError)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Não foi possível carregar agora.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(color: AppColors.cinzaTexto)),
                )
              else if (lista.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Ninguém com mensagem neste humor.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(color: AppColors.cinzaTexto)),
                )
              else
                for (final r in lista) _pessoa(r),
            ],
          ));
        },
      ),
    );
  }

  Widget _pessoa(Map<String, dynamic> r) {
    final c = r['colaborador'] as Map<String, dynamic>?;
    final nome = c?['nome'] as String? ?? 'Colaborador';
    final setor = (c?['setor'] as String? ?? '').trim();
    final motivo = '${r['motivo'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          FotoClicavel(
            url: c?['foto_url'] as String?,
            nome: nome,
            child: AvatarColaborador(
                fotoUrl: c?['foto_url'] as String?, nome: nome, raio: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nome,
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              if (setor.isNotEmpty && setor != '—')
                Text(setor,
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.cinzaTexto)),
            ]),
          ),
          Text(_hora(r['criado_em'] as String?),
              style: GoogleFonts.poppins(
                  fontSize: 11, color: AppColors.cinzaTexto)),
        ]),
        if (motivo.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(motivo, style: GoogleFonts.poppins(fontSize: 12.5, height: 1.4)),
        ],
      ]),
    );
  }
}
