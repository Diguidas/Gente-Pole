import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/multi_select_chip_field.dart';

const _corRequisitantes = Color(0xFF0EA5E9);

/// Tela do gestor: pra cada função que existe entre as pessoas abaixo dele
/// (nos setores que ele cuida), mostra quem é o(s) requisitante(s) de vaga
/// atribuído(s) — pode trocar (remover um e adicionar outro) e também
/// associar requisitante pra um setor+função que ele cuida mas que ainda
/// não tem ninguém atribuído. Mesma tabela `vaga_requisitantes` que a tela
/// equivalente do gentepole_admin gerencia.
class RequisitantesScreen extends StatefulWidget {
  const RequisitantesScreen({super.key});

  @override
  State<RequisitantesScreen> createState() => _RequisitantesScreenState();
}

class _RequisitantesScreenState extends State<RequisitantesScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _erro;
  List<String> _setores = [];
  List<({String setor, String funcao})> _pares = [];
  Map<String, List<Map<String, dynamic>>> _requisitantesPorPar = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  String _chave(String setor, String funcao) => '$setor|||$funcao';

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final colab = _api.colaboradorAtual;
      if (colab == null) {
        setState(() {
          _erro = 'Perfil de colaborador não encontrado.';
          _loading = false;
        });
        return;
      }
      final setores = await _api.buscarSetoresEfetivosDoGestor();
      final equipe = await _api.buscarEquipeGestorMultiSetor(setores,
          responsavelId: int.tryParse(colab.id.toString()));

      final paresSet = <String>{};
      final pares = <({String setor, String funcao})>[];
      for (final c in equipe) {
        final setor = c['setor'] as String?;
        final cargo = c['cargo'] as String?;
        if (setor == null || setor.isEmpty || cargo == null || cargo.isEmpty) continue;
        final chave = _chave(setor, cargo);
        if (paresSet.add(chave)) pares.add((setor: setor, funcao: cargo));
      }
      pares.sort((a, b) {
        final s = a.setor.compareTo(b.setor);
        return s != 0 ? s : a.funcao.compareTo(b.funcao);
      });

      final requisitantesPorPar = <String, List<Map<String, dynamic>>>{};
      for (final p in pares) {
        final lista = await _api.listarRequisitantesVaga(setor: p.setor, funcao: p.funcao);
        requisitantesPorPar[_chave(p.setor, p.funcao)] = lista;
      }

      if (!mounted) return;
      setState(() {
        _setores = setores;
        _pares = pares;
        _requisitantesPorPar = requisitantesPorPar;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro: $e';
        _loading = false;
      });
    }
  }

  Future<void> _remover(Map<String, dynamic> r) async {
    await _api.removerRequisitanteVaga(r['id'] as int);
    _carregar();
  }

  Future<void> _adicionar({String? setorFixo, String? funcaoFixa}) async {
    final colab = _api.colaboradorAtual;
    if (colab == null) return;
    final adicionou = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogAssociarRequisitante(
        setoresPermitidos: _setores,
        setorFixo: setorFixo,
        funcaoFixa: funcaoFixa,
        atribuidoPorId: int.tryParse(colab.id.toString()),
      ),
    );
    if (adicionou == true) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _corRequisitantes,
        foregroundColor: Colors.white,
        title: Text('Requisitantes de Vagas',
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () => _adicionar(),
            icon: const Icon(Icons.add),
            tooltip: 'Associar requisitante',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Text(_erro!,
                      style: GoogleFonts.poppins(color: AppColors.cinzaTexto)))
              : _pares.isEmpty
                  ? Center(
                      child: Text('Nenhuma função encontrada na sua equipe ainda.',
                          style: GoogleFonts.poppins(color: AppColors.cinzaTexto)))
                  : RefreshIndicator(
                      onRefresh: _carregar,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _pares.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final p = _pares[i];
                          final requisitantes =
                              _requisitantesPorPar[_chave(p.setor, p.funcao)] ?? const [];
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.funcao,
                                            style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.dark)),
                                        Text(p.setor,
                                            style: GoogleFonts.poppins(
                                                fontSize: 12, color: AppColors.cinzaTexto)),
                                      ],
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () =>
                                        _adicionar(setorFixo: p.setor, funcaoFixa: p.funcao),
                                    icon: const Icon(Icons.add, size: 16),
                                    label: Text('Adicionar',
                                        style: GoogleFonts.poppins(
                                            fontSize: 12, fontWeight: FontWeight.w600)),
                                  ),
                                ]),
                                const SizedBox(height: 8),
                                if (requisitantes.isEmpty)
                                  Text('Nenhum requisitante atribuído ainda.',
                                      style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: AppColors.cinzaTexto,
                                          fontStyle: FontStyle.italic))
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: requisitantes
                                        .map((r) => Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: _corRequisitantes.withOpacity(0.08),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                      r['colaborador_nome'] as String? ?? '—',
                                                      style: GoogleFonts.poppins(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                          color: _corRequisitantes)),
                                                  const SizedBox(width: 6),
                                                  GestureDetector(
                                                    onTap: () => _remover(r),
                                                    child: Icon(Icons.close,
                                                        size: 14,
                                                        color: _corRequisitantes
                                                            .withOpacity(0.7)),
                                                  ),
                                                ],
                                              ),
                                            ))
                                        .toList(),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _DialogAssociarRequisitante extends StatefulWidget {
  final List<String> setoresPermitidos;
  final String? setorFixo;
  final String? funcaoFixa;
  final int? atribuidoPorId;
  const _DialogAssociarRequisitante({
    required this.setoresPermitidos,
    this.setorFixo,
    this.funcaoFixa,
    required this.atribuidoPorId,
  });

  @override
  State<_DialogAssociarRequisitante> createState() => _DialogAssociarRequisitanteState();
}

