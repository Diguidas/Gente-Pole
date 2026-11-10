import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const _corCardapio = Color(0xFFF59E0B);
const _laranja = Color(0xFFFF5000);
const _carmim = Color(0xFFE6004C);
const _cinzaEscuro = Color(0xFF3A3A3A);

const _nomesDias = ['SEGUNDA', 'TERÇA', 'QUARTA', 'QUINTA', 'SEXTA', 'SÁBADO'];
const _meses = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho',
  'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
];

/// Segunda-feira da semana de [d] (domingo conta como início da próxima).
DateTime _segundaDaSemana(DateTime d) {
  final dia = DateTime(d.year, d.month, d.day);
  if (dia.weekday == DateTime.sunday) return dia.add(const Duration(days: 1));
  return dia.subtract(Duration(days: dia.weekday - 1));
}

/// Texto do cardápio com formatação leve: **negrito** e *itálico*.
class _CardapioTexto extends StatelessWidget {
  final String texto;
  const _CardapioTexto(this.texto);

  static final _padrao = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*', dotAll: true);

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.poppins(
        fontSize: 15, color: _cinzaEscuro, height: 1.5);
    final out = <InlineSpan>[];
    var pos = 0;
    for (final m in _padrao.allMatches(texto)) {
      if (m.start > pos) {
        out.add(TextSpan(text: texto.substring(pos, m.start), style: base));
      }
      if (m.group(1) != null) {
        out.add(TextSpan(
            text: m.group(1),
            style: base.copyWith(fontWeight: FontWeight.w700)));
      } else {
        out.add(TextSpan(
            text: m.group(2),
            style: base.copyWith(fontStyle: FontStyle.italic)));
      }
      pos = m.end;
    }
    if (pos < texto.length) {
      out.add(TextSpan(text: texto.substring(pos), style: base));
    }
    return Text.rich(TextSpan(children: out));
  }
}

class CardapioScreen extends StatefulWidget {
  const CardapioScreen({super.key});

  @override
  State<CardapioScreen> createState() => _CardapioScreenState();
}

class _CardapioScreenState extends State<CardapioScreen> {
  final _api = ApiService();
  bool _loading = true;
  late DateTime _segunda;
  Map<String, String> _textos = {};

  @override
  void initState() {
    super.initState();
    _segunda = _segundaDaSemana(DateTime.now());
    _carregar();
  }

  DateTime _dia(int i) => _segunda.add(Duration(days: i));

  String _chave(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dd(DateTime d) => d.day.toString().padLeft(2, '0');

  String _periodo() {
    final a = _dia(0), b = _dia(5);
    return a.month == b.month
        ? 'de ${_dd(a)} a ${_dd(b)} de ${_meses[b.month - 1]}'
        : 'de ${_dd(a)} de ${_meses[a.month - 1]} a ${_dd(b)} de ${_meses[b.month - 1]}';
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      _segunda = _segundaDaSemana(DateTime.now());
      final r = await _api.buscarCardapioDias(_dia(0), _dia(5));
      if (!mounted) return;
      setState(() {
        _textos = r;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _abrirDia(int i) {
    final d = _dia(i);
    final texto = _textos[_chave(d)] ?? '';
    final titulo =
        '${_nomesDias[i][0]}${_nomesDias[i].substring(1).toLowerCase()} '
        '${_dd(d)}/${d.month.toString().padLeft(2, '0')}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.restaurant_menu_outlined, color: _laranja),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Cardápio · $titulo',
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _cinzaEscuro)),
          ),
        ]),
        content: SingleChildScrollView(
          child: texto.trim().isEmpty
              ? Text('O cardápio deste dia ainda não foi cadastrado.',
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: AppColors.cinzaTexto))
              : _CardapioTexto(texto),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  Text('Fechar', style: GoogleFonts.poppins(color: _laranja))),
        ],
      ),
    );
  }

  Widget _botao(int i) {
    final hoje = DateTime.now();
    final d = _dia(i);
    final ehHoje =
        d.year == hoje.year && d.month == hoje.month && d.day == hoje.day;
    return Material(
      color: i.isEven ? _laranja : _carmim,
      shape: StadiumBorder(
        side: ehHoje
            ? const BorderSide(color: Colors.white, width: 3)
            : BorderSide.none,
      ),
      elevation: ehHoje ? 4 : 0,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => _abrirDia(i),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_nomesDias[i],
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              Text('${_dd(d)}/${d.month.toString().padLeft(2, '0')}',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _conteudo() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFEA),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Topo da arte (logo do cardápio); o resto da arte é só fundo.
          AspectRatio(
            aspectRatio: 16 / 9 / 0.42,
            child: Image.asset('assets/cardapio_fundo.webp',
                fit: BoxFit.cover, alignment: Alignment.topCenter),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(children: [
              Text(_periodo(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _laranja)),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  style: GoogleFonts.poppins(fontSize: 13, color: _cinzaEscuro),
                  children: [
                    const TextSpan(text: 'Para acessar '),
                    TextSpan(
                        text: 'clique no botão',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _laranja)),
                    const TextSpan(text: ' para '),
                    TextSpan(
                        text: 'visualizar o cardápio',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _carmim)),
                    const TextSpan(text: ' do dia.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.6,
                children: [for (var i = 0; i < 6; i++) _botao(i)],
              ),
              const SizedBox(height: 16),
              Text.rich(
                TextSpan(
                  style: GoogleFonts.poppins(fontSize: 12, color: _cinzaEscuro),
                  children: [
                    const TextSpan(text: '* Sujeito a alteração por parte do '),
                    TextSpan(
                        text: 'Setor de Nutrição',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _laranja)),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Container(
                height: 180,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_corCardapio, Color(0xFFE86A00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
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
                        color: Colors.black.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.restaurant_menu_outlined, color: Colors.white, size: 32),
                    const SizedBox(height: 8),
                    Text('Cardápio do Refeitório',
                        style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text('Confira o cardápio do refeitório',
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.white.withOpacity(0.85))),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _corCardapio))
                  : RefreshIndicator(
                      color: _corCardapio,
                      onRefresh: _carregar,
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [_conteudo()],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
