import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import 'ponto_pdf_service.dart';

const _corPonto = Color(0xFF0EA5E9);

int? _paraMinutos(String? hhmm) {
  if (hhmm == null || hhmm.isEmpty) return null;
  final partes = hhmm.split(':');
  if (partes.length < 2) return null;
  final h = int.tryParse(partes[0]);
  final m = int.tryParse(partes[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

String _formatarHora(String? hhmm) {
  if (hhmm == null || hhmm.isEmpty) return '--:--';
  final partes = hhmm.split(':');
  return '${partes[0].padLeft(2, '0')}:${partes[1].padLeft(2, '0')}';
}

String _formatarSaldo(int minutos) {
  final sinal = minutos < 0 ? '-' : '+';
  final abs = minutos.abs();
  final h = abs ~/ 60;
  final m = abs % 60;
  return '$sinal$h:${m.toString().padLeft(2, '0')}';
}

class PontoScreen extends StatefulWidget {
  const PontoScreen({super.key});

  @override
  State<PontoScreen> createState() => _PontoScreenState();
}

class _PontoScreenState extends State<PontoScreen> {
  final _api = ApiService();
  bool _loading = true;
  Map<String, dynamic> _config = {};
  List<Map<String, dynamic>> _registros = [];
  List<Map<String, dynamic>> _horasExtras = [];
  late DateTime _mesSelecionado;
  bool _temMesAnterior = false;
  bool _exportandoPdf = false;

  String _fmtData(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime get _hojeBrasilia {
    final agora = ApiService.horarioBrasilia();
    return DateTime(agora.year, agora.month, agora.day);
  }

  bool get _vendoMesAtual =>
      _mesSelecionado.year == _hojeBrasilia.year && _mesSelecionado.month == _hojeBrasilia.month;

  String? get _colaboradorId => _api.colaboradorAtual?.id.toString();

  @override
  void initState() {
    super.initState();
    final hoje = ApiService.horarioBrasilia();
    _mesSelecionado = DateTime(hoje.year, hoje.month);
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final id = _colaboradorId;
    if (id == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final resultados = await Future.wait([
      _api.buscarConfigPonto(id),
      _api.buscarRegistrosPontoMes(
          colaboradorId: id, ano: _mesSelecionado.year, mes: _mesSelecionado.month),
      _api.existeRegistroPontoAnterior(
          colaboradorId: id, antesDe: DateTime(_mesSelecionado.year, _mesSelecionado.month, 1)),
      _api.buscarHorasExtrasMes(
          colaboradorId: id, ano: _mesSelecionado.year, mes: _mesSelecionado.month),
    ]);
    if (!mounted) return;
    setState(() {
      _config = resultados[0] as Map<String, dynamic>;
      _registros = resultados[1] as List<Map<String, dynamic>>;
      _temMesAnterior = resultados[2] as bool;
      _horasExtras = resultados[3] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  Future<void> _recarregarRegistros() async {
    final id = _colaboradorId;
    if (id == null) return;
    final registros = await _api.buscarRegistrosPontoMes(
        colaboradorId: id, ano: _mesSelecionado.year, mes: _mesSelecionado.month);
    if (!mounted) return;
    setState(() => _registros = registros);
  }

  Future<void> _recarregarHorasExtras() async {
    final id = _colaboradorId;
    if (id == null) return;
    final horas = await _api.buscarHorasExtrasMes(
        colaboradorId: id, ano: _mesSelecionado.year, mes: _mesSelecionado.month);
    if (!mounted) return;
    setState(() => _horasExtras = horas);
  }

  int get _totalHorasExtrasMin => _horasExtras.fold(0, (soma, h) => soma + (h['minutos'] as int));

  Map<String, dynamic>? get _registroHoje {
    final hojeStr = _fmtData(_hojeBrasilia);
    final achados = _registros.where((r) => r['data'] == hojeStr);
    return achados.isEmpty ? null : achados.first;
  }

  int get _horasEsperadasMin {
    final entrada = _paraMinutos(_config['entrada_padrao'] as String?) ?? 0;
    final saida = _paraMinutos(_config['saida_padrao'] as String?) ?? 0;
    final almoco = _config['almoco_minutos'] as int? ?? 60;
    return (saida - entrada - almoco).clamp(0, 24 * 60);
  }

  int? _horasTrabalhadasMin(Map<String, dynamic> registro) {
    final entrada = _paraMinutos(registro['entrada'] as String?);
    final saida = _paraMinutos(registro['saida'] as String?);
    if (entrada == null || saida == null) return null;
    final almoco = _config['almoco_minutos'] as int? ?? 60;
    return (saida - entrada - almoco).clamp(0, 24 * 60);
  }

  int get _saldoMesMin {
    var total = 0;
    for (final r in _registros) {
      final trabalhado = _horasTrabalhadasMin(r);
      if (trabalhado != null) total += trabalhado - _horasEsperadasMin;
    }
    return total;
  }

  void _mesAnterior() {
    if (!_temMesAnterior) return;
    setState(() => _mesSelecionado = DateTime(_mesSelecionado.year, _mesSelecionado.month - 1));
    _carregar();
  }

  void _proximoMes() {
    if (_vendoMesAtual) return;
    setState(() => _mesSelecionado = DateTime(_mesSelecionado.year, _mesSelecionado.month + 1));
    _carregar();
  }

  Future<void> _exportarPdf() async {
    setState(() => _exportandoPdf = true);
    try {
      await PontoPdfService.gerar(
        nomeColaborador: _api.colaboradorAtual?.nome ?? '',
        mesAno: '${_meses[_mesSelecionado.month]} ${_mesSelecionado.year}',
        registros: _registros,
        horasExtras: _horasExtras,
        saldoMesMin: _saldoMesMin,
        horasTrabalhadasMin: _horasTrabalhadasMin,
        horasEsperadasMin: _horasEsperadasMin,
      );
    } finally {
      if (mounted) setState(() => _exportandoPdf = false);
    }
  }

  Future<void> _abrirConfig() async {
    final salvou = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogConfigPonto(config: _config, colaboradorId: _colaboradorId!, api: _api),
    );
    if (salvou == true) _carregar();
  }

  Future<void> _baterPonto({required bool entrada}) async {
    final agora = ApiService.horarioBrasilia();
    final horario = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: agora.hour, minute: agora.minute),
    );
    if (horario == null || !mounted) return;

    final horaStr =
        '${horario.hour.toString().padLeft(2, '0')}:${horario.minute.toString().padLeft(2, '0')}';
    final dataStr = _fmtData(_hojeBrasilia);
    final ok = await _api.salvarRegistroPonto(
      colaboradorId: _colaboradorId!,
      data: dataStr,
      entrada: entrada ? horaStr : null,
      saida: entrada ? null : horaStr,
    );
    if (!mounted) return;
    if (ok) {
      _recarregarRegistros();
      _snack(entrada ? 'Entrada registrada!' : 'Saída registrada!');
    } else {
      _snack('Erro ao registrar. Tente novamente.', erro: true);
    }
  }

  Future<void> _abrirDialogHoraExtra() async {
    final id = _colaboradorId;
    if (id == null) return;
    final salvou = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogHoraExtra(colaboradorId: id, api: _api),
    );
    if (salvou == true) _recarregarHorasExtras();
  }

  Future<void> _confirmarExcluirHoraExtra(Map<String, dynamic> h) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: Text('Remover ${_formatarSaldo(h['minutos'] as int).replaceFirst('+', '')} de hora extra?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmar != true) return;
    final ok = await _api.excluirHoraExtra(h['id'] as int);
    if (ok) _recarregarHorasExtras();
  }

  void _snack(String msg, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: erro ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  static const _meses = [
    '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Container(
                height: 160,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_corPonto, Color(0xFF0369A1)],
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
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: Row(children: [
                    IconButton(
                      onPressed: _loading || _exportandoPdf ? null : _exportarPdf,
                      icon: _exportandoPdf
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
                      tooltip: 'Exportar PDF do mês',
                    ),
                    IconButton(
                      onPressed: _loading ? null : _abrirConfig,
                      icon: const Icon(Icons.settings_outlined, color: Colors.white),
                      tooltip: 'Configurar jornada',
                    ),
                  ]),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.access_time_rounded, color: Colors.white, size: 32),
                    const SizedBox(height: 8),
                    Text('Calculadora de Ponto',
                        style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text('Acompanhe suas horas e seu saldo',
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
                  ? const Center(child: CircularProgressIndicator(color: _corPonto))
                  : RefreshIndicator(
                      color: _corPonto,
                      onRefresh: _carregar,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_vendoMesAtual) ...[
                              _cardHoje(),
                              const SizedBox(height: 20),
                            ],
                            _cardSaldoMes(),
                            const SizedBox(height: 16),
                            _listaRegistros(),
                            const SizedBox(height: 20),
                            _cardHorasExtras(),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardHoje() {
    final registro = _registroHoje;
    final entrada = registro?['entrada'] as String?;
    final saida = registro?['saida'] as String?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hoje', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Entrada', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto)),
                Text(_formatarHora(entrada),
                    style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.dark)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Saída', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto)),
                Text(_formatarHora(saida),
                    style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.dark)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          if (entrada == null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _baterPonto(entrada: true),
                icon: const Icon(Icons.login_rounded, size: 18),
                label: Text('Bater entrada', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _corPonto, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            )
          else if (saida == null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _baterPonto(entrada: false),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text('Bater saída', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _corPonto, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _baterPonto(entrada: true),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Corrigir horários'),
                style: OutlinedButton.styleFrom(foregroundColor: _corPonto, side: const BorderSide(color: _corPonto)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cardSaldoMes() {
    final saldo = _saldoMesMin;
    final cor = saldo < 0 ? Colors.red : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        IconButton(
          onPressed: _temMesAnterior ? _mesAnterior : null,
          icon: Icon(Icons.chevron_left_rounded, color: _temMesAnterior ? null : AppColors.cinzaTexto.withOpacity(0.3)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_meses[_mesSelecionado.month]} ${_mesSelecionado.year}',
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.dark)),
              Text('Saldo do mês', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto)),
            ],
          ),
        ),
        Text(_formatarSaldo(saldo),
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: cor)),
        IconButton(
          onPressed: _vendoMesAtual ? null : _proximoMes,
          icon: Icon(Icons.chevron_right_rounded, color: _vendoMesAtual ? AppColors.cinzaTexto.withOpacity(0.3) : null),
        ),
      ]),
    );
  }

  Widget _listaRegistros() {
    if (_registros.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('Nenhum registro nesse mês ainda.',
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto)),
        ),
      );
    }
    final ordenados = [..._registros]..sort((a, b) => (b['data'] as String).compareTo(a['data'] as String));
    return Column(
      children: ordenados.map((r) {
        final trabalhado = _horasTrabalhadasMin(r);
        final saldoDia = trabalhado != null ? trabalhado - _horasEsperadasMin : null;
        final data = DateTime.parse(r['data'] as String);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(children: [
            SizedBox(
              width: 44,
              child: Text('${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}',
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.dark)),
            ),
            Expanded(
              child: Text('${_formatarHora(r['entrada'] as String?)} — ${_formatarHora(r['saida'] as String?)}',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
            ),
            if (saldoDia != null)
              Text(_formatarSaldo(saldoDia),
                  style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w700, color: saldoDia < 0 ? Colors.red : Colors.green))
            else
              Text('incompleto', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto)),
          ]),
        );
      }).toList(),
    );
  }

  Widget _cardHorasExtras() {
    const corExtra = Color(0xFF7C3AED);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: corExtra.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.nightlight_round, size: 18, color: corExtra),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Horas extras / sobreaviso',
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark)),
                Text('Não entram no saldo da jornada — total à parte',
                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto)),
              ]),
            ),
            Text(_formatarSaldo(_totalHorasExtrasMin).replaceFirst('+', ''),
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: corExtra)),
          ]),
          const SizedBox(height: 12),
          if (_horasExtras.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Nenhum lançamento neste mês.',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
            )
          else
            ..._horasExtras.map((h) {
              final data = DateTime.parse(h['data'] as String);
              final obs = h['observacao'] as String?;
              final inicio = _formatarHora(h['hora_inicio'] as String?);
              final fim = _formatarHora(h['hora_fim'] as String?);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: corExtra.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  SizedBox(
                    width: 44,
                    child: Text('${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.dark)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$inicio — $fim',
                            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
                        if (obs != null && obs.isNotEmpty)
                          Text(obs,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto.withOpacity(0.8))),
                      ],
                    ),
                  ),
                  Text(_formatarSaldo(h['minutos'] as int).replaceFirst('+', ''),
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: corExtra)),
                  IconButton(
                    onPressed: () => _confirmarExcluirHoraExtra(h),
                    icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.cinzaTexto),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                ]),
              );
            }),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _abrirDialogHoraExtra,
              icon: const Icon(Icons.add_rounded, size: 18, color: corExtra),
              label: Text('Registrar hora extra', style: GoogleFonts.poppins(color: corExtra, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: corExtra)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogHoraExtra extends StatefulWidget {
  final String colaboradorId;
  final ApiService api;

  const _DialogHoraExtra({required this.colaboradorId, required this.api});

  @override
  State<_DialogHoraExtra> createState() => _DialogHoraExtraState();
}

class _DialogHoraExtraState extends State<_DialogHoraExtra> {
  DateTime _data = DateTime.now();
  TimeOfDay _horaInicio = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _horaFim = const TimeOfDay(hour: 23, minute: 0);
  final _obsCtrl = TextEditingController();
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  int get _minutos {
    final inicio = _horaInicio.hour * 60 + _horaInicio.minute;
    var fim = _horaFim.hour * 60 + _horaFim.minute;
    if (fim <= inicio) fim += 24 * 60;
    return fim - inicio;
  }

  Future<void> _salvar() async {
    final minutos = _minutos;
    if (minutos <= 0) {
      setState(() => _erro = 'O horário final precisa ser diferente do inicial.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    final dataStr =
        '${_data.year}-${_data.month.toString().padLeft(2, '0')}-${_data.day.toString().padLeft(2, '0')}';
    String fmtTod(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
    final ok = await widget.api.registrarHoraExtra(
      colaboradorId: widget.colaboradorId,
      data: dataStr,
      horaInicio: fmtTod(_horaInicio),
      horaFim: fmtTod(_horaFim),
      minutos: minutos,
      observacao: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _salvando = false);
    if (!ok) {
      setState(() => _erro = 'Não foi possível salvar. Tente novamente.');
      return;
    }
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Registrar hora extra',
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark)),
          const SizedBox(height: 4),
          Text('Ex: sobreaviso chamado fora do horário normal.',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: Text('Data', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.dark))),
            OutlinedButton(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _data,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _data = d);
              },
              child: Text('${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('Início', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.dark))),
            OutlinedButton(
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: _horaInicio);
                if (t != null) setState(() => _horaInicio = t);
              },
              child: Text('${_horaInicio.hour.toString().padLeft(2, '0')}:${_horaInicio.minute.toString().padLeft(2, '0')}',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('Fim', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.dark))),
            OutlinedButton(
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: _horaFim);
                if (t != null) setState(() => _horaFim = t);
              },
              child: Text('${_horaFim.hour.toString().padLeft(2, '0')}:${_horaFim.minute.toString().padLeft(2, '0')}',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Total: ${_formatarSaldo(_minutos).replaceFirst('+', '')}',
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF7C3AED))),
          if (_erro != null) ...[
            const SizedBox(height: 4),
            Text(_erro!, style: GoogleFonts.poppins(fontSize: 12, color: Colors.red)),
          ],
          const SizedBox(height: 12),
          Text('Observação (opcional)', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.cinzaTexto)),
          const SizedBox(height: 6),
          TextField(
            controller: _obsCtrl,
            maxLength: 100,
            style: GoogleFonts.poppins(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Ex: chamado pra resolver sistema fora do horário',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _salvando ? null : _salvar,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), foregroundColor: Colors.white),
              child: _salvando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Salvar'),
            ),
          ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DialogConfigPonto extends StatefulWidget {
  final Map<String, dynamic> config;
  final String colaboradorId;
  final ApiService api;

  const _DialogConfigPonto({required this.config, required this.colaboradorId, required this.api});

  @override
  State<_DialogConfigPonto> createState() => _DialogConfigPontoState();
}

class _DialogConfigPontoState extends State<_DialogConfigPonto> {
  late TimeOfDay _entrada;
  late TimeOfDay _saida;
  late final TextEditingController _almocoCtrl;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final e = _paraMinutos(widget.config['entrada_padrao'] as String?) ?? (7 * 60 + 42);
    final s = _paraMinutos(widget.config['saida_padrao'] as String?) ?? (17 * 60 + 30);
    _entrada = TimeOfDay(hour: e ~/ 60, minute: e % 60);
    _saida = TimeOfDay(hour: s ~/ 60, minute: s % 60);
    _almocoCtrl = TextEditingController(text: '${widget.config['almoco_minutos'] ?? 60}');
  }

  @override
  void dispose() {
    _almocoCtrl.dispose();
    super.dispose();
  }

  String _fmtTod(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _salvar() async {
    final almoco = int.tryParse(_almocoCtrl.text.trim());
    if (almoco == null || almoco < 0) return;
    setState(() => _salvando = true);
    final ok = await widget.api.salvarConfigPonto(
      colaboradorId: widget.colaboradorId,
      entradaPadrao: '${_fmtTod(_entrada)}:00',
      saidaPadrao: '${_fmtTod(_saida)}:00',
      almocoMinutos: almoco,
    );
    if (!mounted) return;
    setState(() => _salvando = false);
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Sua jornada de trabalho',
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark)),
          const SizedBox(height: 4),
          Text('Usada como base pra calcular o seu saldo diário.',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
          const SizedBox(height: 20),
          _linhaHorario('Entrada padrão', _entrada, (t) => setState(() => _entrada = t)),
          const SizedBox(height: 12),
          _linhaHorario('Saída padrão', _saida, (t) => setState(() => _saida = t)),
          const SizedBox(height: 12),
          Text('Almoço (minutos)', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.cinzaTexto)),
          const SizedBox(height: 6),
          TextField(
            controller: _almocoCtrl,
            keyboardType: TextInputType.number,
            style: GoogleFonts.poppins(fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _salvando ? null : _salvar,
              style: ElevatedButton.styleFrom(backgroundColor: _corPonto, foregroundColor: Colors.white),
              child: _salvando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Salvar'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _linhaHorario(String label, TimeOfDay valor, ValueChanged<TimeOfDay> onChanged) {
    return Row(children: [
      Expanded(child: Text(label, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.dark))),
      OutlinedButton(
        onPressed: () async {
          final t = await showTimePicker(context: context, initialTime: valor);
          if (t != null) onChanged(t);
        },
        child: Text(_fmtTod(valor), style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}
