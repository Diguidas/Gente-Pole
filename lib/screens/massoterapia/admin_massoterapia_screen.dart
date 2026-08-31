import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/services.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';
import '../login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminMassoterapiaScreen
// Tela exclusiva para a massoterapeuta: lista agendamentos do dia e registra
// presença com assinatura digital.
// ─────────────────────────────────────────────────────────────────────────────

class AdminMassoterapiaScreen extends StatefulWidget {
  const AdminMassoterapiaScreen({super.key});

  @override
  State<AdminMassoterapiaScreen> createState() =>
      _AdminMassoterapiaScreenState();
}

class _AdminMassoterapiaScreenState extends State<AdminMassoterapiaScreen> {
  DateTime _dataSelecionada = DateTime.now();
  List<Map<String, dynamic>> _agendamentos = [];
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
      final lista =
          await ApiService().buscarAgendamentosData(_dataFormatada);
      if (mounted) setState(() => _agendamentos = lista);
    } catch (e) {
      debugPrint('Erro ao carregar agendamentos: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mudarData(int dias) async {
    setState(() => _dataSelecionada =
        _dataSelecionada.add(Duration(days: dias)));
    await _carregar();
  }

  Future<void> _abrirCalendario() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      locale: const Locale('pt', 'BR'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.magenta,
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

  // ── Registra NAO_VEIO diretamente ───────────────────────────────────────────
  Future<void> _marcarNaoVeio(Map<String, dynamic> ag) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmar ausência'),
        content: Text(
            '${ag['nome']} não compareceu à sessão de ${ag['horario'].toString().substring(0, 5)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.erro),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final ok = await ApiService().atualizarPresencaMassoterapia(
      id: ag['id'] as int,
      status: 'NAO_VEIO',
    );
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ausência registrada.'),
          backgroundColor: AppColors.erro,
        ),
      );
      _carregar();
    }
  }

  // ── Abre o modal de assinatura ───────────────────────────────────────────────
  /// [substituto] preenchido só no fluxo de substituição: quem assina de fato
  /// não é o colaborador do agendamento original.
  Future<void> _abrirAssinatura(
    Map<String, dynamic> ag, {
    ColaboradorModel? substituto,
  }) async {
    final assinaturaBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AssinaturaModal(
            nomeColaborador: substituto?.nome ?? ag['nome'] as String),
      ),
    );

    if (assinaturaBytes == null) return;

    // Faz upload da assinatura e atualiza status
    setState(() => _loading = true);
    try {
      final url = await ApiService().uploadAssinaturaMassoterapia(
        agendamentoId: ag['id'] as int,
        bytes: assinaturaBytes,
      );
      await ApiService().atualizarPresencaMassoterapia(
        id: ag['id'] as int,
        status: substituto != null ? 'ALTERADO' : 'VEIO',
        assinaturaUrl: url,
        substitutoColaboradorId: substituto?.id,
        substitutoNome: substituto?.nome,
        substitutoMatricula: substituto?.matricula,
        substitutoSetor: substituto?.setor,
        substitutoCargo: substituto?.cargo,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(substituto != null
                ? 'Substituição registrada e assinatura salva! ✅'
                : 'Presença confirmada e assinatura salva! ✅'),
            backgroundColor: AppColors.sucesso,
          ),
        );
      }
      _carregar();
    } catch (e) {
      debugPrint('Erro ao salvar assinatura: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao salvar. Tente novamente.'),
            backgroundColor: AppColors.erro,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Fluxo de substituição: pede a matrícula de quem foi de fato ──────────────
  Future<void> _abrirSubstituicao(Map<String, dynamic> ag) async {
    final matriculaCtrl = TextEditingController();
    final matricula = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Substituição'),
        content: TextField(
          controller: matriculaCtrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Matrícula de quem foi',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.magenta),
            onPressed: () => Navigator.pop(context, matriculaCtrl.text.trim()),
            child: const Text('Buscar'),
          ),
        ],
      ),
    );
    if (matricula == null || matricula.isEmpty || !mounted) return;

    final empresaAtual = ApiService().colaboradorAtual?.empresa;
    if (empresaAtual == null) return;
    final colaborador = await ApiService()
        .buscarColaboradorPorMatricula(matricula, empresaAtual);
    if (!mounted) return;
    if (colaborador == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Colaborador não encontrado para essa matrícula.'),
          backgroundColor: AppColors.erro,
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmar substituição'),
        content: Text(
          '${colaborador.nome}\n${colaborador.setor ?? '—'}\n\n'
          'Vai assinar no lugar de ${ag['nome']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.sucesso),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar e assinar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    await _abrirAssinatura(ag, substituto: colaborador);
  }

  // ── Contadores do dia ────────────────────────────────────────────────────────
  int get _totalDia => _agendamentos.length;
  int get _vieram =>
      _agendamentos.where((a) => a['status'] == 'VEIO').length;
  int get _naoVieram =>
      _agendamentos.where((a) => a['status'] == 'NAO_VEIO').length;
  int get _pendentes =>
      _agendamentos.where((a) => a['status'] == 'AGENDADO').length;
  int get _alterados =>
      _agendamentos.where((a) => a['status'] == 'ALTERADO').length;

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
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.spa_outlined, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Massoterapia',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
                ),
              ),
              Text(
                'Controle de presença',
                style: TextStyle(fontSize: 11, color: AppColors.cinzaTexto),
              ),
            ],
          ),
        ]),
        actions: [
          IconButton(
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.cinzaTexto),
            tooltip: 'Atualizar',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const _LoginRedirect()),
              (_) => false,
            ),
            icon: const Icon(Icons.logout_rounded, color: AppColors.cinzaTexto),
            tooltip: 'Sair',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── Seletor de data ────────────────────────────────────────────────
          _DateSelector(
            titulo: _dataTitulo,
            onAnterior: () => _mudarData(-1),
            onProximo: () => _mudarData(1),
            onCalendario: _abrirCalendario,
          ),

          // ── Cards de resumo ────────────────────────────────────────────────
          if (!_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _ResumoChip(
                      label: 'Total',
                      valor: _totalDia,
                      cor: AppColors.cinzaTexto),
                  const SizedBox(width: 8),
                  _ResumoChip(
                      label: 'Vieram',
                      valor: _vieram,
                      cor: AppColors.sucesso),
                  const SizedBox(width: 8),
                  _ResumoChip(
                      label: 'Faltaram',
                      valor: _naoVieram,
                      cor: AppColors.erro),
                  const SizedBox(width: 8),
                  _ResumoChip(
                      label: 'Alterados',
                      valor: _alterados,
                      cor: AppColors.magenta),
                  const SizedBox(width: 8),
                  _ResumoChip(
                      label: 'Pendentes',
                      valor: _pendentes,
                      cor: AppColors.laranja),
                ]),
              ),
            ),

          // ── Lista de agendamentos ──────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.magenta))
                : _agendamentos.isEmpty
                    ? _Vazio(data: _dataTitulo)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: _agendamentos.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _AgendamentoCard(
                          agendamento: _agendamentos[i],
                          onVeio: () => _abrirAssinatura(_agendamentos[i]),
                          onNaoVeio: () => _marcarNaoVeio(_agendamentos[i]),
                          onSubstituicao: () =>
                              _abrirSubstituicao(_agendamentos[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seletor de data
// ─────────────────────────────────────────────────────────────────────────────

class _DateSelector extends StatelessWidget {
  final String titulo;
  final VoidCallback onAnterior;
  final VoidCallback onProximo;
  final VoidCallback onCalendario;

  const _DateSelector({
    required this.titulo,
    required this.onAnterior,
    required this.onProximo,
    required this.onCalendario,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.branco,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: onAnterior,
            icon: const Icon(Icons.chevron_left_rounded),
            color: AppColors.cinzaTexto,
          ),
          Expanded(
            child: GestureDetector(
              onTap: onCalendario,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.calendar_today_outlined,
                      size: 14, color: AppColors.magenta),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onProximo,
            icon: const Icon(Icons.chevron_right_rounded),
            color: AppColors.cinzaTexto,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chip de resumo
// ─────────────────────────────────────────────────────────────────────────────

class _ResumoChip extends StatelessWidget {
  final String label;
  final int valor;
  final Color cor;

  const _ResumoChip(
      {required this.label, required this.valor, required this.cor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cor.withOpacity(0.25)),
        ),
        child: Column(children: [
          Text(
            '$valor',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: cor),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: cor.withOpacity(0.8))),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card de agendamento
// ─────────────────────────────────────────────────────────────────────────────

class _AgendamentoCard extends StatelessWidget {
  final Map<String, dynamic> agendamento;
  final VoidCallback onVeio;
  final VoidCallback onNaoVeio;
  final VoidCallback onSubstituicao;

  const _AgendamentoCard({
    required this.agendamento,
    required this.onVeio,
    required this.onNaoVeio,
    required this.onSubstituicao,
  });

  String get _horario =>
      (agendamento['horario'] as String).substring(0, 5);

  String get _status => agendamento['status'] as String? ?? 'AGENDADO';

  Color get _statusColor => switch (_status) {
        'VEIO' => AppColors.sucesso,
        'NAO_VEIO' => AppColors.erro,
        'ALTERADO' => AppColors.magenta,
        _ => AppColors.laranja,
      };

  String get _statusLabel => switch (_status) {
        'VEIO' => 'Presente ✅',
        'NAO_VEIO' => 'Faltou ❌',
        'ALTERADO' => 'Alterado 🔄',
        _ => 'Pendente',
      };

  String? get _substitutoNome => agendamento['substituto_nome'] as String?;
  String? get _substitutoMatricula =>
      agendamento['substituto_matricula'] as String?;

  bool get _pendente => _status == 'AGENDADO';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.branco,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _pendente
              ? const Color(0xFFE2E8F0)
              : _statusColor.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Linha superior: horário + badge status ─────────────────────
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientePrincipal,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _horario,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    _statusLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Nome e dados ───────────────────────────────────────────────
            Text(
              agendamento['nome'] as String? ?? '—',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark),
            ),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.business_outlined,
                  size: 13, color: AppColors.cinzaTexto),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  agendamento['setor'] as String? ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.cinzaTexto),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.badge_outlined,
                  size: 13, color: AppColors.cinzaTexto),
              const SizedBox(width: 4),
              Text(
                agendamento['matricula'] as String? ?? '—',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.cinzaTexto),
              ),
            ]),

            // ── Substituto (quando alterado) ────────────────────────────────
            if (_status == 'ALTERADO' && _substitutoNome != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.magenta.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.magenta.withOpacity(0.25)),
                ),
                child: Row(children: [
                  const Icon(Icons.sync_alt_rounded,
                      size: 14, color: AppColors.magenta),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Quem foi: $_substitutoNome'
                      '${_substitutoMatricula != null ? ' (mat. $_substitutoMatricula)' : ''}',
                      style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.magenta,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
            ],

            // ── Assinatura (se já veio ou foi alterado) ─────────────────────
            if ((_status == 'VEIO' || _status == 'ALTERADO') &&
                agendamento['assinatura_url'] != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.draw_outlined,
                    size: 13, color: AppColors.sucesso),
                const SizedBox(width: 4),
                Text('Assinatura registrada',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.sucesso,
                        fontWeight: FontWeight.w500)),
              ]),
            ],

            // ── Botões de ação (apenas se pendente) ────────────────────────
            if (_pendente) ...[
              const SizedBox(height: 14),
              Row(
                children: [
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
                      label: const Text('Atendido — assinar',
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
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onSubstituicao,
                  icon: const Icon(Icons.sync_alt_rounded,
                      size: 16, color: AppColors.magenta),
                  label: const Text('Substituição (foi outra pessoa)',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.magenta,
                          fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.magenta),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _Vazio extends StatelessWidget {
  final String data;
  const _Vazio({required this.data});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.magenta.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_available_outlined,
                size: 40, color: AppColors.magenta),
          ),
          const SizedBox(height: 16),
          const Text(
            'Nenhum agendamento',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.dark),
          ),
          const SizedBox(height: 6),
          Text(
            'Não há sessões marcadas para\n$data.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.cinzaTexto),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modal de assinatura digital
// ─────────────────────────────────────────────────────────────────────────────

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
    // Força landscape para a tela de assinatura
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Restaura portrait ao fechar
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
        const SnackBar(content: Text('Por favor, assine antes de confirmar.')),
      );
      return;
    }
    setState(() => _salvando = true);

    // Renderiza o canvas em PNG
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(600, 250);

    // Fundo branco
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    // Linhas da assinatura
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
        // Escala: o canvas de desenho tem o tamanho real do widget,
        // aqui normalizamos para 600×250
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
    final img = await picture.toImage(size.width.toInt(), size.height.toInt());
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
          child: Row(
            children: [
              // ── Área de assinatura (ocupa todo espaço disponível) ───────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cabeçalho
                    Row(children: [
                      const Icon(Icons.draw_outlined,
                          color: AppColors.magenta, size: 20),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Assinar presença',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.dark),
                          ),
                          Text(
                            widget.nomeColaborador,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.cinzaTexto),
                          ),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 10),

                    // Canvas de assinatura expandido
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
                          child: Stack(
                            children: [
                              // Linha de base sutil
                              Positioned(
                                bottom: 48,
                                left: 24,
                                right: 24,
                                child: Container(
                                  height: 1,
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              if (!_temAssinatura)
                                const Center(
                                  child: Text(
                                    'Assine aqui',
                                    style: TextStyle(
                                        fontSize: 16,
                                        color: Color(0xFFCBD5E1)),
                                  ),
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
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // ── Coluna de ações à direita ─────────────────────────────────
              SizedBox(
                width: 160,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Botão limpar
                    OutlinedButton.icon(
                      onPressed: _limpar,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Limpar'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        foregroundColor: AppColors.cinzaTexto,
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Botão cancelar
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

                    // Botão confirmar
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter da assinatura
// ─────────────────────────────────────────────────────────────────────────────

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

class _LoginRedirect extends StatelessWidget {
  const _LoginRedirect();

  @override
  Widget build(BuildContext context) => const LoginScreen();
}