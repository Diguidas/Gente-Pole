import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const _corContracheque = Color(0xFF0F766E);

const _mesesNome = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

/// Lista de contracheques do colaborador, agrupados por competência
/// (mês/ano) — mais recente primeiro. Se o colaborador teve mais de um
/// período no mesmo mês (ex: Folha Mensal + Férias, ou + 13º Salário), cada
/// um aparece como um card separado — nunca somados num contracheque só.
class ContrachequeScreen extends StatefulWidget {
  const ContrachequeScreen({super.key});

  @override
  State<ContrachequeScreen> createState() => _ContrachequeScreenState();
}

class _ContrachequeScreenState extends State<ContrachequeScreen> {
  final _api = ApiService();
  bool _carregando = true;
  List<({int mes, int ano, List<Map<String, dynamic>> periodos})> _competencias = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final competencias = await _api.listarCompetenciasContracheque();
      final comPeriodos = <({int mes, int ano, List<Map<String, dynamic>> periodos})>[];
      for (final c in competencias) {
        final mes = c['mes'] as int;
        final ano = c['ano'] as int;
        final periodos = await _api.listarPeriodosContracheque(mes: mes, ano: ano);
        if (periodos.isNotEmpty) {
          comPeriodos.add((mes: mes, ano: ano, periodos: periodos));
        }
      }
      if (!mounted) return;
      setState(() {
        _competencias = comPeriodos;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        backgroundColor: _corContracheque,
        foregroundColor: Colors.white,
        title: Text('Contracheque',
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        centerTitle: false,
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _competencias.isEmpty
              ? RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 12),
                      Text('Seu contracheque ainda não foi liberado pelo DP.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.cinzaTexto)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      for (final c in _competencias) ...[
                        Text('${_mesesNome[c.mes - 1]} de ${c.ano}',
                            style: GoogleFonts.poppins(
                                fontSize: 13, color: AppColors.cinzaTexto)),
                        const SizedBox(height: 12),
                        ...c.periodos.map((p) => _cardPeriodo(c.mes, c.ano, p)),
                        const SizedBox(height: 20),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _cardPeriodo(int mes, int ano, Map<String, dynamic> p) {
    final periodo = p['periodo'] as int;
    final nome = p['nome'] as String;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ContrachequeDetalheScreen(
              mes: mes,
              ano: ano,
              periodo: periodo,
              nomePeriodo: nome,
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _corContracheque.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long_outlined, size: 20, color: _corContracheque),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(nome,
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark)),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.cinzaTexto),
          ]),
        ),
      ),
    );
  }
}

/// Detalhe de UM período de contracheque (nunca mais de um junto).
class ContrachequeDetalheScreen extends StatefulWidget {
  final int mes;
  final int ano;
  final int periodo;
  final String nomePeriodo;

  const ContrachequeDetalheScreen({
    super.key,
    required this.mes,
    required this.ano,
    required this.periodo,
    required this.nomePeriodo,
  });

  @override
  State<ContrachequeDetalheScreen> createState() => _ContrachequeDetalheScreenState();
}

class _ContrachequeDetalheScreenState extends State<ContrachequeDetalheScreen> {
  final _api = ApiService();
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic>? _folha;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final folha = await _api.buscarContracheque(
        mes: widget.mes,
        ano: widget.ano,
        periodo: widget.periodo,
      );
      if (!mounted) return;
      setState(() {
        _folha = folha;
        _carregando = false;
        if (folha == null) _erro = 'Não foi possível carregar seu contracheque.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar: $e';
        _carregando = false;
      });
    }
  }

  String _moeda(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        backgroundColor: _corContracheque,
        foregroundColor: Colors.white,
        title: Text(widget.nomePeriodo,
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        centerTitle: false,
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_outlined,
                            size: 48, color: Color(0xFFCBD5E1)),
                        const SizedBox(height: 12),
                        Text(_erro!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 14, color: AppColors.cinzaTexto)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _carregar,
                          style: ElevatedButton.styleFrom(backgroundColor: _corContracheque),
                          child: Text('Tentar novamente',
                              style: GoogleFonts.poppins(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildFolha(),
    );
  }

  Widget _buildFolha() {
    final folha = _folha!;
    final eventos = (folha['eventos'] as List).cast<Map<String, dynamic>>();
    final proventos = eventos.where((e) => e['tipo'] == 'Provento').toList();
    final descontos = eventos.where((e) => e['tipo'] == 'Desconto').toList();
    final totalProventos = (folha['totalProventos'] as num).toDouble();
    final totalDescontos = (folha['totalDescontos'] as num).toDouble();
    final liquido = (folha['liquido'] as num).toDouble();

    if (eventos.isEmpty) {
      return Center(
        child: Text('Nenhum evento encontrado pra esse período.',
            style: GoogleFonts.poppins(fontSize: 14, color: AppColors.cinzaTexto)),
      );
    }

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_corContracheque, Color(0xFF115E59)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_mesNome(widget.mes)} de ${widget.ano} · ${widget.nomePeriodo}',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.white.withOpacity(0.8))),
                const SizedBox(height: 6),
                Text('Líquido a receber',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.white.withOpacity(0.8))),
                Text(_moeda(liquido),
                    style: GoogleFonts.poppins(
                        fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: _cardResumo('Proventos', totalProventos, AppColors.sucesso),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _cardResumo('Descontos', totalDescontos, AppColors.erro),
            ),
          ]),
          const SizedBox(height: 24),
          if (proventos.isNotEmpty) ...[
            Text('Proventos',
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark)),
            const SizedBox(height: 8),
            ...proventos.map((e) => _linhaEvento(e, AppColors.sucesso)),
            const SizedBox(height: 20),
          ],
          if (descontos.isNotEmpty) ...[
            Text('Descontos',
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark)),
            const SizedBox(height: 8),
            ...descontos.map((e) => _linhaEvento(e, AppColors.erro)),
          ],
        ],
      ),
    );
  }

  String _mesNome(int mes) => const [
        'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
        'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
      ][mes - 1];

  Widget _cardResumo(String titulo, double valor, Color cor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto)),
          const SizedBox(height: 4),
          Text(_moeda(valor),
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w700, color: cor)),
        ],
      ),
    );
  }

  Widget _linhaEvento(Map<String, dynamic> e, Color cor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Expanded(
          child: Text(e['descricao'] as String? ?? '',
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.dark)),
        ),
        Text(_moeda((e['valor'] as num)),
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: cor)),
      ]),
    );
  }
}
