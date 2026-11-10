import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const modosChegadaVisitante = <String, String>{
  'a_pe': 'A pé',
  'carro': 'Carro',
  'moto': 'Moto',
};

const _statusVisitante = <String, String>{
  'agendado': 'Agendado',
  'chegou': 'Chegou',
  'cancelado': 'Cancelado',
  'nao_compareceu': 'Não compareceu',
};

/// Valida CPF (dígitos verificadores).
bool cpfValido(String texto) {
  final d = texto.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length != 11 || RegExp(r'^(\d)\1{10}$').hasMatch(d)) return false;
  int dv(int n) {
    var soma = 0;
    for (var i = 0; i < n; i++) {
      soma += int.parse(d[i]) * (n + 1 - i);
    }
    final r = (soma * 10) % 11;
    return r == 10 ? 0 : r;
  }

  return dv(9) == int.parse(d[9]) && dv(10) == int.parse(d[10]);
}

String formatarCpf(String cpf) {
  final d = cpf.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length != 11) return cpf;
  return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
}

/// Máscara 000.000.000-00.
class _CpfFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue antigo, TextEditingValue novo) {
    var d = novo.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length > 11) d = d.substring(0, 11);
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 3 || i == 6) b.write('.');
      if (i == 9) b.write('-');
      b.write(d[i]);
    }
    final t = b.toString();
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

/// "Visitantes" — o colaborador (anfitrião) cadastra as visitas; a Portaria
/// consulta por CPF na recepção (tabela `visitantes_agendados`).
class VisitantesScreen extends StatefulWidget {
  const VisitantesScreen({super.key});

  @override
  State<VisitantesScreen> createState() => _VisitantesScreenState();
}

class _VisitantesScreenState extends State<VisitantesScreen> {
  final _api = ApiService();
  final _db = Supabase.instance.client;
  bool _loading = true;
  bool _tabelaAusente = false;
  List<Map<String, dynamic>> _visitas = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final id = _api.colaboradorAtual?.id;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await _db
          .from('visitantes_agendados')
          .select()
          .eq('colaborador_id', id)
          .order('data_visita', ascending: false);
      _visitas = (res as List).cast<Map<String, dynamic>>();
    } catch (_) {
      _tabelaAusente = true;
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  DateTime _data(Map<String, dynamic> v) => DateTime.parse(v['data_visita'] as String);

  bool _proxima(Map<String, dynamic> v) {
    final hoje = DateTime.now();
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    return v['status'] == 'agendado' && !_data(v).isBefore(h);
  }

  Future<void> _abrirFormulario({Map<String, dynamic>? existente}) async {
    final id = _api.colaboradorAtual?.id;
    if (id == null) return;
    final salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormularioVisitaSheet(colaboradorId: id, existente: existente),
    );
    if (salvo == true) _carregar();
  }

  Future<void> _cancelar(Map<String, dynamic> v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar visita'),
        content: Text('Cancelar a visita de ${v['nome']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Cancelar visita'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.from('visitantes_agendados').update({'status': 'cancelado'}).eq('id', v['id']);
      _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao cancelar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final proximas = _visitas.where(_proxima).toList()
      ..sort((a, b) => _data(a).compareTo(_data(b)));
    final passadas = _visitas.where((v) => !_proxima(v)).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        title: const Text('Visitantes'),
        backgroundColor: AppColors.laranja,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: _tabelaAusente
          ? null
          : FloatingActionButton(
              onPressed: () => _abrirFormulario(),
              backgroundColor: AppColors.laranja,
              child: const Icon(Icons.add, color: Colors.white),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tabelaAusente
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Este recurso ainda não está disponível.',
                        style: TextStyle(color: Colors.black54)),
                  ),
                )
              : _visitas.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Você ainda não cadastrou nenhuma visita.',
                            style: TextStyle(color: Colors.black54)),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                      children: [
                        _titulo('Próximas visitas'),
                        if (proximas.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text('Nenhuma visita agendada.', style: TextStyle(color: Colors.black54)),
                          ),
                        for (final v in proximas) _card(v),
                        if (passadas.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _titulo('Anteriores'),
                          for (final v in passadas) _card(v),
                        ],
                      ],
                    ),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      );

  Widget _card(Map<String, dynamic> v) {
    final agendado = v['status'] == 'agendado';
    final hoje = DateTime.now();
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    final editavel = agendado && _data(v).isAfter(h);
    final modo = v['modo_chegada'] as String? ?? 'a_pe';
    final detalhes = [
      DateFormat('dd/MM/yyyy').format(_data(v)) + ((v['horario'] ?? '').toString().isNotEmpty ? ' às ${v['horario']}' : ''),
      'CPF ${formatarCpf(v['cpf'] as String)}',
      if ((v['empresa_visitante'] ?? '').toString().isNotEmpty) v['empresa_visitante'],
      modosChegadaVisitante[modo] ?? modo,
      if ((v['placa'] ?? '').toString().isNotEmpty) v['placa'],
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.badge_outlined, color: AppColors.laranja, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v['nome'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(detalhes.join(' · '), style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
                if ((v['motivo'] ?? '').toString().isNotEmpty)
                  Text('Motivo: ${v['motivo']}', style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(_statusVisitante[v['status']] ?? '${v['status']}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: agendado ? AppColors.laranja : Colors.black45)),
              ],
            ),
          ),
          if (editavel)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar',
              onPressed: () => _abrirFormulario(existente: v),
            ),
          if (agendado)
            IconButton(
              icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
              tooltip: 'Cancelar visita',
              onPressed: () => _cancelar(v),
            ),
        ],
      ),
    );
  }
}

