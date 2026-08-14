import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../models/fisioterapia_model.dart';
import '../../services/api_service.dart';
import '../login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminFisioterapiaScreen
// Tela exclusiva do fisioterapeuta: agenda do dia dos seus casos ativos,
// marcar presença + evolução da sessão, e gerenciar exercícios do caso.
// ─────────────────────────────────────────────────────────────────────────────

class AdminFisioterapiaScreen extends StatefulWidget {
  final int fisioterapeutaId;
  final String nome;

  const AdminFisioterapiaScreen({
    super.key,
    required this.fisioterapeutaId,
    required this.nome,
  });

  @override
  State<AdminFisioterapiaScreen> createState() =>
      _AdminFisioterapiaScreenState();
}

class _AdminFisioterapiaScreenState extends State<AdminFisioterapiaScreen> {
  final _api = ApiService();

  DateTime _dataSelecionada = DateTime.now();
  bool _loading = true;
  List<FisioterapiaCaso> _casos = [];
  List<FisioterapiaSessao> _sessoes = [];

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
      final casos =
          await _api.listarMeusCasosFisioterapia(widget.fisioterapeutaId);
      final sessoes =
          await _api.listarSessoesPorCasos(casos.map((c) => c.id).toList());
      setState(() {
        _casos = casos;
        _sessoes = sessoes;
      });
    } catch (e) {
      debugPrint('Erro ao carregar fisioterapia: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mudarData(int dias) async {
    setState(() => _dataSelecionada = _dataSelecionada.add(Duration(days: dias)));
  }

  FisioterapiaCaso? _casoDe(FisioterapiaSessao s) {
    try {
      return _casos.firstWhere((c) => c.id == s.casoId);
    } catch (_) {
      return null;
    }
  }

  List<FisioterapiaSessao> get _sessoesDoDia {
    final alvo = _dataFormatada;
    return _sessoes.where((s) {
      final d = DateFormat('yyyy-MM-dd').format(s.data);
      return d == alvo && s.status != 'CANCELADO';
    }).toList()
      ..sort((a, b) => a.horario.compareTo(b.horario));
  }

  Future<void> _marcarPresenca(FisioterapiaSessao s, String status) async {
    final ok = await _api.atualizarSessaoFisioterapia(s.id, {'status': status});
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == 'VEIO'
              ? 'Presença confirmada.'
              : 'Ausência registrada.'),
          backgroundColor:
              status == 'VEIO' ? AppColors.sucesso : AppColors.erro,
        ),
      );
      _carregar();
    }
  }

  Future<void> _registrarEvolucao(FisioterapiaSessao s) async {
    final ctrl = TextEditingController(text: s.evolucao ?? '');
    final texto = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Evolução da sessão', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Descreva a evolução do paciente nesta sessão...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.magenta),
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (texto == null) return;

    final ok = await _api.atualizarSessaoFisioterapia(s.id, {'evolucao': texto});
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Evolução salva.'), backgroundColor: AppColors.sucesso),
      );
      _carregar();
    }
  }

  Future<void> _abrirExercicios(FisioterapiaCaso caso) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _ExerciciosCasoScreen(caso: caso)),
    );
  }

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
            child: const Icon(Icons.accessibility_new_rounded,
                size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Fisioterapia',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.dark)),
              Text(widget.nome,
                  style: const TextStyle(fontSize: 11, color: AppColors.cinzaTexto)),
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
              MaterialPageRoute(builder: (_) => const LoginScreen()),
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
          Container(
            color: AppColors.branco,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _mudarData(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: AppColors.cinzaTexto,
                ),
                Expanded(
                  child: Text(
                    _dataTitulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.dark),
                  ),
                ),
                IconButton(
                  onPressed: () => _mudarData(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: AppColors.cinzaTexto,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.magenta))
                : DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        Container(
                          color: AppColors.branco,
                          child: TabBar(
                            labelColor: AppColors.magenta,
                            unselectedLabelColor: AppColors.cinzaTexto,
                            indicatorColor: AppColors.magenta,
                            tabs: const [
                              Tab(text: 'Agenda do dia'),
                              Tab(text: 'Meus casos'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildAgenda(),
                              _buildCasos(),
                            ],
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

  Widget _buildAgenda() {
    final sessoes = _sessoesDoDia;
    if (sessoes.isEmpty) {
      return const _Vazio(
          icone: Icons.event_available_outlined, texto: 'Nenhuma sessão marcada para este dia.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: sessoes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final s = sessoes[i];
        final caso = _casoDe(s);
        return _SessaoCard(
          sessao: s,
          nomeColaborador: caso?.nomeColaborador ?? '—',
          patologia: caso?.patologia ?? '—',
          onVeio: () => _marcarPresenca(s, 'VEIO'),
          onNaoVeio: () => _marcarPresenca(s, 'NAO_VEIO'),
          onEvolucao: () => _registrarEvolucao(s),
        );
      },
    );
  }

  Widget _buildCasos() {
    if (_casos.isEmpty) {
      return const _Vazio(
          icone: Icons.folder_open_outlined, texto: 'Nenhum caso ativo no momento.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _casos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final c = _casos[i];
        return Container(
          decoration: BoxDecoration(
            color: AppColors.branco,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(14),
            title: Text(c.nomeColaborador ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${c.patologia}\n${c.setorColaborador ?? ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.cinzaTexto)),
            ),
            isThreeLine: true,
            trailing: TextButton.icon(
              onPressed: () => _abrirExercicios(c),
              icon: const Icon(Icons.fitness_center_rounded, size: 16),
              label: const Text('Exercícios'),
            ),
          ),
        );
      },
    );
  }
}

class _Vazio extends StatelessWidget {
  final IconData icone;
  final String texto;
  const _Vazio({required this.icone, required this.texto});

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
            child: Icon(icone, size: 40, color: AppColors.magenta),
          ),
          const SizedBox(height: 16),
          Text(texto,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.cinzaTexto)),
        ]),
      ),
    );
  }
}

