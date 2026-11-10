import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_theme.dart';
import '../../models/veiculo_model.dart';
import '../../services/api_service.dart';

/// Modos de locomoção disponíveis (chave gravada em `colaborador_locomocao.modo`).
const modosLocomocao = <String, String>{
  'carro': 'Carro',
  'moto': 'Moto',
  'bicicleta': 'Bicicleta',
  'rota': 'Rota (fretado)',
  'transporte_publico': 'Transporte público',
  'uber': 'Uber/aplicativo',
  'carona': 'Carona',
  'a_pe': 'A pé',
  'outro': 'Outro',
};

const _iconesLocomocao = <String, IconData>{
  'carro': Icons.directions_car_outlined,
  'moto': Icons.two_wheeler_outlined,
  'bicicleta': Icons.pedal_bike_outlined,
  'rota': Icons.directions_bus_outlined,
  'transporte_publico': Icons.train_outlined,
  'uber': Icons.local_taxi_outlined,
  'carona': Icons.people_outline,
  'a_pe': Icons.directions_walk_outlined,
  'outro': Icons.more_horiz,
};

/// Campos de texto por modo: chave do JSON -> rótulo.
const _camposTexto = <String, Map<String, String>>{
  'rota': {'rota': 'Qual rota / ponto de embarque?'},
  'transporte_publico': {'linhas': 'Linhas / trajeto'},
  'uber': {'aplicativo': 'Aplicativo usado', 'desembarque': 'Ponto de desembarque'},
  'a_pe': {'observacao': 'Observação'},
  'outro': {'observacao': 'Observação'},
};

/// "Locomoção" — o colaborador informa como vai para a empresa (pode marcar
/// mais de uma opção, com ordem de prioridade). Carro/moto reaproveitam o
/// cadastro `veiculos`, que a Portaria continua lendo.
class LocomocaoScreen extends StatefulWidget {
  const LocomocaoScreen({super.key});

  @override
  State<LocomocaoScreen> createState() => _LocomocaoScreenState();
}

class _LocomocaoScreenState extends State<LocomocaoScreen> {
  final _api = ApiService();
  final _db = Supabase.instance.client;
  bool _loading = true;
  bool _salvando = false;
  bool _tabelaAusente = false;
  List<VeiculoModel> _veiculos = [];
  List<String> _ordem = []; // modos marcados, na ordem de prioridade
  final Map<String, int?> _veiculoPorModo = {};
  final Map<String, bool> _bicicletario = {};
  final Map<String, TextEditingController> _ctrls = {};
  // Caronas: cada item e {'id': colaborador_id?, 'nome': ...}. Sem id = nome manual.
  final List<Map<String, dynamic>> _caronas = [];

  int? get _colabId => _api.colaboradorAtual?.id;

