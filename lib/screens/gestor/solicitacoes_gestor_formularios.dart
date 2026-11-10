import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';
import '../solicitacoes/solicitacoes_screen.dart'
    show CampoRotulado, SolicitacaoDialogShell, decoracaoCampo, formatarDataAdmissao;

/// Formulários do módulo Gestor (Solicitações e Facilites). Porta de
/// `solicitacoes_gestor_formularios.dart` do gentepole_admin — mesmos campos,
/// dropdowns/enums e payloads.
const _corGestor = AppColors.laranja;

/// Meses completos de empresa a partir de `data_admissao` (ISO). Null se não
/// houver data válida.
int? mesesDeEmpresa(ColaboradorModel c) {
  if (c.dataAdmissao == null) return null;
  final d = DateTime.tryParse(c.dataAdmissao!);
  if (d == null) return null;
  final now = DateTime.now();
  var meses = (now.year - d.year) * 12 + now.month - d.month;
  if (now.day < d.day) meses--;
  return meses < 0 ? 0 : meses;
}

/// Dropdown de colaborador da equipe do gestor, reaproveitado nos formulários
/// abaixo que precisam "escolher o colaborador".
class _DropdownColaboradorEquipe extends StatelessWidget {
  final List<ColaboradorModel> equipe;
  final ColaboradorModel? selecionado;
  final ValueChanged<ColaboradorModel?> onChanged;
  const _DropdownColaboradorEquipe(
      {required this.equipe, required this.selecionado, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ColaboradorModel>(
      value: selecionado,
      isExpanded: true,
      decoration: decoracaoCampo(),
      items: equipe
          .map((c) => DropdownMenuItem(
              value: c,
              child: Text('${c.nome} (${c.matricula})',
                  overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

Widget _botaoAnexo(String? nome, String vazio, IconData icone, VoidCallback onTap) {
  return OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icone, size: 18),
    label: Text(nome ?? vazio, overflow: TextOverflow.ellipsis),
    style: OutlinedButton.styleFrom(
      alignment: Alignment.centerLeft,
      minimumSize: const Size(double.infinity, 44),
      side: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
  );
}

// ─── Adesão de Benefício (exclusiva de líder) ──────────────────────────────

const _tiposBeneficio = {
  'alimentacao': 'Alimentação',
  'combustivel': 'Combustível',
  'ajuda_custo': 'Ajuda de Custo',
};

class DialogAdesaoBeneficio extends StatefulWidget {
  final ColaboradorModel gestor;
  final List<ColaboradorModel> equipe;
  final ApiService api;
  const DialogAdesaoBeneficio(
      {super.key, required this.gestor, required this.equipe, required this.api});

  @override
  State<DialogAdesaoBeneficio> createState() => _DialogAdesaoBeneficioState();
}

class _DialogAdesaoBeneficioState extends State<DialogAdesaoBeneficio> {
  ColaboradorModel? _colabAlvo;
  String? _tipo;
  final _valorCtrl = TextEditingController();
  final _justificativaCtrl = TextEditingController();
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _valorCtrl.dispose();
    _justificativaCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_colabAlvo == null ||
        _tipo == null ||
        _valorCtrl.text.trim().isEmpty ||
        _justificativaCtrl.text.trim().isEmpty) {
      setState(() => _erro = 'Preencha todos os campos.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.api.criarSolicitacao(
        tipo: 'adesao_beneficio',
        payload: {
          'Colaborador': _colabAlvo!.nome,
          'Matrícula': _colabAlvo!.matricula,
          'Cargo': _colabAlvo!.cargo,
          if (formatarDataAdmissao(_colabAlvo!.dataAdmissao) != null)
            'Data de admissão': formatarDataAdmissao(_colabAlvo!.dataAdmissao),
          'Tipo de benefício': _tiposBeneficio[_tipo],
          'Valor': _valorCtrl.text.trim(),
          'Justificativa': _justificativaCtrl.text.trim(),
        },
        abertoPorId: widget.gestor.id,
        abertoPorNome: widget.gestor.nome,
        abertoPorPapel: 'gestor',
        setor: widget.gestor.setor,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = 'Erro ao enviar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SolicitacaoDialogShell(
      titulo: 'Adesão de Benefício',
      cor: _corGestor,
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        CampoRotulado(
          label: 'Colaborador',
          child: _DropdownColaboradorEquipe(
              equipe: widget.equipe,
              selecionado: _colabAlvo,
              onChanged: (c) => setState(() => _colabAlvo = c)),
        ),
        CampoRotulado(
          label: 'Tipo de benefício',
          child: DropdownButtonFormField<String>(
            value: _tipo,
            isExpanded: true,
            decoration: decoracaoCampo(),
            items: _tiposBeneficio.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _tipo = v),
          ),
        ),
        CampoRotulado(
          label: 'Valor',
          child: TextField(
            controller: _valorCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: decoracaoCampo(hint: 'Ex: 250.00'),
          ),
        ),
        CampoRotulado(
          label: 'Justificativa',
          child: TextField(
              controller: _justificativaCtrl,
              maxLines: 3,
              decoration: decoracaoCampo()),
        ),
      ],
    );
  }
}

// ─── Móveis Administrativos ─────────────────────────────────────────────────

class DialogMoveisAdministrativos extends StatefulWidget {
  final ColaboradorModel gestor;
  final List<ColaboradorModel> equipe;
  final ApiService api;
  const DialogMoveisAdministrativos(
      {super.key, required this.gestor, required this.equipe, required this.api});

  @override
  State<DialogMoveisAdministrativos> createState() =>
      _DialogMoveisAdministrativosState();
}

class _DialogMoveisAdministrativosState
    extends State<DialogMoveisAdministrativos> {
  String _tipo = 'material';
  final _ordemInvestimentoCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  PlatformFile? _foto;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _ordemInvestimentoCtrl.dispose();
    _descricaoCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  Future<void> _escolherFoto() async {
    final resultado =
        await FilePicker.platform.pickFiles(withData: true, type: FileType.image);
    if (!mounted) return;
    if (resultado != null && resultado.files.isNotEmpty) {
      setState(() => _foto = resultado.files.first);
    }
  }

  Future<void> _enviar() async {
    if (_descricaoCtrl.text.trim().isEmpty) {
      setState(() => _erro = 'Descreva o pedido.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      String? fotoUrl;
      if (_foto != null) {
        fotoUrl = await widget.api.uploadAnexoSolicitacao(
            Uint8List.fromList(_foto!.bytes!), _foto!.name);
      }
      await widget.api.criarSolicitacao(
        tipo: 'moveis_administrativos',
        payload: {
          'Tipo de solicitação': _tipo == 'material' ? 'Material' : 'Serviço',
          'Ordem de investimento': _ordemInvestimentoCtrl.text.trim(),
          'Descrição': _descricaoCtrl.text.trim(),
          'Referência (link)': _linkCtrl.text.trim(),
          if (fotoUrl != null) 'Referência (foto)': fotoUrl,
        },
        abertoPorId: widget.gestor.id,
        abertoPorNome: widget.gestor.nome,
        abertoPorPapel: 'gestor',
        setor: widget.gestor.setor,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = 'Erro ao enviar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SolicitacaoDialogShell(
      titulo: 'Móveis Administrativos',
      cor: _corGestor,
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        CampoRotulado(
          label: 'Tipo de solicitação',
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'material', label: Text('Material')),
              ButtonSegment(value: 'servico', label: Text('Serviço')),
            ],
            selected: {_tipo},
            onSelectionChanged: (v) => setState(() => _tipo = v.first),
          ),
        ),
        CampoRotulado(
            label: 'Ordem de investimento',
            child: TextField(
                controller: _ordemInvestimentoCtrl, decoration: decoracaoCampo())),
        CampoRotulado(
            label: 'Descrição',
            child: TextField(
                controller: _descricaoCtrl,
                maxLines: 3,
                decoration: decoracaoCampo())),
        CampoRotulado(
            label: 'Referência (link)',
            child: TextField(
                controller: _linkCtrl,
                decoration: decoracaoCampo(hint: 'https://...'))),
        CampoRotulado(
          label: 'Referência (foto, opcional)',
          child: _botaoAnexo(
              _foto?.name, 'Escolher foto', Icons.image_outlined, _escolherFoto),
        ),
      ],
    );
  }
}

// ─── Swile ──────────────────────────────────────────────────────────────────

/// Aviso de prazo de envio/crédito exibido na abertura da solicitação —
/// o gestor precisa saber disso antes de mandar, já que solicitação feita
/// depois do dia 20 só vira crédito no mês seguinte ao esperado.
class _RegrasPrazoSwile extends StatelessWidget {
  const _RegrasPrazoSwile();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.push_pin_outlined,
                size: 14, color: Color(0xFFE11D48)),
            const SizedBox(width: 6),
            Text('Regras de Prazos de Envio',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark)),
          ]),
          const SizedBox(height: 8),
          _itemRegra('Combustível'),
          const SizedBox(height: 6),
          _itemRegra('Alimentação'),
        ],
      ),
    );
  }

  Widget _itemRegra(String beneficio) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5, right: 8),
          child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                  color: AppColors.dark, shape: BoxShape.circle)),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.dark, height: 1.4),
              children: [
                TextSpan(
                    text: '$beneficio\n',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: 'Envio até o dia '),
                const TextSpan(
                    text: '20 de cada mês',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' → Crédito disponível em '),
                const TextSpan(
                    text: '01 do mês seguinte',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class DialogSwile extends StatefulWidget {
  final ColaboradorModel gestor;
  final List<ColaboradorModel> equipe;
  final ApiService api;
  const DialogSwile(
      {super.key, required this.gestor, required this.equipe, required this.api});

  @override
  State<DialogSwile> createState() => _DialogSwileState();
}

class _DialogSwileState extends State<DialogSwile> {
  final Set<ColaboradorModel> _selecionados = {};
  // Carteira do benefício: escolha obrigatória, vale para toda a solicitação.
  String? _carteira;
  bool _enviando = false;
  String? _erro;

  Future<void> _enviar() async {
    if (_carteira == null) {
      setState(() => _erro = 'Selecione a carteira (Combustível ou Livre).');
      return;
    }
    if (_selecionados.isEmpty) {
      setState(() => _erro = 'Selecione ao menos um colaborador.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.api.criarSolicitacao(
        tipo: 'swile',
        payload: {
          'Carteira': _carteira,
          'Colaboradores':
              _selecionados.map((c) => '${c.nome} (${c.matricula})').join(', '),
        },
        abertoPorId: widget.gestor.id,
        abertoPorNome: widget.gestor.nome,
        abertoPorPapel: 'gestor',
        setor: widget.gestor.setor,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = 'Erro ao enviar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SolicitacaoDialogShell(
      titulo: 'Solicitar Swile',
      cor: _corGestor,
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        const _RegrasPrazoSwile(),
        CampoRotulado(
          label: 'Carteira',
          child: DropdownButtonFormField<String>(
            value: _carteira,
            isExpanded: true,
            decoration: decoracaoCampo(hint: 'Selecione a carteira'),
            items: const ['Combustível', 'Livre']
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _carteira = v),
          ),
        ),
        CampoRotulado(
          label: 'Matrículas dos colaboradores',
          child: Container(
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10)),
            child: widget.equipe.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Nenhum colaborador na sua equipe.',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.cinzaTexto)),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: widget.equipe
                        .map((c) => CheckboxListTile(
                              dense: true,
                              value: _selecionados.contains(c),
                              title: Text('${c.nome} (${c.matricula})',
                                  style: GoogleFonts.poppins(fontSize: 13)),
                              onChanged: (v) => setState(() => v == true
                                  ? _selecionados.add(c)
                                  : _selecionados.remove(c)),
                            ))
                        .toList(),
                  ),
          ),
        ),
      ],
    );
  }
}

