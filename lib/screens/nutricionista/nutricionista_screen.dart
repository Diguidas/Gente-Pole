import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class NutricionistaAgendamentoModel {
  final int id;
  final int colaboradorId;
  final String nomeColaborador;
  final String matricula;
  final String setor;
  final String data;    // 'yyyy-MM-dd'
  final String horario; // 'HH:mm'
  final String status;  // AGENDADO | VEIO | NAO_VEIO | CANCELADO
  final String? observacao;
  final String? assinaturaUrl;
  final String criadoEm;

  NutricionistaAgendamentoModel({
    required this.id,
    required this.colaboradorId,
    required this.nomeColaborador,
    required this.matricula,
    required this.setor,
    required this.data,
    required this.horario,
    required this.status,
    this.observacao,
    this.assinaturaUrl,
    required this.criadoEm,
  });

  factory NutricionistaAgendamentoModel.fromJson(Map<String, dynamic> json) {
    final colab = json['colaboradores'] as Map<String, dynamic>? ?? {};
    return NutricionistaAgendamentoModel(
      id: json['id'] as int,
      colaboradorId: json['colaborador_id'] as int,
      nomeColaborador: colab['nome'] ?? '',
      matricula: colab['matricula'] ?? json['matricula'] ?? '',
      setor: colab['setor'] ?? '',
      data: (json['data'] as String).substring(0, 10),
      horario: (json['horario'] as String).substring(0, 5),
      status: json['status'] ?? 'AGENDADO',
      observacao: json['observacao'],
      assinaturaUrl: json['assinatura_url'] as String?,
      criadoEm: json['criado_em'] ?? '',
    );
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class NutricionistaScreen extends StatefulWidget {
  const NutricionistaScreen({super.key});

  @override
  State<NutricionistaScreen> createState() => _NutricionistaScreenState();
}

class _NutricionistaScreenState extends State<NutricionistaScreen> {
  final _api = ApiService();

  List<NutricionistaAgendamentoModel> _agendamentos = [];
  List<String> _diasDisponiveis = [];
  bool _loading = true;
  String? _erro;

  String? _dataSelecionada;
  String? _horarioSelecionado;
  bool _salvando = false;

  static const Color _cor = Color(0xFF10B981);

  NutricionistaAgendamentoModel? get _meuAgendamento {
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
        _api.buscarDiasDisponiveisNutricionista(),
        _api.buscarAgendamentosNutricionista(),
      ]);
      setState(() {
        _diasDisponiveis = resultados[0] as List<String>;
        _agendamentos =
            resultados[1] as List<NutricionistaAgendamentoModel>;
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

  // ── Slots ─────────────────────────────────────────────────────────────────

  List<String> get _todosSlots {
    final slots = <String>[];
    for (var h = 8; h < 12; h++) {
      for (var m = 0; m < 60; m += 30) {
        slots.add(
          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
        );
      }
    }
    for (var h = 13; h < 17; h++) {
      for (var m = 0; m < 60; m += 30) {
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
        .where((a) => a.data == _dataSelecionada && a.status != 'CANCELADO')
        .map((a) => a.horario)
        .toSet();
  }

  // Horário de Brasília (UTC-3, sem DST), independe do fuso do dispositivo
  static DateTime _brasilia() =>
      DateTime.now().toUtc().subtract(const Duration(hours: 3));

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

  List<NutricionistaAgendamentoModel> get _agendamentosDoDia {
    if (_dataSelecionada == null) return [];
    return _agendamentos
        .where((a) => a.data == _dataSelecionada)
        .toList()
      ..sort((a, b) => a.horario.compareTo(b.horario));
  }

  // ── Ações ─────────────────────────────────────────────────────────────────

  Future<void> _agendar() async {
    if (_dataSelecionada == null || _horarioSelecionado == null) return;
    if (_meuAgendamento != null) {
      _mostrarErro('Você já tem um agendamento neste dia.');
      return;
    }
    setState(() => _salvando = true);
    final ok = await _api.agendarNutricionista(
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
    final ok = await _api.cancelarNutricionista(agend.id);
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
        backgroundColor: _cor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 200,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(28)),
                    child: Image.asset(
                      'assets/nutricionista.png',
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
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nutricionista', style: AppTextStyles.tituloGrande),
                Text('Agende sua consulta',
                    style: AppTextStyles.corpoBranco
                        .copyWith(color: AppColors.cinzaTexto)),
              ],
            ),
          ),
          Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _erro != null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_erro!,
                                        style: GoogleFonts.poppins()),
                                    const SizedBox(height: 12),
                                    ElevatedButton(
                                      onPressed: _carregar,
                                      child: const Text('Tentar novamente'),
                                    ),
                                  ],
                                ),
                              )
                            : _buildConteudo(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildConteudo() {
    final meuAgend = _meuAgendamento;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner de agendamento ativo
          if (meuAgend != null && meuAgend.status == 'AGENDADO') ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: _cor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Você tem um agendamento',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: _cor,
                          ),
                        ),
                        Text(
                          '${_formatarData(meuAgend.data)} às ${meuAgend.horario}',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _cancelar,
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.poppins(
                        color: Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Seleção de datas
          _buildSectionLabel('Escolha um dia'),
          const SizedBox(height: 12),
          if (_diasDisponiveis.isEmpty)
            Text(
              'Nenhum dia disponível no momento.',
              style: GoogleFonts.poppins(
                  color: Colors.grey.shade500, fontSize: 13),
            )
          else
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _diasDisponiveis.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final dia = _diasDisponiveis[i];
                  final selecionado = dia == _dataSelecionada;
                  final dt = DateTime.parse(dia);
                  return GestureDetector(
                    onTap: () => setState(() {
                      _dataSelecionada = dia;
                      _horarioSelecionado = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 56,
                      decoration: BoxDecoration(
                        color: selecionado ? _cor : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _cor.withOpacity(selecionado ? 0.3 : 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _nomeDia(dt.weekday),
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: selecionado
                                  ? Colors.white70
                                  : Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dt.day.toString(),
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: selecionado
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 24),

          // Horários
          _buildSectionLabel('Horários disponíveis'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _todosSlots.map((slot) {
              final ocupado = _slotsOcupados.contains(slot);
              final passado = _slotsPassados.contains(slot);
              final bloqueado = ocupado || passado;
              final selecionado = slot == _horarioSelecionado;
              return GestureDetector(
                onTap: bloqueado || meuAgend != null
                    ? null
                    : () => setState(() => _horarioSelecionado = slot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selecionado
                        ? _cor
                        : bloqueado
                            ? Colors.grey.shade100
                            : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selecionado
                          ? _cor
                          : bloqueado
                              ? Colors.grey.shade200
                              : _cor.withOpacity(0.25),
                    ),
                  ),
                  child: Text(
                    slot,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selecionado
                          ? Colors.white
                          : bloqueado
                              ? Colors.grey.shade400
                              : Colors.black87,
                      decoration: passado
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Botão confirmar
          _buildBotaoAgendar(meuAgend != null),

          const SizedBox(height: 28),

          // Lista do dia
          _buildSectionLabel('Agendamentos do dia'),
          const SizedBox(height: 12),
          _buildListaAgendados(),
        ],
      ),
    );
  }

  Widget _buildBotaoAgendar(bool temAgend) {
    final habilitado = _horarioSelecionado != null && !_salvando && !temAgend;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: habilitado ? _agendar : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: habilitado ? _cor : Colors.grey.shade200,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          elevation: habilitado ? 4 : 0,
          shadowColor: _cor.withOpacity(0.4),
        ),
        child: _salvando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
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

  Widget _buildListaAgendados() {
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
                color: Colors.grey.shade500, fontSize: 13),
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
                ? Border.all(color: _cor.withOpacity(0.4))
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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: souEu
                      ? _cor.withOpacity(0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    a.horario.substring(0, 5),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: souEu ? _cor : Colors.grey.shade600,
                    ),
                  ),
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
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: _cor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'você',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: _cor,
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
                    Text(
                      a.setor,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
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

  String _nomeDia(int weekday) {
    const nomes = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM'];
    return nomes[weekday - 1];
  }
}