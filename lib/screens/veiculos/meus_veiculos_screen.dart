import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/veiculo_model.dart';
import '../../services/api_service.dart';

/// "Meus Veículos" — o colaborador cadastra os próprios carros/motos, usados
/// na portaria e no estacionamento. Mesma tabela `veiculos` da tela de
/// Portaria no painel web; aqui cada um só vê e mexe nos seus.
class MeusVeiculosScreen extends StatefulWidget {
  const MeusVeiculosScreen({super.key});

  @override
  State<MeusVeiculosScreen> createState() => _MeusVeiculosScreenState();
}

class _MeusVeiculosScreenState extends State<MeusVeiculosScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<VeiculoModel> _veiculos = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final colaborador = _api.colaboradorAtual;
    final veiculos =
        colaborador != null ? await _api.listarMeusVeiculos(colaborador.id) : <VeiculoModel>[];
    if (!mounted) return;
    setState(() {
      _veiculos = veiculos;
      _loading = false;
    });
  }

  Future<void> _abrirFormulario() async {
    final colaborador = _api.colaboradorAtual;
    if (colaborador == null) return;
    final salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormularioVeiculoSheet(colaboradorId: colaborador.id),
    );
    if (salvo == true) _carregar();
  }

  Future<void> _excluir(VeiculoModel v) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remover veículo'),
        content: Text('Remover a placa ${v.placa}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await _api.excluirVeiculo(v.id);
      _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao remover: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        title: const Text('Meus Veículos'),
        backgroundColor: AppColors.laranja,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _abrirFormulario,
        backgroundColor: AppColors.laranja,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _veiculos.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Você ainda não cadastrou nenhum veículo.',
                        style: TextStyle(color: Colors.black54)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _veiculos.length,
                  itemBuilder: (_, i) => _cardVeiculo(_veiculos[i]),
                ),
    );
  }

  Widget _cardVeiculo(VeiculoModel v) {
    final icone = v.tipo == 'moto' ? Icons.two_wheeler_outlined : Icons.directions_car_outlined;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Icon(icone, color: AppColors.laranja, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.placa, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(
                  [v.tipoLabel, if (v.modelo?.isNotEmpty == true) v.modelo, if (v.cor?.isNotEmpty == true) v.cor]
                      .join(' · '),
                  style: const TextStyle(color: Colors.black54, fontSize: 12.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _excluir(v),
          ),
        ],
      ),
    );
  }
}

class _FormularioVeiculoSheet extends StatefulWidget {
  final int colaboradorId;
  const _FormularioVeiculoSheet({required this.colaboradorId});

  @override
  State<_FormularioVeiculoSheet> createState() => _FormularioVeiculoSheetState();
}

class _FormularioVeiculoSheetState extends State<_FormularioVeiculoSheet> {
  final _api = ApiService();
  final _placaCtrl = TextEditingController();
  final _modeloCtrl = TextEditingController();
  final _corCtrl = TextEditingController();
  final _tipoOutroCtrl = TextEditingController();
  String _tipo = 'carro';
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _placaCtrl.dispose();
    _modeloCtrl.dispose();
    _corCtrl.dispose();
    _tipoOutroCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_placaCtrl.text.trim().isEmpty) {
      setState(() => _erro = 'Informe a placa.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await _api.criarVeiculo(
        placa: _placaCtrl.text,
        tipo: _tipo,
        tipoOutro: _tipoOutroCtrl.text.trim(),
        modelo: _modeloCtrl.text.trim(),
        cor: _corCtrl.text.trim(),
        colaboradorId: widget.colaboradorId,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _erro = 'Erro ao salvar: $e';
        _salvando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            20,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Adicionar veículo', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
              items: tiposVeiculo.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _tipo = v ?? 'carro'),
            ),
            if (_tipo == 'outro') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _tipoOutroCtrl,
                decoration: const InputDecoration(labelText: 'Qual tipo?', border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _placaCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Placa *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modeloCtrl,
              decoration: const InputDecoration(labelText: 'Modelo', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _corCtrl,
              decoration: const InputDecoration(labelText: 'Cor', border: OutlineInputBorder()),
            ),
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
                    backgroundColor: AppColors.laranja, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _salvando
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Salvar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