// ─── Uber ───────────────────────────────────────────────────────────────────

const _trajetosUber = [
  'Evento/Reunião Externa - Casa',
  'Casa - Evento/Reunião Externa',
  'Evento/Reunião Externa - Trabalho',
  'Trabalho - Evento/Reunião Externa',
  'Trabalho - Trabalho',
  'Casa - Trabalho',
  'Trabalho - Casa',
  'Encomenda Flash',
  'Evento Marketing/Trade',
  'Aeroporto - Pole Piauí',
  'Pole Piauí - Aeroporto',
  'Casa - Aeroporto',
  'Aeroporto - Casa',
  'Granja - Filial',
  'Filial - Granja',
  'Granja - Casa',
  'Casa - Granja',
];

class DialogUber extends StatefulWidget {
  final ColaboradorModel gestor;
  final List<ColaboradorModel> equipe;
  final ApiService api;

  /// Rota que originou este Uber (escolha "Uber Flash"): pré-preenche o
  /// formulário com os dados da rota e registra o vínculo no pedido.
  final Map<String, dynamic>? rotaOrigem;
  const DialogUber(
      {super.key,
      required this.gestor,
      required this.equipe,
      required this.api,
      this.rotaOrigem});

  @override
  State<DialogUber> createState() => _DialogUberState();
}

