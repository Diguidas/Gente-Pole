import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/massoterapia_model.dart';
import '../../services/api_service.dart';

class MassoterapiaScreen extends StatefulWidget {
  const MassoterapiaScreen({super.key});

  @override
  State<MassoterapiaScreen> createState() => _MassoterapiaScreenState();
}

class _MassoterapiaScreenState extends State<MassoterapiaScreen> {
  final _api = ApiService();

  // Dados carregados
  List<MassoterapiaAgendamentoModel> _agendamentos = [];
  List<String> _diasDisponiveis = []; // datas 'yyyy-MM-dd'
  MassoterapiaConfigSetorModel? _configSetor;
  Map<String, dynamic>? _statusCiclo;
  bool _loading = true;
  String? _erro;

  // Seleção do usuário
  String? _dataSelecionada;
  String? _horarioSelecionado;
  bool _salvando = false;
  final _scrollDatasCtrl = ScrollController();

  @override
  void dispose() {
    _scrollDatasCtrl.dispose();
    super.dispose();
  }

  // Agendamento atual do colaborador logado
  MassoterapiaAgendamentoModel? get _meuAgendamento {
    final meuId = _api.colaboradorAtual?.id;
    if (meuId == null) return null;
    try {
      return _agendamentos.firstWhere((a) => a.colaboradorId == meuId);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final resultados = await Future.wait([
        _api.buscarDiasDisponiveisMassoterapia(),
        _api.buscarAgendamentosMassoterapia(),
        _api.buscarConfigSetorMassoterapia(
          _api.colaboradorAtual?.setor ?? '',
          filial: _api.colaboradorAtual?.filialEfetiva,
        ),
        _api.buscarStatusCicloMassoterapia(),
      ]);
      if (!mounted) return;
      setState(() {
        _diasDisponiveis = resultados[0] as List<String>;
        _agendamentos = resultados[1] as List<MassoterapiaAgendamentoModel>;
        _configSetor = resultados[2] as MassoterapiaConfigSetorModel?;
        _statusCiclo = resultados[3] as Map<String, dynamic>;
        // Pré-seleciona o primeiro dia (hoje ou futuro) que ainda tem vaga
        // de verdade — não adianta abrir num dia sem horário livre nem
        // vaga de setor, mesmo que seja o mais próximo cronologicamente.
        if (_diasDisponiveis.isNotEmpty && _dataSelecionada == null) {
          final agora = _brasilia();
          final hojeStr =
              '${agora.year}-${agora.month.toString().padLeft(2, '0')}-${agora.day.toString().padLeft(2, '0')}';
          final futuros =
              _diasDisponiveis.where((d) => d.compareTo(hojeStr) >= 0).toList();
          _dataSelecionada = futuros.firstWhere(
            _temVagaDisponivelEm,
            orElse: () =>
                futuros.isNotEmpty ? futuros.first : _diasDisponiveis.last,
          );
        }
        _loading = false;
      });
      _rolarAteDataSelecionada();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar agenda. Tente novamente.';
        _loading = false;
      });
    }
  }

  // ── Slots de horário para o dia selecionado ──────────────────────────────

  List<String> get _todosSlots {
    final slots = <String>[];
    // Manhã: 08:00 – 11:45
    for (var h = 8; h < 12; h++) {
      for (var m = 0; m < 60; m += 15) {
        slots.add(
          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
        );
      }
    }
    // Tarde: 13:00 – 16:45
    for (var h = 13; h < 17; h++) {
      for (var m = 0; m < 60; m += 15) {
        slots.add(
          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
        );
      }
    }
    return slots;
  }

  Set<String> _slotsOcupadosEm(String? data) {
    if (data == null) return {};
    return _agendamentos
        .where((a) => a.data == data && a.status != 'CANCELADO')
        .map((a) => a.horario)
        .toSet();
  }

  Set<String> get _slotsOcupados => _slotsOcupadosEm(_dataSelecionada);

  // Horário de Brasília (UTC-3, sem DST), independe do fuso do dispositivo
  static DateTime _brasilia() =>
      DateTime.now().toUtc().subtract(const Duration(hours: 3));

  /// Slots já passados em [data]: todos, se a data já passou por completo;
  /// só os do horário, se a data for hoje; nenhum, se for uma data futura.
  Set<String> _slotsPassadosEm(String? data) {
    if (data == null) return {};
    final agora = _brasilia();
    final hojeStr =
        '${agora.year}-${agora.month.toString().padLeft(2, '0')}-${agora.day.toString().padLeft(2, '0')}';
    if (data.compareTo(hojeStr) < 0) return _todosSlots.toSet();
    if (data != hojeStr) return {};
    return _todosSlots.where((slot) {
      final partes = slot.split(':');
      final h = int.parse(partes[0]);
      final m = int.parse(partes[1]);
      return h < agora.hour || (h == agora.hour && m <= agora.minute);
    }).toSet();
  }

  Set<String> get _slotsPassados => _slotsPassadosEm(_dataSelecionada);

  List<MassoterapiaAgendamentoModel> get _agendamentosDoDia {
    if (_dataSelecionada == null) return [];
    return _agendamentos.where((a) => a.data == _dataSelecionada).toList()
      ..sort((a, b) => a.horario.compareTo(b.horario));
  }

  int _vagasUsadasMeuSetorEm(String? data) {
    final setor = _api.colaboradorAtual?.setor ?? '';
    if (data == null) return 0;
    return _agendamentos
        .where(
          (a) => a.data == data && a.setor == setor && a.status != 'CANCELADO',
        ) // ← conta AGENDADO + VEIO + NAO_VEIO
        .length;
  }

  int get _vagasUsadasMeuSetor => _vagasUsadasMeuSetorEm(_dataSelecionada);

  /// Quantos horários ainda podem ser agendados em [data] (não ocupados e
  /// não passados) — é o teto real de vagas: não faz sentido mostrar
  /// "3 vagas" se só sobra 1 horário livre até o fim do expediente.
  int _slotsLivresRestantesEm(String? data) {
    final ocupados = _slotsOcupadosEm(data);
    final passados = _slotsPassadosEm(data);
    return _todosSlots
        .where((s) => !ocupados.contains(s) && !passados.contains(s))
        .length;
  }

  int get _slotsLivresRestantes => _slotsLivresRestantesEm(_dataSelecionada);

  /// Vagas restantes do setor em [data], já limitadas pelos horários que
  /// ainda restam no dia.
  int _vagasRestantesEm(String? data) {
    final porHorarios = _slotsLivresRestantesEm(data);
    final vagasSetor = _configSetor?.vagasDia ?? 0;
    if (vagasSetor <= 0) return porHorarios;
    final porSetor = vagasSetor - _vagasUsadasMeuSetorEm(data);
    return porSetor < porHorarios ? (porSetor < 0 ? 0 : porSetor) : porHorarios;
  }

  int get _vagasRestantes => _vagasRestantesEm(_dataSelecionada);

  bool get _setorLotado => _vagasRestantes <= 0;

  /// Se [data] ainda tem alguma vaga real pra agendar (considerando slots
  /// ocupados/passados e limite de setor) — usado pra pré-selecionar o
  /// primeiro dia com vaga de verdade, não só o primeiro dia do ciclo.
  bool _temVagaDisponivelEm(String data) => _vagasRestantesEm(data) > 0;

  // ── Ações ────────────────────────────────────────────────────────────────

  Future<void> _agendar() async {
    if (_dataSelecionada == null || _horarioSelecionado == null) return;
    if (_meuAgendamento != null) {
      _mostrarErro('Você já tem um agendamento neste dia.');
      return;
    }
    if (_setorLotado) {
      _mostrarErro('Seu setor atingiu o limite de vagas para este dia.');
      return;
    }

    if (_statusCiclo?['proxima_paga'] == true) {
      final custo = _statusCiclo?['custo_polecoins_extra'] as int? ?? 0;
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Sessão paga com PoleCoins',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Você já usou suas sessões grátis neste ciclo. Essa sessão vai custar '
            '$custo PoleCoins. Confirma?',
            style: GoogleFonts.poppins(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Confirmar', style: GoogleFonts.poppins(color: AppColors.laranja)),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
    }

    setState(() => _salvando = true);

    final resultado = await _api.agendarMassoterapia(
      data: _dataSelecionada!,
      horario: _horarioSelecionado!,
    );

    if (!mounted) return;
    setState(() => _salvando = false);

    if (resultado.ok) {
      final mensagem = resultado.pagoComPolecoins
          ? 'Agendado para ${_formatarData(_dataSelecionada!)} às $_horarioSelecionado! '
                'Você atingiu o limite de sessões grátis e essa foi paga com PoleCoins.'
          : 'Agendado para ${_formatarData(_dataSelecionada!)} às $_horarioSelecionado!';
      _mostrarSucesso(mensagem);
      _horarioSelecionado = null;
      await _carregar();
    } else if (resultado.motivo == 'saldo_insuficiente') {
      _mostrarErro(
        'Você atingiu o limite de sessões grátis e não tem PoleCoins suficientes para pagar uma sessão extra.',
      );
    } else if (resultado.motivo == 'data_passada') {
      _mostrarErro('Não é possível agendar para uma data que já passou.');
    } else {
      _mostrarErro('Não foi possível agendar. Tente outro horário.');
    }
  }

  static const _minutosLimiteCancelamento = 15;

  /// Combina data + horário do agendamento num DateTime (horário de Brasília).
  DateTime? _dataHoraAgendamento(MassoterapiaAgendamentoModel a) {
    final partesData = a.data.split('-');
    if (partesData.length != 3) return null;
    final partesHora = a.horario.split(':');
    if (partesHora.length < 2) return null;
    return DateTime(
      int.parse(partesData[0]),
      int.parse(partesData[1]),
      int.parse(partesData[2]),
      int.parse(partesHora[0]),
      int.parse(partesHora[1]),
    );
  }

  bool _podeCancelar(MassoterapiaAgendamentoModel a) {
    final dataHora = _dataHoraAgendamento(a);
    if (dataHora == null) return true;
    final limite =
        dataHora.subtract(const Duration(minutes: _minutosLimiteCancelamento));
    return _brasilia().isBefore(limite);
  }

  Future<void> _cancelar() async {
    final agend = _meuAgendamento;
    if (agend == null) return;

    if (!_podeCancelar(agend)) {
      _mostrarErro(
          'Cancelamento não permitido: só é possível cancelar até '
          '$_minutosLimiteCancelamento minutos antes do horário.');
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cancelar agendamento',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Tem certeza que deseja cancelar o horário das ${agend.horario} em ${_formatarData(agend.data)}?',
          style: GoogleFonts.poppins(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Não', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Sim, cancelar',
              style: GoogleFonts.poppins(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _salvando = true);
    final ok = await _api.cancelarMassoterapia(agend.id);
    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      _mostrarSucesso('Agendamento cancelado.');
      await _carregar();
    } else {
      _mostrarErro('Erro ao cancelar. Tente novamente.');
    }
  }

  void _mostrarErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins()),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _mostrarSucesso(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins()),
        backgroundColor: AppColors.magenta,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              // Proporção real do asset (1440x540) — evita qualquer corte,
              // lateral ou vertical, em qualquer largura de tela.
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(28)),
                child: AspectRatio(
                  aspectRatio: 1440 / 540,
                  child: Image.asset(
                    'assets/massoterapia.png',
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
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
                        color: Colors.black.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Massoterapia',
                    style: GoogleFonts.poppins(
                        fontSize: 22, fontWeight: FontWeight.w700)),
                Text('Agende sua sessão de bem-estar',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FC),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: _loading
                  ? _buildLoading()
                  : _erro != null
                  ? _buildErro()
                  : _buildConteudo(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.laranja),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _erro!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _carregar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.laranja,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Tentar novamente',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConteudo() {
    return RefreshIndicator(
      color: AppColors.laranja,
      onRefresh: _carregar,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner do meu agendamento — sempre visível (com o botão de
            // cancelar), mesmo quando hoje não é dia de massoterapia, já que
            // o agendamento pode ser para uma data futura.
            if (_meuAgendamento != null) _buildMeuAgendamentoBanner(),
            if (_meuAgendamento != null) const SizedBox(height: 20),

            if (_diasDisponiveis.isEmpty)
              _buildSemMassoterapiaHoje()
            else ...[
              // Seletor de data
              _buildSectionLabel('📅 Escolha o dia'),
              const SizedBox(height: 10),
              _buildSeletorDatas(),
              const SizedBox(height: 24),

              // Info de vagas do setor
              if (_configSetor != null) _buildInfoVagasSetor(),
              if (_configSetor != null) const SizedBox(height: 20),

              // Grade de horários (só se não tiver agendamento)
              if (_meuAgendamento == null ||
                  _meuAgendamento!.status == 'CANCELADO') ...[
                if (_statusCiclo != null) _buildContadorCiclo(),
                if (_statusCiclo != null) const SizedBox(height: 16),
                _buildSectionLabel('🕐 Escolha o horário'),
                const SizedBox(height: 10),
                _buildGradeHorarios(),
                const SizedBox(height: 24),
                _buildBotaoAgendar(),
                const SizedBox(height: 28),
              ],

              // Lista de quem agendou no dia
              _buildSectionLabel('👥 Quem vai hoje'),
              const SizedBox(height: 10),
              _buildListaAgendados(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSemMassoterapiaHoje() {
    final proxima = _diasDisponiveis.isNotEmpty ? _diasDisponiveis.first : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.laranja.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                size: 40,
                color: AppColors.laranja,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Hoje não tem massoterapia',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              proxima != null
                  ? 'A próxima sessão será em\n${_formatarData(proxima)}'
                  : 'Nenhuma sessão agendada no momento.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Meu agendamento banner ───────────────────────────────────────────────

  Widget _buildMeuAgendamentoBanner() {
    final a = _meuAgendamento!;
    final jaFoi = a.status == 'VEIO';
    final naoVeio = a.status == 'NAO_VEIO';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: jaFoi
              ? [Colors.green.shade500, Colors.green.shade700]
              : naoVeio
              ? [Colors.red.shade400, Colors.red.shade700]
              : [AppColors.laranja, AppColors.magenta],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              jaFoi
                  ? Icons.check_circle_rounded
                  : naoVeio
                  ? Icons.cancel_rounded
                  : Icons.event_available_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  jaFoi
                      ? 'Presença confirmada!'
                      : naoVeio
                      ? 'Você não compareceu'
                      : 'Você está agendado!',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${_formatarData(a.data)} às ${a.horario}',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Só mostra cancelar se ainda estiver AGENDADO e dentro do prazo
          if (a.status == 'AGENDADO' && _podeCancelar(a))
            TextButton(
              onPressed: _salvando ? null : _cancelar,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: Text(
                'Cancelar',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white,
                ),
              ),
            )
          else if (a.status == 'AGENDADO')
            Tooltip(
              message:
                  'Não é mais possível cancelar (menos de $_minutosLimiteCancelamento min para o horário).',
              child: Icon(Icons.lock_clock_rounded,
                  color: Colors.white.withOpacity(0.7), size: 18),
            ),
        ],
      ),
    );
  }

  // ── Seletor de datas ─────────────────────────────────────────────────────

  // Largura do chip (56) + espaçamento (8) — usado pra rolar o carrossel
  // até o dia selecionado, já que agora a lista inclui dias passados e o
  // selecionado pode não estar no início.
  static const double _larguraChipData = 64;

  void _rolarAteDataSelecionada() {
    if (_dataSelecionada == null) return;
    final index = _diasDisponiveis.indexOf(_dataSelecionada!);
    if (index <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollDatasCtrl.hasClients) return;
      final alvo = (index * _larguraChipData - 100).clamp(
        0.0,
        _scrollDatasCtrl.position.maxScrollExtent,
      );
      _scrollDatasCtrl.animateTo(
        alvo,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildSeletorDatas() {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        controller: _scrollDatasCtrl,
        scrollDirection: Axis.horizontal,
        itemCount: _diasDisponiveis.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final data = _diasDisponiveis[i];
          final selecionado = data == _dataSelecionada;
          final partes = data.split('-');
          final dt = DateTime(
            int.parse(partes[0]),
            int.parse(partes[1]),
            int.parse(partes[2]),
          );
          final diaSemana = _nomeDiaSemana(dt.weekday);
          final dia = partes[2];

          return GestureDetector(
            onTap: () => setState(() {
              _dataSelecionada = data;
              _horarioSelecionado = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              decoration: BoxDecoration(
                gradient: selecionado
                    ?  AppColors.gradientePrincipal
                    : null,
                color: selecionado ? null : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: selecionado
                        ? AppColors.gradientePrincipal.colors[0].withOpacity(0.35)
                        : Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    diaSemana,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: selecionado
                          ? Colors.white.withOpacity(0.85)
                          : Colors.grey.shade500,
                    ),
                  ),
                  Text(
                    dia,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: selecionado ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Info vagas do setor ──────────────────────────────────────────────────

  Widget _buildInfoVagasSetor() {
    final usadas = _vagasUsadasMeuSetor;
    final total = _configSetor!.vagasDia;
    final restam = _vagasRestantes;
    final cor = restam == 0
        ? Colors.red.shade600
        : restam == 1
        ? AppColors.magenta
        : AppColors.laranja;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.group_outlined, color: cor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              restam == 0
                  ? 'Não há mais vagas hoje.'
                  : restam == 1
                  ? 'Última vaga do seu setor hoje!'
                  : '$restam vagas disponíveis para seu setor hoje',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: cor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '$usadas/$total',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: cor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContadorCiclo() {
    final usadas = _statusCiclo!['usadas'] as int? ?? 0;
    final limite = _statusCiclo!['limite'] as int? ?? 0;
    final proximaPaga = _statusCiclo!['proxima_paga'] == true;
    final custo = _statusCiclo!['custo_polecoins_extra'] as int? ?? 0;
    final cor = proximaPaga ? AppColors.magenta : AppColors.laranja;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(
            proximaPaga ? Icons.toll_outlined : Icons.event_available_outlined,
            color: cor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              proximaPaga
                  ? 'Você já usou suas sessões grátis. A próxima sai por $custo PoleCoins.'
                  : 'Você já usou $usadas de $limite sessões grátis neste ciclo.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: cor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Grade de horários ────────────────────────────────────────────────────

  Widget _buildGradeHorarios() {
    final ocupados = _slotsOcupados;
    final passados = _slotsPassados;
    final bloqueado = _setorLotado;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTurno(
          'Manhã',
          _todosSlots.take(16).toList(),
          ocupados,
          passados,
          bloqueado,
        ),
        const SizedBox(height: 16),
        _buildTurno(
          'Tarde',
          _todosSlots.skip(16).toList(),
          ocupados,
          passados,
          bloqueado,
        ),
      ],
    );
  }

  Widget _buildTurno(
    String label,
    List<String> slots,
    Set<String> ocupados,
    Set<String> passados,
    bool bloqueado,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: slots.map((slot) {
            final ocupado = ocupados.contains(slot);
            final passado = passados.contains(slot);
            final selecionado = slot == _horarioSelecionado;
            final disponivel = !ocupado && !passado && !bloqueado;

            Color bgColor;
            Color txtColor;
            BoxBorder? border;

            if (selecionado) {
              bgColor = AppColors.laranja;
              txtColor = Colors.white;
              border = null;
            } else if (ocupado || passado || bloqueado) {
              bgColor = Colors.grey.shade100;
              txtColor = Colors.grey.shade400;
              border = null;
            } else {
              bgColor = Colors.white;
              txtColor = Colors.black87;
              border = Border.all(color: Colors.grey.shade200);
            }

            return GestureDetector(
              onTap: disponivel
                  ? () => setState(() => _horarioSelecionado = slot)
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                  border: border,
                  boxShadow: selecionado
                      ? [
                          BoxShadow(
                            color: AppColors.laranja.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  slot,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight:
                        selecionado ? FontWeight.w700 : FontWeight.w500,
                    color: txtColor,
                    decoration: passado
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Botão agendar ────────────────────────────────────────────────────────

  Widget _buildBotaoAgendar() {
    final habilitado = _horarioSelecionado != null && !_salvando;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: habilitado ? _agendar : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.laranja,
          disabledBackgroundColor: Colors.grey.shade200,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: habilitado ? 4 : 0,
          shadowColor: AppColors.laranja.withOpacity(0.4),
        ),
        child: _salvando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                _horarioSelecionado == null
                    ? 'Selecione um horário'
                    : 'Confirmar às $_horarioSelecionado',
                style: GoogleFonts.poppins(
                  color: habilitado ? Colors.white : Colors.grey.shade400,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
      ),
    );
  }

  // ── Lista de agendados no dia ─────────────────────────────────────────────

  Widget _buildListaAgendados() {
    // ✅ mostra todos que não cancelaram
    final lista = _agendamentosDoDia
        .where((a) => a.status != 'CANCELADO')
        .toList();

    if (lista.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            'Nenhum agendamento neste dia ainda.',
            style: GoogleFonts.poppins(
              color: Colors.grey.shade500,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Column(
      children: lista.map((a) {
        final souEu = a.colaboradorId == _api.colaboradorAtual?.id;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: souEu
                ? Border.all(color: AppColors.laranja.withOpacity(0.4))
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar com horário
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: souEu
                      ? AppColors.laranja.withOpacity(0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      a.horario.substring(0, 5),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: souEu
                            ? AppColors.laranja
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            a.nomeColaborador,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (souEu) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.laranja.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'você',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: AppColors.laranja,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        if (souEu &&
                            a.status == 'AGENDADO' &&
                            _podeCancelar(a)) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: _salvando ? null : _cancelar,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.red.shade200, width: 1),
                              ),
                              child: Text(
                                'Desmarcar',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Dentro do Column do Expanded, após o Text do setor:
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            a.setor,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (a.status == 'VEIO') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Text(
                              '✓ atendido',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        if (a.status == 'NAO_VEIO') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              '✗ faltou',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );
  }

  String _formatarData(String data) {
    final p = data.split('-');
    if (p.length != 3) return data;
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  String _nomeDiaSemana(int weekday) {
    const nomes = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM'];
    return nomes[weekday - 1];
  }
}