class _DialogAssociarRequisitanteState extends State<_DialogAssociarRequisitante> {
  final _api = ApiService();
  final _buscaColabCtrl = TextEditingController();
  List<Map<String, dynamic>> _opcoesColab = [];
  Map<String, dynamic>? _colabSelecionado;

  bool get _paresFixos => widget.setorFixo != null && widget.funcaoFixa != null;

  final Set<String> _setoresSelecionados = {};
  final Map<String, List<String>> _funcoesPorSetor = {};
  final Set<String> _funcoesSelecionadas = {};
  bool _carregandoFuncoes = false;

  List<String> get _funcoesDisponiveis {
    final todas = <String>{};
    for (final setor in _setoresSelecionados) {
      todas.addAll(_funcoesPorSetor[setor] ?? const []);
    }
    final lista = todas.toList()..sort();
    return lista;
  }

  bool _enviando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    if (_paresFixos) {
      _setoresSelecionados.add(widget.setorFixo!);
      _funcoesSelecionadas.add(widget.funcaoFixa!);
      _funcoesPorSetor[widget.setorFixo!] = [widget.funcaoFixa!];
    }
  }

  @override
  void dispose() {
    _buscaColabCtrl.dispose();
    super.dispose();
  }

  Future<void> _selecionarSetores(Set<String> setores) async {
    setState(() {
      _setoresSelecionados
        ..clear()
        ..addAll(setores);
    });
    final faltantes = setores.where((s) => !_funcoesPorSetor.containsKey(s)).toList();
    if (faltantes.isNotEmpty) {
      setState(() => _carregandoFuncoes = true);
      for (final setor in faltantes) {
        _funcoesPorSetor[setor] = await _api.listarFuncoesTemplateDoSetor(setor);
      }
      if (!mounted) return;
      setState(() => _carregandoFuncoes = false);
    }
    setState(() => _funcoesSelecionadas.removeWhere((f) => !_funcoesDisponiveis.contains(f)));
  }

  Future<void> _buscarColab(String q) async {
    if (q.trim().length < 2) {
      setState(() => _opcoesColab = []);
      return;
    }
    final res = await _api.buscarColaboradoresFeed(q.trim());
    if (!mounted) return;
    setState(() => _opcoesColab = res);
  }

  Future<void> _enviar() async {
    if (_colabSelecionado == null || _setoresSelecionados.isEmpty || _funcoesSelecionadas.isEmpty) {
      setState(() => _erro = 'Preencha colaborador, setor(es) e função(ões).');
      return;
    }
    final linhas = <({int colaboradorId, String setor, String funcao, int? atribuidoPorId})>[];
    for (final setor in _setoresSelecionados) {
      for (final funcao in _funcoesSelecionadas) {
        if ((_funcoesPorSetor[setor] ?? const []).contains(funcao)) {
          linhas.add((
            colaboradorId: _colabSelecionado!['id'] as int,
            setor: setor,
            funcao: funcao,
            atribuidoPorId: widget.atribuidoPorId,
          ));
        }
      }
    }
    if (linhas.isEmpty) {
      setState(() => _erro = 'Nenhuma combinação válida de setor + função entre o que foi marcado.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await _api.adicionarRequisitantesVagaEmLote(linhas);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = 'Erro ao salvar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final setorTravado = widget.setorFixo != null;
    final funcaoTravada = widget.funcaoFixa != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Associar requisitante',
                    style: GoogleFonts.poppins(
                        fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark)),
                const SizedBox(height: 16),
                Text('Colaborador',
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.cinzaTexto)),
                const SizedBox(height: 6),
                if (_colabSelecionado != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                            '${_colabSelecionado!['nome']} · ${_colabSelecionado!['setor'] ?? ''}',
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _colabSelecionado = null),
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Trocar',
                      ),
                    ]),
                  )
                else ...[
                  TextField(
                    controller: _buscaColabCtrl,
                    onChanged: _buscarColab,
                    style: GoogleFonts.poppins(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nome...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                  ),
                  if (_opcoesColab.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      constraints: const BoxConstraints(maxHeight: 160),
                      decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(10)),
                      child: ListView(
                        shrinkWrap: true,
                        children: _opcoesColab
                            .map((c) => ListTile(
                                  dense: true,
                                  title: Text(c['nome'] as String,
                                      style: GoogleFonts.poppins(fontSize: 13)),
                                  subtitle: Text('${c['setor'] ?? ''} · ${c['cargo'] ?? ''}',
                                      style: GoogleFonts.poppins(fontSize: 11)),
                                  onTap: () => setState(() {
                                    _colabSelecionado = c;
                                    _opcoesColab = [];
                                    _buscaColabCtrl.clear();
                                  }),
                                ))
                            .toList(),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                Text(setorTravado ? 'Setor' : 'Setores',
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.cinzaTexto)),
                const SizedBox(height: 6),
                setorTravado
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                        child: Text(widget.setorFixo!, style: GoogleFonts.poppins(fontSize: 13)),
                      )
                    : MultiSelectChipField(
                        opcoes: widget.setoresPermitidos,
                        selecionados: _setoresSelecionados,
                        cor: _corRequisitantes,
                        hint: 'Toque para escolher os setores',
                        onChanged: (v) => _selecionarSetores(v),
                      ),
                const SizedBox(height: 12),
                Text(funcaoTravada ? 'Função (template de vaga)' : 'Funções (template de vaga)',
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.cinzaTexto)),
                const SizedBox(height: 6),
                funcaoTravada
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                        child: Text(widget.funcaoFixa!, style: GoogleFonts.poppins(fontSize: 13)),
                      )
                    : MultiSelectChipField(
                        opcoes: _funcoesDisponiveis,
                        selecionados: _funcoesSelecionadas,
                        carregando: _carregandoFuncoes,
                        habilitado: _setoresSelecionados.isNotEmpty,
                        cor: _corRequisitantes,
                        hint: _setoresSelecionados.isEmpty
                            ? 'Escolha o(s) setor(es) primeiro'
                            : 'Toque para escolher as funções',
                        onChanged: (v) => setState(() {
                          _funcoesSelecionadas
                            ..clear()
                            ..addAll(v);
                        }),
                      ),
                if (_erro != null) ...[
                  const SizedBox(height: 8),
                  Text(_erro!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.erro)),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _enviando ? null : _enviar,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _corRequisitantes, foregroundColor: Colors.white),
                    child: _enviando
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Associar'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