// Tipo de campo pedido para cada ponta (partida/destino) do trajeto.
enum _TipoPonta { unidade, aeroporto, endereco }

class _DialogUberState extends State<DialogUber> {
  DateTime _data = DateTime.now();
  final _diasAtivosCtrl = TextEditingController();
  ColaboradorModel? _passageiro;
  final _emailUberCtrl = TextEditingController();
  String? _trajeto;
  List<Map<String, dynamic>> _filiais = [];
  bool _carregandoFiliais = true;
  String? _unidadePartida;
  String? _unidadeDestino;
  final _enderecoPartidaCtrl = TextEditingController();
  final _enderecoDestinoCtrl = TextEditingController();
  final _centroCustoCtrl = TextEditingController();
  // 'comum' = corridas pontuais (com prazo); 'fixo' = Uber ativo em tempo integral.
  String _modo = 'comum';
  final _justificativaFixoCtrl = TextEditingController();
  bool _aceiteFixo = false;
  final _obsCtrl = TextEditingController();
  bool _enviando = false;
  String? _erro;

  /// Uber Flash escolhido numa rota: traz data, solicitante, trajeto
  /// "Encomenda Flash" (partida/destino livres), endereços e centro de custo.
  void _preencherDaRota() {
    final rota = widget.rotaOrigem;
    if (rota == null) return;
    final p = (rota['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    String t(String k) => (p[k] ?? '').toString();

    final partes = t('Data da rota').split('/');
    if (partes.length == 3) {
      final d = int.tryParse(partes[0]),
          m = int.tryParse(partes[1]),
          a = int.tryParse(partes[2]);
      if (d != null && m != null && a != null) _data = DateTime(a, m, d);
    }
    _diasAtivosCtrl.text = '1';
    final mat = t('Matrícula');
    for (final c in widget.equipe) {
      if (c.matricula == mat) _passageiro = c;
    }
    _trajeto = 'Encomenda Flash';
    _enderecoPartidaCtrl.text = t('Local de saída');
    _enderecoDestinoCtrl.text = t('Local de destino');
    _centroCustoCtrl.text = t('Centro de custo');
    final tarefa = t('Descrição da tarefa');
    _obsCtrl.text =
        'Uber Flash da rota nº ${rota['id']}${tarefa.isEmpty ? '' : ' — $tarefa'}';
  }

  @override
  void initState() {
    super.initState();
    _preencherDaRota();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final filiais = await widget.api.listarFiliais();
      if (!mounted) return;
      setState(() {
        _filiais = filiais;
        _carregandoFiliais = false;
      });
    });
  }

