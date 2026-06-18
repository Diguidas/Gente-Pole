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
  bool _loading = true;
  String? _erro;

  // Seleção do usuário
  String? _dataSelecionada;
  String? _horarioSelecionado;
  bool _salvando = false;

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
        _api.buscarConfigSetorMassoterapia(_api.colaboradorAtual?.setor ?? ''),
      ]);
      setState(() {
        _diasDisponiveis = resultados[0] as List<String>;
        _agendamentos = resultados[1] as List<MassoterapiaAgendamentoModel>;
        _configSetor = resultados[2] as MassoterapiaConfigSetorModel?;
        // Pré-seleciona o primeiro dia disponível
        if (_diasDisponiveis.isNotEmpty && _dataSelecionada == null) {
          _dataSelecionada = _diasDisponiveis.first;
        }
        _loading = false;
      });
    } catch (e) {
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

  Set<String> get _slotsOcupados {
    if (_dataSelecionada == null) return {};
    return _agendamentos
        .where(
          (a) => a.data == _dataSelecionada && a.status != 'CANCELADO',
        )
        .map((a) => a.horario)
        .toSet();
  }

  // Horário de Brasília (UTC-3, sem DST), independe do fuso do dispositivo
  static DateTime _brasilia() =>
      DateTime.now().toUtc().subtract(const Duration(hours: 3));

  /// Slots que já passaram no horário (só relevante se _dataSelecionada for hoje)
  Set<String> get _slotsPassados {
    if (_dataSelecionada == null) return {};
    final agora = _brasilia();
    final hojeStr =
        '${agora.year}-${agora.month.toString().padLeft(2, '0')}-${agora.day.toString().padLeft(2, '0')}';
    if (_dataSelecionada != hojeStr) return {};
    return _todosSlots.where((slot) {
      final partes = slot.split(':');
      final h = int.parse(partes[0]);
      final m = int.parse(partes[1]);
      return h < agora.hour || (h == agora.hour && m <= agora.minute);
    }).toSet();
  }

  List<MassoterapiaAgendamentoModel> get _agendamentosDoDia {
    if (_dataSelecionada == null) return [];
    return _agendamentos.where((a) => a.data == _dataSelecionada).toList()
      ..sort((a, b) => a.horario.compareTo(b.horario));
  }

  int get _vagasUsadasMeuSetor {
    final setor = _api.colaboradorAtual?.setor ?? '';
    if (_dataSelecionada == null) return 0;
    return _agendamentos
        .where(
          (a) =>
              a.data == _dataSelecionada &&
              a.setor == setor &&
              a.status != 'CANCELADO',
        ) // ← conta AGENDADO + VEIO + NAO_VEIO
        .length;
  }

  bool get _setorLotado {
    final vagas = _configSetor?.vagasDia ?? 999;
    return _vagasUsadasMeuSetor >= vagas;
  }

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

    setState(() => _salvando = true);

    final ok = await _api.agendarMassoterapia(
      data: _dataSelecionada!,
      horario: _horarioSelecionado!,
    );

    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      _mostrarSucesso(
        'Agendado para ${_formatarData(_dataSelecionada!)} às $_horarioSelecionado!',
      );
      _horarioSelecionado = null;
      await _carregar();
    } else {
      _mostrarErro('Não foi possível agendar. Tente outro horário.');
    }
  }

  Future<void> _cancelar() async {
    final agend = _meuAgendamento;
    if (agend == null) return;

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
      body: Stack(
        children: [
          Container(
            height: 220,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
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
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 24, 20),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Massoterapia',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Agende sua sessão de bem-estar',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 13,
                  ),
                ),
              ],
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
    if (_diasDisponiveis.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🗓️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              'Nenhum dia disponível\nno momento.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.grey.shade600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.laranja,
      onRefresh: _carregar,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner do meu agendamento
            if (_meuAgendamento != null) _buildMeuAgendamentoBanner(),
            if (_meuAgendamento != null) const SizedBox(height: 20),

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
          // Só mostra cancelar se ainda estiver AGENDADO
          if (a.status == 'AGENDADO')
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
            ),
        ],
      ),
    );
  }

  // ── Seletor de datas ─────────────────────────────────────────────────────

  Widget _buildSeletorDatas() {
    return SizedBox(
      height: 72,
      child: ListView.separated(
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
    final restam = total - usadas;
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
                  ? 'Seu setor não tem mais vagas hoje.'
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
                        if (souEu && a.status == 'AGENDADO') ...[
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
                              '✓ veio',
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