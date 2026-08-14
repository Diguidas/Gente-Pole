import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import '../login_screen.dart';
import 'nutricionista_screen.dart' show NutricionistaAgendamentoModel;

class AdminNutricionistaScreen extends StatefulWidget {
  const AdminNutricionistaScreen({super.key});

  @override
  State<AdminNutricionistaScreen> createState() =>
      _AdminNutricionistaScreenState();
}

class _AdminNutricionistaScreenState
    extends State<AdminNutricionistaScreen> {
  static const _cor = Color(0xFF06B6D4);

  DateTime _dataSelecionada = DateTime.now();
  List<NutricionistaAgendamentoModel> _agendamentos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('pt_BR').then((_) => _carregar());
  }

  String get _dataFormatada =>
      DateFormat('yyyy-MM-dd').format(_dataSelecionada);

  String get _dataTitulo =>
      DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_dataSelecionada);

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final all = await ApiService().buscarAgendamentosNutricionista();
      final doDia = all
          .where((a) => a.data == _dataFormatada)
          .toList()
        ..sort((a, b) => a.horario.compareTo(b.horario));
      if (mounted) setState(() => _agendamentos = doDia);
    } catch (e) {
      debugPrint('Erro ao carregar agendamentos: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mudarData(int dias) async {
    setState(
        () => _dataSelecionada = _dataSelecionada.add(Duration(days: dias)));
    await _carregar();
  }

  Future<void> _abrirCalendario() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      locale: const Locale('pt', 'BR'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _cor,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _dataSelecionada = picked);
      await _carregar();
    }
  }

  Future<void> _marcarNaoVeio(NutricionistaAgendamentoModel ag) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmar ausência'),
        content: Text('${ag.nomeColaborador} não compareceu — ${ag.horario}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.erro),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await ApiService()
        .atualizarPresencaNutricionista(id: ag.id, status: 'NAO_VEIO');
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ausência registrada.'),
        backgroundColor: AppColors.erro,
      ));
      _carregar();
    }
  }

  Future<void> _abrirAssinatura(NutricionistaAgendamentoModel ag) async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AssinaturaModal(nomeColaborador: ag.nomeColaborador),
      ),
    );
    if (bytes == null) return;

    setState(() => _loading = true);
    try {
      final url = await ApiService().uploadAssinaturaNutricionista(
        agendamentoId: ag.id,
        bytes: bytes,
      );
      await ApiService().atualizarPresencaNutricionista(
        id: ag.id,
        status: 'VEIO',
        assinaturaUrl: url,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Presença confirmada e assinatura salva! ✅'),
          backgroundColor: AppColors.sucesso,
        ));
      }
      _carregar();
    } catch (e) {
      debugPrint('Erro ao salvar assinatura: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erro ao salvar. Tente novamente.'),
          backgroundColor: AppColors.erro,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _totalDia => _agendamentos.length;
  int get _vieram => _agendamentos.where((a) => a.status == 'VEIO').length;
  int get _naoVieram =>
      _agendamentos.where((a) => a.status == 'NAO_VEIO').length;
  int get _pendentes =>
      _agendamentos.where((a) => a.status == 'AGENDADO').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        backgroundColor: AppColors.branco,
        elevation: 0,
        centerTitle: false,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_cor, Color(0xFF0891B2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.restaurant_menu_rounded,
                size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Nutricionista',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark)),
            Text('Controle de presença',
                style:
                    TextStyle(fontSize: 11, color: AppColors.cinzaTexto)),
          ]),
        ]),
        actions: [
          IconButton(
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.cinzaTexto),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (_) => false,
            ),
            icon: const Icon(Icons.logout_rounded,
                color: AppColors.cinzaTexto),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        // Seletor de data
        Container(
          color: AppColors.branco,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            IconButton(
              onPressed: () => _mudarData(-1),
              icon: const Icon(Icons.chevron_left_rounded),
              color: AppColors.cinzaTexto,
            ),
            Expanded(
              child: GestureDetector(
                onTap: _abrirCalendario,
                child: Column(children: [
                  Text(_dataTitulo,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.dark)),
                  Text(_dataFormatada.split('-').reversed.join('/'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.cinzaTexto)),
                ]),
              ),
            ),
            IconButton(
              onPressed: () => _mudarData(1),
              icon: const Icon(Icons.chevron_right_rounded),
              color: AppColors.cinzaTexto,
            ),
          ]),
        ),
        // Chips de resumo
        if (!_loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              _chip('Total', _totalDia, AppColors.cinzaTexto),
              const SizedBox(width: 8),
              _chip('Vieram', _vieram, AppColors.sucesso),
              const SizedBox(width: 8),
              _chip('Faltaram', _naoVieram, AppColors.erro),
              const SizedBox(width: 8),
              _chip('Pendentes', _pendentes, AppColors.laranja),
            ]),
          ),
        // Lista
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: _cor))
              : _agendamentos.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        const Icon(Icons.event_available_outlined,
                            size: 56, color: Color(0xFFCBD5E1)),
                        const SizedBox(height: 12),
                        Text('Nenhum agendamento para $_dataTitulo',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.cinzaTexto,
                                fontSize: 14)),
                      ]))
                  : ListView.separated(
                      padding:
                          const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: _agendamentos.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, i) => _CardAgendamento(
                        agendamento: _agendamentos[i],
                        onVeio: () => _abrirAssinatura(_agendamentos[i]),
                        onNaoVeio: () => _marcarNaoVeio(_agendamentos[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _chip(String label, int valor, Color cor) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: cor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: [
            Text('$valor',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: cor)),
            Text(label,
                style: TextStyle(fontSize: 10, color: cor)),
          ]),
        ),
      );
}