  @override
  void dispose() {
    _diasAtivosCtrl.dispose();
    _emailUberCtrl.dispose();
    _enderecoPartidaCtrl.dispose();
    _enderecoDestinoCtrl.dispose();
    _centroCustoCtrl.dispose();
    _justificativaFixoCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  // "A - B" vira duas pontas; um trajeto sem hífen (Encomenda Flash, Evento
  // Marketing/Trade) pede partida e destino livres, os dois genéricos.
  (String, String) get _pontas {
    if (_trajeto == null) return ('', '');
    final partes = _trajeto!.split(' - ');
    if (partes.length == 2) return (partes[0], partes[1]);
    return (_trajeto!, _trajeto!);
  }

  _TipoPonta _tipoDaPonta(String ponta) {
    if (ponta.contains('Trabalho') || ponta == 'Filial') {
      return _TipoPonta.unidade;
    }
    if (ponta.contains('Aeroporto') ||
        ponta.contains('Pole Piauí') ||
        ponta == 'Granja') {
      return _TipoPonta.aeroporto;
    }
    return _TipoPonta.endereco;
  }

  Future<void> _enviar() async {
    if (_passageiro == null ||
        _emailUberCtrl.text.trim().isEmpty ||
        _trajeto == null ||
        _centroCustoCtrl.text.trim().isEmpty) {
      setState(() =>
          _erro = 'Preencha passageiro, e-mail, trajeto e centro de custo.');
      return;
    }
    final (partida, destino) = _pontas;
    final tipoPartida = _tipoDaPonta(partida);
    final tipoDestino = _tipoDaPonta(destino);
    if (tipoPartida == _TipoPonta.unidade && _unidadePartida == null) {
      setState(() => _erro = 'Selecione a unidade de partida.');
      return;
    }
    if (tipoDestino == _TipoPonta.unidade && _unidadeDestino == null) {
      setState(() => _erro = 'Selecione a unidade de destino.');
      return;
    }
    if (tipoPartida == _TipoPonta.endereco &&
        _enderecoPartidaCtrl.text.trim().isEmpty) {
      setState(() => _erro = 'Informe o endereço de partida.');
      return;
    }
    if (tipoDestino == _TipoPonta.endereco &&
        _enderecoDestinoCtrl.text.trim().isEmpty) {
      setState(() => _erro = 'Informe o endereço de destino.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final dataStr =
          '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}';
      final dias = int.tryParse(_diasAtivosCtrl.text.trim());
      String descreverPonta(_TipoPonta tipo, String ponta, String? unidade,
          TextEditingController enderecoCtrl) {
        return switch (tipo) {
          _TipoPonta.unidade => 'Unidade: ${unidade ?? ''}',
          _TipoPonta.aeroporto => ponta,
          _TipoPonta.endereco => enderecoCtrl.text.trim(),
        };
      }

      await widget.api.criarSolicitacao(
        tipo: 'uber',
        payload: {
          'Data da corrida': dataStr,
          'Dias ativos para solicitar': _diasAtivosCtrl.text.trim(),
          'Passageiro': '${_passageiro!.nome} (${_passageiro!.matricula})',
          'E-mail Uber do passageiro': _emailUberCtrl.text.trim(),
          'Trajeto': _trajeto,
          'Partida': descreverPonta(
              tipoPartida, partida, _unidadePartida, _enderecoPartidaCtrl),
          'Destino': descreverPonta(
              tipoDestino, destino, _unidadeDestino, _enderecoDestinoCtrl),
          'Centro de custo solicitante': _centroCustoCtrl.text.trim(),
          'Observação': _obsCtrl.text.trim(),
          if (widget.rotaOrigem != null)
            'Rota de origem':
                'Rota nº ${widget.rotaOrigem!['id']} (escolha: Uber Flash)',
        },
        abertoPorId: widget.gestor.id,
        abertoPorNome: widget.gestor.nome,
        abertoPorPapel: 'gestor',
        setor: widget.gestor.setor,
        colunasExtras: {
          if (dias != null && dias > 0)
            'prazo_fim': _data
                .add(Duration(days: dias))
                .toIso8601String()
                .substring(0, 10),
        },
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = 'Erro ao enviar: $e';
      });
    }
  }

  Future<void> _enviarFixo() async {
    if (_passageiro == null ||
        _emailUberCtrl.text.trim().isEmpty ||
        _centroCustoCtrl.text.trim().isEmpty ||
        _justificativaFixoCtrl.text.trim().isEmpty) {
      setState(() => _erro =
          'Preencha colaborador, e-mail Uber, centro de custo e justificativa.');
      return;
    }
    if (!_aceiteFixo) {
      setState(() => _erro =
          'Marque que você entende e aceita o Uber fixo em tempo integral.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.api.criarSolicitacao(
        tipo: 'uber_fixo',
        payload: {
          'Colaborador': '${_passageiro!.nome} (${_passageiro!.matricula})',
          'E-mail Uber do colaborador': _emailUberCtrl.text.trim(),
          'Centro de custo solicitante': _centroCustoCtrl.text.trim(),
          'Justificativa': _justificativaFixoCtrl.text.trim(),
          'Aceite':
              'O gestor entende e aceita que o Uber ficará ativo para este colaborador em tempo integral, até solicitar o cancelamento.',
        },
        abertoPorId: widget.gestor.id,
        abertoPorNome: widget.gestor.nome,
        abertoPorPapel: 'gestor',
        setor: widget.gestor.setor,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = 'Erro ao enviar: $e';
      });
    }
  }