  TextEditingController _ctrl(String modo, String campo) =>
      _ctrls.putIfAbsent('$modo.$campo', () => TextEditingController());

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    final id = _colabId;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      _veiculos = await _api.listarMeusVeiculos(id);
    } catch (_) {}
    try {
      final res = await _db
          .from('colaborador_locomocao')
          .select()
          .eq('colaborador_id', id)
          .order('prioridade');
      final linhas = (res as List).cast<Map<String, dynamic>>();
      _ordem = [];
      for (final l in linhas) {
        final modo = l['modo'] as String;
        if (!modosLocomocao.containsKey(modo)) continue;
        _ordem.add(modo);
        _veiculoPorModo[modo] = l['veiculo_id'] as int?;
        final det = (l['detalhes'] as Map?)?.cast<String, dynamic>() ?? {};
        _bicicletario[modo] = det['bicicletario'] == true;
        if (modo == 'carona') {
          final lista = det['caronas'];
          if (lista is List) {
            _caronas.addAll(lista.whereType<Map>().map((m) => m.cast<String, dynamic>()));
          } else if ((det['com_quem'] ?? '').toString().trim().isNotEmpty) {
            _caronas.add({'nome': det['com_quem'].toString().trim()});
          }
        }
        for (final campo in (_camposTexto[modo] ?? {}).keys) {
          _ctrl(modo, campo).text = (det[campo] ?? '').toString();
        }
      }
    } catch (_) {
      _tabelaAusente = true;
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _alternar(String modo, bool marcado) {
    setState(() {
      if (marcado) {
        if (!_ordem.contains(modo)) _ordem.add(modo);
      } else {
        _ordem.remove(modo);
      }
    });
  }

  Future<void> _cadastrarVeiculo(String modo) async {
    final id = _colabId;
    if (id == null) return;
    final placa = TextEditingController();
    final modelo = TextEditingController();
    final cor = TextEditingController();
    String? erro;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(modo == 'moto' ? 'Cadastrar moto' : 'Cadastrar carro'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: placa,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Placa *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: modelo,
              decoration: const InputDecoration(labelText: 'Modelo', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: cor,
              decoration: const InputDecoration(labelText: 'Cor', border: OutlineInputBorder()),
            ),
            if (erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(erro!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (placa.text.trim().isEmpty) {
                  setD(() => erro = 'Informe a placa.');
                  return;
                }
                try {
                  await _api.criarVeiculo(
                    placa: placa.text,
                    tipo: modo,
                    modelo: modelo.text.trim(),
                    cor: cor.text.trim(),
                    colaboradorId: id,
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  setD(() => erro = 'Erro ao salvar (placa já cadastrada?): $e');
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    placa.dispose();
    modelo.dispose();
    cor.dispose();
    if (ok == true) {
      final novos = await _api.listarMeusVeiculos(id);
      if (!mounted) return;
      setState(() {
        final antigos = _veiculos.map((v) => v.id).toSet();
        _veiculos = novos;
        final criado = novos.where((v) => !antigos.contains(v.id));
        if (criado.isNotEmpty) _veiculoPorModo[modo] = criado.first.id;
      });
    }
  }

  Future<void> _salvar() async {
    final id = _colabId;
    if (id == null) return;
    for (final m in _ordem) {
      if ((m == 'carro' || m == 'moto') && _veiculoPorModo[m] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Escolha ou cadastre o veículo para "${modosLocomocao[m]}".')),
        );
        return;
      }
    }
    setState(() => _salvando = true);
    try {
      final marcados = _ordem.toList();
      final existentes = await _db.from('colaborador_locomocao').select('modo').eq('colaborador_id', id);
      for (final e in (existentes as List)) {
        final m = e['modo'] as String;
        if (!marcados.contains(m)) {
          await _db.from('colaborador_locomocao').delete().eq('colaborador_id', id).eq('modo', m);
        }
      }
      if (marcados.isNotEmpty) {
        final linhas = <Map<String, dynamic>>[];
        for (var i = 0; i < marcados.length; i++) {
          final m = marcados[i];
          final det = <String, dynamic>{};
          if (m == 'bicicleta') det['bicicletario'] = _bicicletario[m] == true;
          if (m == 'carona' && _caronas.isNotEmpty) {
            det['caronas'] = _caronas;
            det['com_quem'] = _caronas.map((c) => c['nome']).join(', ');
          }
          for (final campo in (_camposTexto[m] ?? {}).keys) {
            final t = _ctrl(m, campo).text.trim();
            if (t.isNotEmpty) det[campo] = t;
          }
          linhas.add({
            'colaborador_id': id,
            'modo': m,
            'prioridade': i + 1,
            'veiculo_id': (m == 'carro' || m == 'moto') ? _veiculoPorModo[m] : null,
            'detalhes': det,
            'atualizado_em': DateTime.now().toIso8601String(),
          });
        }
        await _db.from('colaborador_locomocao').upsert(linhas, onConflict: 'colaborador_id,modo');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Locomoção salva!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    }
    if (mounted) setState(() => _salvando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        title: const Text('Locomoção'),
        backgroundColor: AppColors.laranja,
        foregroundColor: Colors.white,
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
              : _corpo(),
    );
  }

  Widget _corpo() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Como você vai para a empresa?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Pode marcar mais de uma opção.', style: TextStyle(color: Colors.black54, fontSize: 12.5)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: modosLocomocao.entries.map((e) {
            final sel = _ordem.contains(e.key);
            return FilterChip(
              avatar: Icon(_iconesLocomocao[e.key], size: 18, color: sel ? Colors.white : AppColors.laranja),
              label: Text(e.value),
              selected: sel,
              showCheckmark: false,
              selectedColor: AppColors.laranja,
              labelStyle: TextStyle(color: sel ? Colors.white : Colors.black87),
              onSelected: (v) => _alternar(e.key, v),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        for (final m in _ordem) _cardDetalhes(m),
        if (_ordem.length > 1) ...[
          const SizedBox(height: 8),
          const Text('Ordem de prioridade',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const Text('Arraste para reordenar: 1 é o principal.',
              style: TextStyle(color: Colors.black54, fontSize: 12.5)),
          const SizedBox(height: 8),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (a, b) => setState(() {
              if (b > a) b -= 1;
              _ordem.insert(b, _ordem.removeAt(a));
            }),
            children: [
              for (var i = 0; i < _ordem.length; i++)
                Card(
                  key: ValueKey(_ordem[i]),
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.laranja,
                      child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                    title: Text(modosLocomocao[_ordem[i]] ?? _ordem[i]),
                    trailing: const Icon(Icons.drag_handle),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
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
    );
  }

  Widget _cardDetalhes(String modo) {
    final filhos = <Widget>[];
    if (modo == 'carro' || modo == 'moto') {
      final lista = _veiculos.where((v) => v.tipo == modo).toList();
      final atual = _veiculoPorModo[modo];
      filhos.add(DropdownButtonFormField<int>(
        initialValue: lista.any((v) => v.id == atual) ? atual : null,
        decoration: InputDecoration(
            labelText: modo == 'moto' ? 'Qual moto?' : 'Qual carro?', border: const OutlineInputBorder()),
        items: lista
            .map((v) => DropdownMenuItem(
                value: v.id,
                child: Text([v.placa, if (v.modelo?.isNotEmpty == true) v.modelo!].join(' · '))))
            .toList(),
        onChanged: (v) => setState(() => _veiculoPorModo[modo] = v),
      ));
      filhos.add(Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _cadastrarVeiculo(modo),
          icon: const Icon(Icons.add, size: 18),
          label: Text(modo == 'moto' ? 'Cadastrar nova moto' : 'Cadastrar novo carro'),
        ),
      ));
    } else if (modo == 'carona') {
      filhos.add(_CaronaCampo(
        db: _db,
        meuId: _colabId,
        caronas: _caronas,
        onChanged: () => setState(() {}),
      ));
    } else if (modo == 'bicicleta') {
      filhos.add(SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Usa o bicicletário da empresa?'),
        value: _bicicletario[modo] == true,
        activeThumbColor: AppColors.laranja,
        onChanged: (v) => setState(() => _bicicletario[modo] = v),
      ));
    } else {
      for (final e in (_camposTexto[modo] ?? {}).entries) {
        if (filhos.isNotEmpty) filhos.add(const SizedBox(height: 10));
        filhos.add(TextField(
          controller: _ctrl(modo, e.key),
          decoration: InputDecoration(labelText: e.value, border: const OutlineInputBorder()),
        ));
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_iconesLocomocao[modo], color: AppColors.laranja, size: 22),
            const SizedBox(width: 8),
            Text(modosLocomocao[modo] ?? modo, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          ...filhos,
        ],
      ),
    );
  }
}

/// Campo "Com quem?" da carona: busca colaboradores por nome; escolher um (ou
/// digitar um nome fora da lista e tocar em Adicionar) poe a pessoa na lista.
class _CaronaCampo extends StatefulWidget {
  final SupabaseClient db;
  final int? meuId;
  final List<Map<String, dynamic>> caronas;
  final VoidCallback onChanged;
  const _CaronaCampo({
    required this.db,
    required this.meuId,
    required this.caronas,
    required this.onChanged,
  });

  @override
  State<_CaronaCampo> createState() => _CaronaCampoState();
}

class _CaronaCampoState extends State<_CaronaCampo> {
  final _ctrl = TextEditingController();
  final _foco = FocusNode();
  List<Map<String, dynamic>> _sugestoes = [];
  int _busca = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    _foco.dispose();
    super.dispose();
  }

  Future<void> _buscar(String texto) async {
    final termo = texto.trim();
    final ticket = ++_busca;
    if (termo.length < 2) {
      setState(() => _sugestoes = []);
      return;
    }
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted || ticket != _busca) return;
    try {
      final res = await widget.db
          .from('colaboradores')
          .select('id, nome, setor')
          .eq('demitido', false)
          .ilike('nome', '%$termo%')
          .order('nome')
          .limit(8);
      if (!mounted || ticket != _busca) return;
      setState(() => _sugestoes = (res as List).cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  bool _jaAdicionada(Map<String, dynamic> c) => widget.caronas.any((x) =>
      (c['id'] != null && x['id'] == c['id']) ||
      (x['nome'] ?? '').toString().toLowerCase() == (c['nome'] ?? '').toString().toLowerCase());

  void _adicionar(Map<String, dynamic> c) {
    if (!_jaAdicionada(c)) {
      widget.caronas.add(c);
      widget.onChanged();
    }
    _ctrl.clear();
    setState(() => _sugestoes = []);
    _foco.requestFocus();
  }

  void _adicionarDigitado() {
    final nome = _ctrl.text.trim();
    if (nome.isEmpty) return;
    final exata = _sugestoes.where((s) => (s['nome'] as String).toLowerCase() == nome.toLowerCase());
    _adicionar(exata.isNotEmpty
        ? {'id': exata.first['id'], 'nome': exata.first['nome']}
        : {'nome': nome});
  }

  @override
  Widget build(BuildContext context) {
    final sugestoes = _sugestoes
        .where((s) => s['id'] != widget.meuId)
        .where((s) => !_jaAdicionada({'id': s['id'], 'nome': s['nome']}))
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.caronas.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in widget.caronas)
              InputChip(
                avatar: Icon(c['id'] != null ? Icons.person : Icons.edit_outlined,
                    size: 16, color: AppColors.laranja),
                label: Text('${c['nome']}'),
                onDeleted: () {
                  widget.caronas.remove(c);
                  widget.onChanged();
                },
              ),
          ]),
        ),
      TextField(
        controller: _ctrl,
        focusNode: _foco,
        onChanged: _buscar,
        onSubmitted: (_) => _adicionarDigitado(),
        decoration: InputDecoration(
          labelText: 'Com quem? (digite o nome do colaborador)',
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'Adicionar',
            icon: const Icon(Icons.add_circle, color: AppColors.laranja),
            onPressed: _adicionarDigitado,
          ),
        ),
      ),
      if (sugestoes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final s in sugestoes)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline, size: 20),
                  title: Text('${s['nome']}', style: const TextStyle(fontSize: 13)),
                  subtitle: (s['setor'] ?? '').toString().isEmpty
                      ? null
                      : Text('${s['setor']}', style: const TextStyle(fontSize: 11)),
                  onTap: () => _adicionar({'id': s['id'], 'nome': s['nome']}),
                ),
            ]),
          ),
        ),
    ]);
  }
}
