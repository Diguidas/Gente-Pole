import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const _corSalas = Color(0xFF0891B2);

const _tiposSala = {
  'copa': ('Copa', Icons.emoji_food_beverage_outlined),
  'sala_reuniao': ('Sala de Reunião', Icons.meeting_room_outlined),
  'auditorio': ('Auditório', Icons.groups_outlined),
};

const _subtiposCopa = {'aniversario': 'Aniversário', 'confraternizacao': 'Confraternização'};
const _subtiposAuditorio = {'reuniao': 'Reunião', 'treinamento': 'Treinamento', 'evento': 'Evento'};
const _labelSubtipo = {
  'aniversario': 'Aniversário',
  'confraternizacao': 'Confraternização',
  'reuniao': 'Reunião',
  'treinamento': 'Treinamento',
  'evento': 'Evento',
};

class ReservaSalasScreen extends StatefulWidget {
  const ReservaSalasScreen({super.key});

  @override
  State<ReservaSalasScreen> createState() => _ReservaSalasScreenState();
}

class _ReservaSalasScreenState extends State<ReservaSalasScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _salas = [];
  List<Map<String, dynamic>> _minhasReservas = [];
  bool _abaMinhas = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final colab = _api.colaboradorAtual;
    if (colab == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final results = await Future.wait([
      _api.listarSalasReserva(apenasAtivas: true),
      _api.listarMinhasReservasSalas(colab.id.toString()),
    ]);
    if (!mounted) return;
    setState(() {
      _salas = results[0] as List<Map<String, dynamic>>;
      _minhasReservas = results[1] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  Future<void> _abrirReserva(Map<String, dynamic> sala) async {
    final colab = _api.colaboradorAtual;
    if (colab == null) return;
    final reservou = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogReserva(sala: sala, colaboradorId: colab.id.toString(), colaboradorNome: colab.nome, api: _api),
    );
    if (reservou == true) _carregar();
  }

  Future<void> _confirmarCancelar(Map<String, dynamic> r) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar reserva?'),
        content: Text('Cancelar "${r['titulo']}" (${r['sala_nome']})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancelar')),
        ],
      ),
    );
    if (confirmar != true) return;
    final ok = await _api.cancelarReservaSala(r['id'] as int);
    if (ok) _carregar();
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
                height: 150,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_corSalas, Color(0xFF0E7490)], begin: Alignment.topLeft, end: Alignment.bottomRight),
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
                left: 20,
                right: 20,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.meeting_room_outlined, color: Colors.white, size: 32),
                    const SizedBox(height: 8),
                    Text('Reserva de Salas', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text('Copa, salas de reunião e auditório',
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.white.withOpacity(0.85))),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(color: Color(0xFFF8F9FC), borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _corSalas))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                          child: Row(children: [
                            _tabBtn('Salas', !_abaMinhas, () => setState(() => _abaMinhas = false)),
                            const SizedBox(width: 8),
                            _tabBtn('Minhas reservas', _abaMinhas, () => setState(() => _abaMinhas = true)),
                          ]),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            color: _corSalas,
                            onRefresh: _carregar,
                            child: _abaMinhas ? _listaMinhasReservas() : _listaSalas(),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, bool ativo, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: ativo ? _corSalas : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: ativo ? Colors.white : AppColors.cinzaTexto)),
      ),
    );
  }

  Widget _listaSalas() {
    if (_salas.isEmpty) {
      return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
        Padding(
          padding: const EdgeInsets.all(40),
          child: Center(child: Text('Nenhuma sala disponível no momento.', style: GoogleFonts.poppins(color: AppColors.cinzaTexto))),
        ),
      ]);
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 190,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: _salas.length,
      itemBuilder: (_, i) {
        final sala = _salas[i];
        final fotoUrl = sala['foto_url'] as String?;
        final tipo = sala['tipo'] as String;
        final (label, icone) = _tiposSala[tipo] ?? ('Sala', Icons.meeting_room_outlined);
        return GestureDetector(
          onTap: () => _abrirReserva(sala),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: fotoUrl != null && fotoUrl.isNotEmpty
                      ? Image.network(fotoUrl, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: const Color(0xFFF1F5F9), child: Icon(icone, color: _corSalas, size: 26)))
                      : Container(color: const Color(0xFFF1F5F9), child: Icon(icone, color: _corSalas, size: 26)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sala['nome'] as String,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dark)),
                      Text(label, style: GoogleFonts.poppins(fontSize: 10, color: AppColors.cinzaTexto)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _listaMinhasReservas() {
    if (_minhasReservas.isEmpty) {
      return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
        Padding(
          padding: const EdgeInsets.all(40),
          child: Center(child: Text('Você ainda não reservou nenhuma sala.', style: GoogleFonts.poppins(color: AppColors.cinzaTexto))),
        ),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _minhasReservas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _minhasReservas[i];
        final data = DateTime.parse(r['data'] as String);
        final subtipo = r['subtipo'] as String?;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r['titulo'] as String, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark)),
                  Text('${r['sala_nome']}${subtipo != null ? ' · ${_labelSubtipo[subtipo] ?? subtipo}' : ''}',
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
                  Text(
                      '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year} · ${_fmt(r['hora_inicio'] as String)} — ${_fmt(r['hora_fim'] as String)}',
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: _corSalas)),
                ],
              ),
            ),
            IconButton(onPressed: () => _confirmarCancelar(r), icon: const Icon(Icons.close_rounded, color: Colors.red)),
          ]),
        );
      },
    );
  }

  String _fmt(String hhmm) {
    final p = hhmm.split(':');
    return '${p[0].padLeft(2, '0')}:${p[1].padLeft(2, '0')}';
  }
}