  Widget _campoPonta(String label, String ponta, String? unidadeSelecionada,
      ValueChanged<String?> onUnidade, TextEditingController enderecoCtrl) {
    final tipo = _tipoDaPonta(ponta);
    switch (tipo) {
      case _TipoPonta.unidade:
        return CampoRotulado(
          label: 'Unidade ($label)',
          child: _carregandoFiliais
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : DropdownButtonFormField<String>(
                  value: unidadeSelecionada,
                  isExpanded: true,
                  decoration: decoracaoCampo(),
                  items: _filiais
                      .map((f) => DropdownMenuItem(
                          value: f['nome'] as String,
                          child: Text(f['nome'] as String)))
                      .toList(),
                  onChanged: onUnidade,
                ),
        );
      case _TipoPonta.aeroporto:
        return CampoRotulado(
          label: label,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10)),
            child: Text(ponta,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.cinzaTexto)),
          ),
        );
      case _TipoPonta.endereco:
        return CampoRotulado(
            label: 'Endereço de $label',
            child: TextField(
                controller: enderecoCtrl, decoration: decoracaoCampo()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SolicitacaoDialogShell(
      titulo: 'Solicitar Uber',
      cor: _corGestor,
      erro: _erro,
      enviando: _enviando,
      onEnviar: _modo == 'fixo' ? _enviarFixo : _enviar,
      campos: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'comum', label: Text('Comum')),
            ButtonSegment(value: 'fixo', label: Text('Fixo')),
          ],
          selected: {_modo},
          onSelectionChanged: (v) => setState(() {
            _modo = v.first;
            _erro = null;
          }),
        ),
        const SizedBox(height: 12),
        if (_modo == 'fixo') ...[
          CampoRotulado(
            label: 'Colaborador',
            child: _DropdownColaboradorEquipe(
                equipe: widget.equipe,
                selecionado: _passageiro,
                onChanged: (c) => setState(() => _passageiro = c)),
          ),
          CampoRotulado(
              label: 'E-mail do colaborador cadastrado na Uber',
              child: TextField(
                  controller: _emailUberCtrl, decoration: decoracaoCampo())),
          CampoRotulado(
              label: 'Centro de custo solicitante',
              child: TextField(
                  controller: _centroCustoCtrl, decoration: decoracaoCampo())),
          CampoRotulado(
              label: 'Justificativa',
              child: TextField(
                  controller: _justificativaFixoCtrl,
                  maxLines: 3,
                  decoration: decoracaoCampo())),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _aceiteFixo,
            onChanged: (v) => setState(() => _aceiteFixo = v ?? false),
            title: Text(
              'Entendo e aceito que o Uber ficará ativo para este colaborador em tempo integral, até eu solicitar o cancelamento.',
              style: GoogleFonts.poppins(fontSize: 12),
            ),
          ),
        ] else ...[
          Row(children: [
            Expanded(
              child: CampoRotulado(
                label: 'Data da corrida',
                child: OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: _data,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (d != null) setState(() => _data = d);
                  },
                  child: Text(
                      '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CampoRotulado(
                label: 'Dias ativos p/ solicitar',
                child: TextField(
                    controller: _diasAtivosCtrl,
                    keyboardType: TextInputType.number,
                    decoration: decoracaoCampo(hint: 'Ex: 5')),
              ),
            ),
          ]),
          CampoRotulado(
            label: 'Passageiro',
            child: _DropdownColaboradorEquipe(
                equipe: widget.equipe,
                selecionado: _passageiro,
                onChanged: (c) => setState(() => _passageiro = c)),
          ),
          CampoRotulado(
              label: 'E-mail do passageiro cadastrado na Uber',
              child: TextField(
                  controller: _emailUberCtrl, decoration: decoracaoCampo())),
          CampoRotulado(
            label: 'Trajeto',
            child: DropdownButtonFormField<String>(
              value: _trajeto,
              isExpanded: true,
              decoration: decoracaoCampo(),
              items: _trajetosUber
                  .map((t) => DropdownMenuItem(
                      value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() {
                _trajeto = v;
                _unidadePartida = null;
                _unidadeDestino = null;
              }),
            ),
          ),
          if (_trajeto != null) ...[
            Builder(builder: (_) {
              final (partida, destino) = _pontas;
              return Column(children: [
                _campoPonta('partida', partida, _unidadePartida,
                    (v) => setState(() => _unidadePartida = v), _enderecoPartidaCtrl),
                _campoPonta('destino', destino, _unidadeDestino,
                    (v) => setState(() => _unidadeDestino = v), _enderecoDestinoCtrl),
              ]);
            }),
          ],
          CampoRotulado(
              label: 'Centro de custo solicitante',
              child: TextField(
                  controller: _centroCustoCtrl, decoration: decoracaoCampo())),
          CampoRotulado(
              label: 'Observação',
              child: TextField(
                  controller: _obsCtrl,
                  maxLines: 2,
                  decoration: decoracaoCampo())),
        ],
      ],
    );
  }
}