// ─── Card de agendamento ──────────────────────────────────────────────────────

class _CardAgendamento extends StatelessWidget {
  final NutricionistaAgendamentoModel agendamento;
  final VoidCallback onVeio;
  final VoidCallback onNaoVeio;

  const _CardAgendamento({
    required this.agendamento,
    required this.onVeio,
    required this.onNaoVeio,
  });

  @override
  Widget build(BuildContext context) {
    final ag = agendamento;
    final (statusColor, statusLabel) = switch (ag.status) {
      'VEIO' => (AppColors.sucesso, 'Presente ✅'),
      'NAO_VEIO' => (AppColors.erro, 'Faltou ❌'),
      'CANCELADO' => (AppColors.cinzaTexto, 'Cancelado'),
      _ => (const Color(0xFF06B6D4), 'Pendente'),
    };
    final pendente = ag.status == 'AGENDADO';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.branco,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: pendente
              ? const Color(0xFFE2E8F0)
              : statusColor.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Horário + status
          Row(children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(ag.horario,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withOpacity(0.3)),
              ),
              child: Text(statusLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor)),
            ),
          ]),
          const SizedBox(height: 12),
          // Nome
          Text(ag.nomeColaborador,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.business_outlined,
                size: 13, color: AppColors.cinzaTexto),
            const SizedBox(width: 4),
            Flexible(
              child: Text(ag.setor,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.cinzaTexto)),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.badge_outlined,
                size: 13, color: AppColors.cinzaTexto),
            const SizedBox(width: 4),
            Text(ag.matricula,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.cinzaTexto)),
          ]),
          // Assinatura registrada
          if (ag.status == 'VEIO' && ag.assinaturaUrl != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.draw_outlined,
                  size: 13, color: AppColors.sucesso),
              const SizedBox(width: 4),
              const Text('Assinatura registrada',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.sucesso,
                      fontWeight: FontWeight.w500)),
            ]),
          ],
          // Botões
          if (pendente) ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onNaoVeio,
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: AppColors.erro),
                  label: const Text('Não veio',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.erro,
                          fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.erro),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onVeio,
                  icon: const Icon(Icons.draw_outlined,
                      size: 16, color: Colors.white),
                  label: const Text('Veio — assinar',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.sucesso,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ─── Modal de assinatura ──────────────────────────────────────────────────────

class _AssinaturaModal extends StatefulWidget {
  final String nomeColaborador;
  const _AssinaturaModal({required this.nomeColaborador});

  @override
  State<_AssinaturaModal> createState() => _AssinaturaModalState();
}

class _AssinaturaModalState extends State<_AssinaturaModal> {
  final _pontosNotifier = ValueNotifier<List<Offset?>>([]);
  List<Offset?> get _pontos => _pontosNotifier.value;
  bool _salvando = false;
  bool get _temAssinatura => _pontos.any((p) => p != null);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _pontosNotifier.dispose();
    super.dispose();
  }

  void _limpar() {
    _pontosNotifier.value = [];
    setState(() {});
  }

  Future<void> _confirmar() async {
    if (!_temAssinatura) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Por favor, assine antes de confirmar.')),
      );
      return;
    }
    setState(() => _salvando = true);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(600, 250);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool novo = true;
    for (final ponto in _pontos) {
      if (ponto == null) {
        novo = true;
      } else {
        if (novo) {
          path.moveTo(ponto.dx, ponto.dy);
          novo = false;
        } else {
          path.lineTo(ponto.dx, ponto.dy);
        }
      }
    }
    canvas.drawPath(path, paint);

    final picture = recorder.endRecording();
    final img =
        await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    if (mounted) Navigator.pop(context, bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.draw_outlined,
                        color: Color(0xFF06B6D4), size: 20),
                    const SizedBox(width: 8),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Assinar presença',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.dark)),
                          Text(widget.nomeColaborador,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.cinzaTexto)),
                        ]),
                  ]),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFFE2E8F0), width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(children: [
                          Positioned(
                            bottom: 48,
                            left: 24,
                            right: 24,
                            child: Container(
                                height: 1,
                                color: const Color(0xFFE2E8F0)),
                          ),
                          if (!_temAssinatura)
                            const Center(
                              child: Text('Assine aqui',
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFFCBD5E1))),
                            ),
                          GestureDetector(
                            onPanUpdate: (details) {
                              _pontosNotifier.value = [
                                ..._pontosNotifier.value,
                                details.localPosition,
                              ];
                              setState(() {});
                            },
                            onPanEnd: (_) {
                              _pontosNotifier.value = [
                                ..._pontosNotifier.value,
                                null,
                              ];
                              setState(() {});
                            },
                            child: CustomPaint(
                              painter: _AssinaturaPainter(
                                _pontos,
                                repaint: _pontosNotifier,
                              ),
                              size: Size.infinite,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 160,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _limpar,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Limpar'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        foregroundColor: AppColors.cinzaTexto,
                        side:
                            const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed:
                          _salvando ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _salvando ? null : _confirmar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.sucesso,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _salvando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check_rounded,
                              color: Colors.white, size: 18),
                      label: Text(
                        _salvando ? 'Salvando...' : 'Confirmar',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _AssinaturaPainter extends CustomPainter {
  final List<Offset?> pontos;
  _AssinaturaPainter(this.pontos, {super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.dark
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < pontos.length - 1; i++) {
      if (pontos[i] != null && pontos[i + 1] != null) {
        canvas.drawLine(pontos[i]!, pontos[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_AssinaturaPainter old) => true;
}