// ─── Dialog de reserva ──────────────────────────────────────────────────────

class _DialogReserva extends StatefulWidget {
  final Map<String, dynamic> sala;
  final String colaboradorId;
  final String colaboradorNome;
  final ApiService api;

  const _DialogReserva({required this.sala, required this.colaboradorId, required this.colaboradorNome, required this.api});

  @override
  State<_DialogReserva> createState() => _DialogReservaState();
}

// Grade de horários da agenda: 07:00 às 20:00, em blocos de 30min.
const _agendaInicioMin = 7 * 60;
const _agendaFimMin = 20 * 60;
const _agendaSlotMin = 30;
const _agendaTotalSlots = (_agendaFimMin - _agendaInicioMin) ~/ _agendaSlotMin;

class _DialogReservaState extends State<_DialogReserva> {
  int _etapa = 0; // 0 = confirmação do tipo, 1 = formulário, 2 = agenda do dia
  String? _subtipo;

  DateTime _data = DateTime.now();
  TimeOfDay _horaInicio = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _horaFim = const TimeOfDay(hour: 10, minute: 0);
  final _tituloCtrl = TextEditingController();
  final _responsavelCtrl = TextEditingController();
  final _contatoCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  bool _salvando = false;
  String? _erro;

  // ── Agenda do dia (etapa 2) ────────────────────────────────────────────
  bool _carregandoAgenda = false;
  List<Map<String, dynamic>> _reservasDoDia = [];
  int? _slotInicio;
  int? _slotFim;
  final _agendaScrollCtrl = ScrollController();

  String get _tipo => widget.sala['tipo'] as String;