class _SessaoCard extends StatelessWidget {
  final FisioterapiaSessao sessao;
  final String nomeColaborador;
  final String patologia;
  final VoidCallback onVeio;
  final VoidCallback onNaoVeio;
  final VoidCallback onEvolucao;

  const _SessaoCard({
    required this.sessao,
    required this.nomeColaborador,
    required this.patologia,
    required this.onVeio,
    required this.onNaoVeio,
    required this.onEvolucao,
  });

  Color get _statusColor => switch (sessao.status) {
        'VEIO' => AppColors.sucesso,
        'NAO_VEIO' => AppColors.erro,
        _ => AppColors.laranja,
      };

  String get _statusLabel => switch (sessao.status) {
        'VEIO' => 'Presente ✅',
        'NAO_VEIO' => 'Faltou ❌',
        _ => 'Pendente',
      };

  bool get _pendente => sessao.status == 'AGENDADO';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.branco,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: _pendente ? const Color(0xFFE2E8F0) : _statusColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientePrincipal,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(sessao.horario,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _statusColor.withOpacity(0.3)),
                ),
                child: Text(_statusLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _statusColor)),
              ),
            ]),
            const SizedBox(height: 12),
            Text(nomeColaborador,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.dark)),
            const SizedBox(height: 2),
            Text(patologia, style: const TextStyle(fontSize: 12, color: AppColors.cinzaTexto)),
            if (sessao.evolucao != null && sessao.evolucao!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(sessao.evolucao!, style: const TextStyle(fontSize: 12, color: AppColors.dark)),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEvolucao,
                  icon: const Icon(Icons.edit_note_rounded, size: 16, color: AppColors.magenta),
                  label: const Text('Evolução',
                      style: TextStyle(fontSize: 13, color: AppColors.magenta, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.magenta),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (_pendente) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onNaoVeio,
                    icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.erro),
                    label: const Text('Não veio',
                        style: TextStyle(fontSize: 13, color: AppColors.erro, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.erro),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onVeio,
                    icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                    label: const Text('Presente',
                        style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.sucesso,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Exercícios do caso — o fisioterapeuta adiciona/remove prescrições.
// ─────────────────────────────────────────────────────────────────────────────

class _ExerciciosCasoScreen extends StatefulWidget {
  final FisioterapiaCaso caso;
  const _ExerciciosCasoScreen({required this.caso});

  @override
  State<_ExerciciosCasoScreen> createState() => _ExerciciosCasoScreenState();
}

class _ExerciciosCasoScreenState extends State<_ExerciciosCasoScreen> {
  final _api = ApiService();
  List<FisioterapiaExercicio> _exercicios = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final lista = await _api.listarExerciciosFisioterapia(widget.caso.id);
    if (!mounted) return;
    setState(() {
      _exercicios = lista;
      _loading = false;
    });
  }

  Future<void> _adicionar() async {
    final descCtrl = TextEditingController();
    final freqCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Novo exercício'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: descCtrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Descrição', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: freqCtrl,
              decoration: const InputDecoration(
                  labelText: 'Frequência (ex: 3x por semana)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.magenta),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    if (ok != true || descCtrl.text.trim().isEmpty) return;

    final sucesso = await _api.criarExercicioFisioterapia(
      casoId: widget.caso.id,
      descricao: descCtrl.text.trim(),
      frequencia: freqCtrl.text.trim().isEmpty ? null : freqCtrl.text.trim(),
    );
    if (sucesso) _carregar();
  }

  Future<void> _excluir(FisioterapiaExercicio ex) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remover exercício'),
        content: Text(ex.descricao),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.erro),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    final sucesso = await _api.excluirExercicioFisioterapia(ex.id);
    if (sucesso) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        backgroundColor: AppColors.branco,
        elevation: 0,
        title: Text('Exercícios — ${widget.caso.nomeColaborador ?? ''}',
            style: const TextStyle(fontSize: 15, color: AppColors.dark)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.magenta,
        onPressed: _adicionar,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.magenta))
          : _exercicios.isEmpty
              ? const _Vazio(icone: Icons.fitness_center_outlined, texto: 'Nenhum exercício prescrito ainda.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: _exercicios.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final ex = _exercicios[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.branco,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ListTile(
                        title: Text(ex.descricao),
                        subtitle: ex.frequencia != null ? Text(ex.frequencia!) : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.erro),
                          onPressed: () => _excluir(ex),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