// ─── Adiantamento de 13º ────────────────────────────────────────────────────

/// Aviso de prazo exibido na abertura da solicitação — pedido só até o dia
/// 10, com depósito no dia 15 do mesmo mês da solicitação.
class _RegrasPrazoAdiantamento13 extends StatelessWidget {
  const _RegrasPrazoAdiantamento13();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.push_pin_outlined,
                size: 14, color: Color(0xFFE11D48)),
            const SizedBox(width: 6),
            Text('Regras de Prazo',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark)),
          ]),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.dark, height: 1.4),
              children: const [
                TextSpan(text: 'Solicitação até o dia '),
                TextSpan(
                    text: '10', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' → Depósito no dia '),
                TextSpan(
                    text: '15', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' do mesmo mês da solicitação.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DialogAdiantamento13 extends StatefulWidget {
  final ColaboradorModel gestor;
  final List<ColaboradorModel> equipe;
  final ApiService api;
  const DialogAdiantamento13(
      {super.key, required this.gestor, required this.equipe, required this.api});

  @override
  State<DialogAdiantamento13> createState() => _DialogAdiantamento13State();
}

class _DialogAdiantamento13State extends State<DialogAdiantamento13> {
  ColaboradorModel? _colabAlvo;
  bool _enviando = false;
  String? _erro;

  /// Só quem já tem 6 meses ou mais de empresa pode pedir adiantamento de 13º.
  List<ColaboradorModel> get _equipeElegivel =>
      widget.equipe.where((c) => (mesesDeEmpresa(c) ?? 0) >= 6).toList();

  Future<void> _enviar() async {
    if (_colabAlvo == null) {
      setState(() => _erro = 'Selecione o colaborador.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.api.criarSolicitacao(
        tipo: 'adiantamento_13',
        payload: {
          'Colaborador': _colabAlvo!.nome,
          'Matrícula': _colabAlvo!.matricula,
          'Cargo': _colabAlvo!.cargo,
          if (formatarDataAdmissao(_colabAlvo!.dataAdmissao) != null)
            'Data de admissão': formatarDataAdmissao(_colabAlvo!.dataAdmissao),
        },
        abertoPorId: widget.gestor.id,
        abertoPorNome: widget.gestor.nome,
        abertoPorPapel: 'gestor',
        setor: widget.gestor.setor,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = 'Erro ao enviar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SolicitacaoDialogShell(
      titulo: 'Adiantamento de 13º',
      cor: _corGestor,
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        const _RegrasPrazoAdiantamento13(),
        if (_equipeElegivel.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10)),
            child: Text(
              'Nenhum colaborador da sua equipe já tem 6 meses ou mais de empresa — o adiantamento de 13º só pode ser solicitado depois de completar 6 meses de admissão.',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.cinzaTexto),
            ),
          )
        else
          CampoRotulado(
            label: 'Colaborador',
            child: _DropdownColaboradorEquipe(
                equipe: _equipeElegivel,
                selecionado: _colabAlvo,
                onChanged: (c) => setState(() => _colabAlvo = c)),
          ),
      ],
    );
  }
}