  @override
  void initState() {
    super.initState();
    _responsavelCtrl.text = widget.colaboradorNome;
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _responsavelCtrl.dispose();
    _contatoCtrl.dispose();
    _obsCtrl.dispose();
    _agendaScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_tituloCtrl.text.trim().isEmpty || _responsavelCtrl.text.trim().isEmpty || _contatoCtrl.text.trim().isEmpty) {
      setState(() => _erro = 'Preencha título, responsável e contato.');
      return;
    }
    final inicioMin = _horaInicio.hour * 60 + _horaInicio.minute;
    final fimMin = _horaFim.hour * 60 + _horaFim.minute;
    if (fimMin <= inicioMin) {
      setState(() => _erro = 'O horário final precisa ser depois do inicial.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    String fmtTod(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
    final dataStr = '${_data.year}-${_data.month.toString().padLeft(2, '0')}-${_data.day.toString().padLeft(2, '0')}';

    final erro = await widget.api.reservarSala(
      salaId: widget.sala['id'] as int,
      data: dataStr,
      horaInicio: fmtTod(_horaInicio),
      horaFim: fmtTod(_horaFim),
      colaboradorId: widget.colaboradorId,
      colaboradorNome: widget.colaboradorNome,
      titulo: _tituloCtrl.text.trim(),
      subtipo: _subtipo,
      responsavelNome: _responsavelCtrl.text.trim(),
      responsavelContato: _contatoCtrl.text.trim(),
      observacao: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _salvando = false);
    if (erro != null) {
      setState(() => _erro = erro);
      return;
    }
    Navigator.pop(context, true);
  }

  Future<void> _irParaAgenda() async {
    setState(() {
      _etapa = 2;
      _slotInicio = null;
      _slotFim = null;
    });
    await _carregarAgenda();
  }

  Future<void> _carregarAgenda() async {
    setState(() => _carregandoAgenda = true);
    final res = await widget.api.listarTodasReservasSalas(
      salaId: widget.sala['id'] as int,
      dataInicio: _data,
      dataFim: _data,
    );
    if (!mounted) return;
    setState(() {
      _reservasDoDia = res;
      _carregandoAgenda = false;
    });
  }

  void _mudarDia(int deltaDias) {
    final novaData = _data.add(Duration(days: deltaDias));
    final hoje = DateTime.now();
    final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);
    if (novaData.isBefore(hojeSemHora)) return;
    setState(() {
      _data = novaData;
      _slotInicio = null;
      _slotFim = null;
    });
    _carregarAgenda();
  }

  int _minutosFromHHMMSS(String s) {
    final p = s.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  bool _slotOcupado(int slotIndex) {
    final inicio = _agendaInicioMin + slotIndex * _agendaSlotMin;
    final fim = inicio + _agendaSlotMin;
    for (final r in _reservasDoDia) {
      final ri = _minutosFromHHMMSS(r['hora_inicio'] as String);
      final rf = _minutosFromHHMMSS(r['hora_fim'] as String);
      if (ri < fim && rf > inicio) return true;
    }
    return false;
  }

  void _tocarSlot(int slotIndex) {
    if (_slotOcupado(slotIndex)) return;
    if (_slotInicio == null || _slotFim != null) {
      setState(() {
        _slotInicio = slotIndex;
        _slotFim = null;
      });
      return;
    }
    if (slotIndex == _slotInicio) {
      setState(() => _slotInicio = null);
      return;
    }
    if (slotIndex < _slotInicio!) {
      setState(() {
        _slotInicio = slotIndex;
        _slotFim = null;
      });
      return;
    }
    // Confirma o fim do intervalo só se nenhum slot no meio estiver ocupado.
    for (var i = _slotInicio!; i <= slotIndex; i++) {
      if (_slotOcupado(i)) {
        setState(() {
          _slotInicio = slotIndex;
          _slotFim = null;
        });
        return;
      }
    }
    setState(() => _slotFim = slotIndex);
  }

  void _confirmarHorarioDaAgenda() {
    if (_slotInicio == null || _slotFim == null) return;
    final inicioMin = _agendaInicioMin + _slotInicio! * _agendaSlotMin;
    final fimMin = _agendaInicioMin + (_slotFim! + 1) * _agendaSlotMin;
    setState(() {
      _horaInicio = TimeOfDay(hour: inicioMin ~/ 60, minute: inicioMin % 60);
      _horaFim = TimeOfDay(hour: fimMin ~/ 60, minute: fimMin % 60);
      _etapa = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _etapa == 2
              ? _buildAgenda()
              : SingleChildScrollView(
                  child: _etapa == 0 ? _buildEtapaInicial() : _buildFormulario(),
                ),
        ),
      ),
    );
  }