class _FormularioVisitaSheet extends StatefulWidget {
  final int colaboradorId;
  final Map<String, dynamic>? existente;
  const _FormularioVisitaSheet({required this.colaboradorId, this.existente});

  @override
  State<_FormularioVisitaSheet> createState() => _FormularioVisitaSheetState();
}

class _FormularioVisitaSheetState extends State<_FormularioVisitaSheet> {
  final _db = Supabase.instance.client;
  final _nome = TextEditingController();
  final _cpf = TextEditingController();
  final _empresa = TextEditingController();
  final _motivo = TextEditingController();
  final _placa = TextEditingController();
  final _modelo = TextEditingController();
  DateTime? _data;
  TimeOfDay? _hora;
  String _modo = 'a_pe';
  bool _salvando = false;
  String? _erro;
  // Nova visita: varios visitantes de uma vez; cada um vira uma linha em
  // visitantes_agendados (a Portaria confere por CPF).
  final List<({String nome, String cpf})> _visitantes = [];

  /// Move nome/CPF digitados para a lista. Devolve false (e mostra o erro)
  /// se faltar nome, o CPF for invalido ou ja estiver na lista.
  bool _adicionarVisitante() {
    final nome = _nome.text.trim();
    final cpf = _cpf.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (nome.isEmpty) {
      setState(() => _erro = 'Informe o nome do visitante.');
      return false;
    }
    if (!cpfValido(cpf)) {
      setState(() => _erro = 'CPF inválido.');
      return false;
    }
    if (_visitantes.any((v) => v.cpf == cpf)) {
      setState(() => _erro = 'Esse CPF já está na lista.');
      return false;
    }
    setState(() {
      _visitantes.add((nome: nome, cpf: cpf));
      _nome.clear();
      _cpf.clear();
      _erro = null;
    });
    return true;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    if (e != null) {
      _nome.text = e['nome'] ?? '';
      _cpf.text = formatarCpf(e['cpf'] ?? '');
      _empresa.text = e['empresa_visitante'] ?? '';
      _motivo.text = e['motivo'] ?? '';
      _placa.text = e['placa'] ?? '';
      _modelo.text = e['modelo_veiculo'] ?? '';
      _data = DateTime.tryParse(e['data_visita'] ?? '');
      _modo = (e['modo_chegada'] as String?) == 'outro' ? 'a_pe' : (e['modo_chegada'] ?? 'a_pe');
      final h = (e['horario'] ?? '').toString().split(':');
      if (h.length >= 2) _hora = TimeOfDay(hour: int.tryParse(h[0]) ?? 0, minute: int.tryParse(h[1]) ?? 0);
    }
  }