  Widget _buildEtapaInicial() {
    final nome = widget.sala['nome'] as String;
    final fotoUrl = widget.sala['foto_url'] as String?;

    if (_tipo == 'copa') {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Reservar $nome', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark)),
        const SizedBox(height: 4),
        Text('O que vai rolar?', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto)),
        const SizedBox(height: 16),
        ..._subtiposCopa.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    _subtipo = e.key;
                    _irParaAgenda();
                  },
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: const BorderSide(color: _corSalas)),
                  child: Text(e.value, style: GoogleFonts.poppins(color: _corSalas, fontWeight: FontWeight.w600)),
                ),
              ),
            )),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))),
      ]);
    }

    if (_tipo == 'auditorio') {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Reservar $nome', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark)),
        const SizedBox(height: 4),
        Text('Qual o tipo de evento?', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto)),
        const SizedBox(height: 16),
        ..._subtiposAuditorio.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    _subtipo = e.key;
                    _irParaAgenda();
                  },
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: const BorderSide(color: _corSalas)),
                  child: Text(e.value, style: GoogleFonts.poppins(color: _corSalas, fontWeight: FontWeight.w600)),
                ),
              ),
            )),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))),
      ]);
    }

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Reservar $nome', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark)),
      const SizedBox(height: 4),
      Text('Confirma que é essa sala?', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto)),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: fotoUrl != null && fotoUrl.isNotEmpty
              ? Image.network(fotoUrl, fit: BoxFit.cover)
              : Container(color: const Color(0xFFF1F5F9), child: const Icon(Icons.meeting_room_outlined, color: _corSalas, size: 32)),
        ),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Não é essa'))),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: _irParaAgenda,
            style: ElevatedButton.styleFrom(backgroundColor: _corSalas, foregroundColor: Colors.white),
            child: const Text('Sim, é essa'),
          ),
        ),
      ]),
    ]);
  }

  Widget _buildFormulario() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconButton(
          onPressed: () => setState(() => _etapa = 2),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(widget.sala['nome'] as String, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark))),
      ]),
      if (_subtipo != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(_labelSubtipo[_subtipo] ?? _subtipo!, style: GoogleFonts.poppins(fontSize: 12, color: _corSalas, fontWeight: FontWeight.w600)),
        ),
      const SizedBox(height: 16),
      _campo('Título', _tituloCtrl, hint: 'Ex: Reunião de equipe'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text('Data', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.dark))),
        OutlinedButton(
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _data, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null) setState(() => _data = d);
          },
          child: Text('${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}'),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Text('Início', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.dark))),
        OutlinedButton(
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: _horaInicio);
            if (t != null) setState(() => _horaInicio = t);
          },
          child: Text('${_horaInicio.hour.toString().padLeft(2, '0')}:${_horaInicio.minute.toString().padLeft(2, '0')}'),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Text('Fim', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.dark))),
        OutlinedButton(
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: _horaFim);
            if (t != null) setState(() => _horaFim = t);
          },
          child: Text('${_horaFim.hour.toString().padLeft(2, '0')}:${_horaFim.minute.toString().padLeft(2, '0')}'),
        ),
      ]),
      const SizedBox(height: 12),
      _campo('Responsável', _responsavelCtrl),
      const SizedBox(height: 12),
      _campo('Contato (ramal/telefone)', _contatoCtrl, hint: 'Ex: 1234 ou (11) 99999-9999'),
      const SizedBox(height: 12),
      _campo('Observação (opcional)', _obsCtrl, maxLines: 2),
      if (_erro != null) ...[
        const SizedBox(height: 8),
        Text(_erro!, style: GoogleFonts.poppins(fontSize: 12, color: Colors.red)),
      ],
      const SizedBox(height: 16),
      Row(children: [
        const Spacer(),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _salvando ? null : _salvar,
          style: ElevatedButton.styleFrom(backgroundColor: _corSalas, foregroundColor: Colors.white),
          child: _salvando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Reservar'),
        ),
      ]),
    ]);
  }

  Widget _buildAgenda() {
    final hoje = DateTime.now();
    final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);
    final dataSemHora = DateTime(_data.year, _data.month, _data.day);
    final podeVoltarDia = dataSemHora.isAfter(hojeSemHora);
    const meses = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconButton(
          onPressed: () => setState(() => _etapa = 0),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(widget.sala['nome'] as String,
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark)),
        ),
      ]),
      const SizedBox(height: 4),
      Text('Toque num horário livre pra começar e no fim desejado.',
          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          onPressed: podeVoltarDia ? () => _mudarDia(-1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text('${dataSemHora.day.toString().padLeft(2, '0')} de ${meses[dataSemHora.month - 1]}',
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.dark)),
        IconButton(
          onPressed: () => _mudarDia(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ]),
      Row(children: [
        _legendaItem(const Color(0xFFE2E8F0), 'Ocupado'),
        const SizedBox(width: 16),
        _legendaItem(Colors.white, 'Livre', comBorda: true),
        const SizedBox(width: 16),
        _legendaItem(_corSalas, 'Selecionado'),
      ]),
      const SizedBox(height: 12),
      if (_carregandoAgenda)
        const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: _corSalas)))
      else
        SizedBox(
          height: 320,
          child: Scrollbar(
            controller: _agendaScrollCtrl,
            child: ListView.builder(
              controller: _agendaScrollCtrl,
              itemCount: _agendaTotalSlots,
              itemBuilder: (_, i) {
                final ocupado = _slotOcupado(i);
                final selecionado = _slotInicio != null &&
                    _slotFim != null &&
                    i >= _slotInicio! &&
                    i <= _slotFim!;
                final inicioSelecao = _slotInicio == i && _slotFim == null;
                final minutoInicio = _agendaInicioMin + i * _agendaSlotMin;
                final label =
                    '${(minutoInicio ~/ 60).toString().padLeft(2, '0')}:${(minutoInicio % 60).toString().padLeft(2, '0')}';
                final cor = ocupado
                    ? const Color(0xFFE2E8F0)
                    : (selecionado || inicioSelecao)
                        ? _corSalas
                        : Colors.white;
                return GestureDetector(
                  onTap: () => _tocarSlot(i),
                  child: Container(
                    height: 30,
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: cor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: ocupado ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1)),
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(label,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ocupado
                              ? AppColors.cinzaTexto
                              : (selecionado || inicioSelecao)
                                  ? Colors.white
                                  : AppColors.dark,
                        )),
                  ),
                );
              },
            ),
          ),
        ),
      const SizedBox(height: 12),
      Row(children: [
        const Spacer(),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: (_slotInicio != null && _slotFim != null) ? _confirmarHorarioDaAgenda : null,
          style: ElevatedButton.styleFrom(backgroundColor: _corSalas, foregroundColor: Colors.white),
          child: const Text('Continuar'),
        ),
      ]),
    ]);
  }

  Widget _legendaItem(Color cor, String label, {bool comBorda = false}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: cor,
          borderRadius: BorderRadius.circular(3),
          border: comBorda ? Border.all(color: const Color(0xFFCBD5E1)) : null,
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto)),
    ]);
  }

  Widget _campo(String label, TextEditingController ctrl, {String? hint, int maxLines = 1}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.cinzaTexto)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        ),
      ),
    ]);
  }
}