  @override
  void dispose() {
    for (final c in [_nome, _cpf, _empresa, _motivo, _placa, _modelo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _escolherData() async {
    final hoje = DateTime.now();
    final r = await showDatePicker(
      context: context,
      initialDate: _data ?? hoje,
      firstDate: DateTime(hoje.year, hoje.month, hoje.day),
      lastDate: hoje.add(const Duration(days: 365)),
    );
    if (r != null) setState(() => _data = r);
  }

  Future<void> _escolherHora() async {
    final r = await showTimePicker(context: context, initialTime: _hora ?? const TimeOfDay(hour: 9, minute: 0));
    if (r != null) setState(() => _hora = r);
  }

  Future<void> _salvar() async {
    final novo = widget.existente == null;
    if (novo) {
      // O que estiver digitado e ainda nao adicionado entra na lista.
      if (_nome.text.trim().isNotEmpty || _cpf.text.isNotEmpty) {
        if (!_adicionarVisitante()) return;
      }
      if (_visitantes.isEmpty) {
        return setState(() => _erro = 'Adicione pelo menos um visitante.');
      }
    } else {
      if (_nome.text.trim().isEmpty) return setState(() => _erro = 'Informe o nome do visitante.');
      if (!cpfValido(_cpf.text)) return setState(() => _erro = 'CPF inválido.');
    }
    if (_data == null) return setState(() => _erro = 'Informe a data da visita.');
    final veiculo = _modo != 'a_pe';
    if (veiculo && _placa.text.trim().isEmpty) return setState(() => _erro = 'Informe a placa.');
    setState(() {
      _salvando = true;
      _erro = null;
    });
    final dados = {
      'empresa_visitante': _empresa.text.trim(),
      'motivo': _motivo.text.trim(),
      'data_visita': DateFormat('yyyy-MM-dd').format(_data!),
      'horario': _hora == null
          ? null
          : '${_hora!.hour.toString().padLeft(2, '0')}:${_hora!.minute.toString().padLeft(2, '0')}',
      'modo_chegada': _modo,
      'placa': veiculo ? _placa.text.trim().toUpperCase() : null,
      'modelo_veiculo': veiculo ? _modelo.text.trim() : null,
    };
    try {
      if (widget.existente != null) {
        await _db.from('visitantes_agendados').update({
          ...dados,
          'nome': _nome.text.trim(),
          'cpf': _cpf.text.replaceAll(RegExp(r'[^0-9]'), ''),
        }).eq('id', widget.existente!['id']);
      } else {
        await _db.from('visitantes_agendados').insert([
          for (final v in _visitantes)
            {...dados, 'nome': v.nome, 'cpf': v.cpf, 'colaborador_id': widget.colaboradorId},
        ]);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _erro = 'Erro ao salvar: $e';
        _salvando = false;
      });
    }
  }

  InputDecoration _dec(String l) => InputDecoration(labelText: l, border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(left: 12, right: 12, top: 20, bottom: mq.viewInsets.bottom + mq.padding.bottom + 12),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existente != null ? 'Editar visita' : 'Nova visita',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              if (widget.existente == null && _visitantes.isNotEmpty) ...[
                Text('Visitantes (${_visitantes.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final v in _visitantes)
                    InputChip(
                      avatar: const Icon(Icons.person, size: 16, color: AppColors.laranja),
                      label: Text('${v.nome} · ${formatarCpf(v.cpf)}'),
                      onDeleted: () => setState(() => _visitantes.remove(v)),
                    ),
                ]),
                const SizedBox(height: 12),
              ],
              TextField(controller: _nome, textCapitalization: TextCapitalization.words, decoration: _dec('Nome do visitante *')),
              const SizedBox(height: 12),
              TextField(
                controller: _cpf,
                keyboardType: TextInputType.number,
                inputFormatters: [_CpfFormatter()],
                onSubmitted: (_) {
                  if (widget.existente == null) _adicionarVisitante();
                },
                decoration: _dec('CPF *'),
              ),
              if (widget.existente == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _adicionarVisitante,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Adicionar outro visitante'),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(controller: _empresa, decoration: _dec('Empresa do visitante')),
              const SizedBox(height: 12),
              TextField(controller: _motivo, decoration: _dec('Motivo da visita')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _escolherData,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(_data == null ? 'Data *' : DateFormat('dd/MM/yyyy').format(_data!)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _escolherHora,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_hora == null ? 'Horário' : _hora!.format(context)),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              const Text('Como virá?', style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 8,
                children: modosChegadaVisitante.entries
                    .map((e) => ChoiceChip(
                          label: Text(e.value),
                          selected: _modo == e.key,
                          selectedColor: AppColors.laranja.withOpacity(0.25),
                          onSelected: (_) => setState(() => _modo = e.key),
                        ))
                    .toList(),
              ),
              if (_modo != 'a_pe') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _placa,
                  textCapitalization: TextCapitalization.characters,
                  decoration: _dec('Placa *'),
                ),
                const SizedBox(height: 12),
                TextField(controller: _modelo, decoration: _dec('Modelo do veículo')),
              ],
              if (_erro != null) ...[
                const SizedBox(height: 10),
                Text(_erro!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _salvando ? null : _salvar,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.laranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _salvando
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Salvar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
