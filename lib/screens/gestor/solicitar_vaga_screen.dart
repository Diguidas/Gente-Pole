import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../models/vaga_model.dart';
import '../../services/api_service.dart';

class SolicitarVagaScreen extends StatefulWidget {
  const SolicitarVagaScreen({super.key});

  @override
  State<SolicitarVagaScreen> createState() => _SolicitarVagaScreenState();
}

class _SolicitarVagaScreenState extends State<SolicitarVagaScreen> {
  final _api = ApiService();

  // Etapa 1: picker de template
  List<Map<String, dynamic>> _templates = [];
  bool _carregandoTemplates = true;
  Map<String, dynamic>? _templateSelecionado;

  // Etapa 2: detalhes da requisição
  bool _ehSubstituicao = false;
  ColaboradorModel? _colaboradorSubstituido;
  List<ColaboradorModel> _equipe = [];
  bool _carregandoEquipe = false;
  final _motivoCtrl = TextEditingController();
  bool _enviando = false;

  // Novos campos
  int _quantidade = 1;
  TimeOfDay? _horarioEntrada;
  TimeOfDay? _horarioSaida;
  PlatformFile? _docAprovacao;

  // Campos da vaga
  final _centroCustoCtrl = TextEditingController();
  final _liderancaMatriculaCtrl = TextEditingController();
  List<Map<String, dynamic>> _filiais = [];
  String? _filialSelecionada;

  // Etapa 3: chamado de TI. null = ainda não respondido (obrigatório
  // responder Sim/Não em cada pergunta antes de poder enviar).
  bool _mostrarEtapa3 = false;
  bool? _abrirChamadoTI;
  bool? _precisaUsuarioRede;
  ColaboradorModel? _acessoIgualColaborador;
  bool? _precisaOffice365;
  bool? _precisaMaquina;
  final _observacaoTICtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarTemplates();
    _carregarFiliais();
  }

  @override
  void dispose() {
    _motivoCtrl.dispose();
    _centroCustoCtrl.dispose();
    _liderancaMatriculaCtrl.dispose();
    _observacaoTICtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarFiliais() async {
    try {
      final lista = await _api.listarFiliais();
      if (mounted) setState(() => _filiais = lista);
    } catch (e, st) {
      debugPrint('[FILIAIS] ERRO: $e\n$st');
    }
  }

  Future<void> _carregarTemplates() async {
    try {
      final setores = await _api.buscarSetoresEfetivosDoGestor();
      final lista = await _api.listarTemplatesGestor(
          setor: _api.colaboradorAtual?.setor, setores: setores);
      if (mounted) setState(() { _templates = lista; _carregandoTemplates = false; });
    } catch (_) {
      if (mounted) setState(() => _carregandoTemplates = false);
    }
  }

  List<ColaboradorModel> get _equipeDoSetorDaVaga {
    final setorVaga = _templateSelecionado?['departamento'] as String?;
    if (setorVaga == null || setorVaga.isEmpty) return _equipe;
    return _equipe.where((c) => c.setor == setorVaga).toList();
  }

  Future<void> _carregarEquipe() async {
    setState(() => _carregandoEquipe = true);
    try {
      final lista = await _api.buscarMinhaEquipe();
      if (mounted) setState(() { _equipe = lista; _carregandoEquipe = false; });
    } catch (_) {
      if (mounted) setState(() => _carregandoEquipe = false);
    }
  }

  void _selecionarTemplate(Map<String, dynamic> t) {
    setState(() {
      _templateSelecionado = t;
      _ehSubstituicao = false;
      _colaboradorSubstituido = null;
    });
  }

  void _voltarParaTemplates() {
    setState(() {
      _templateSelecionado = null;
      _ehSubstituicao = false;
      _colaboradorSubstituido = null;
      _motivoCtrl.clear();
      _quantidade = 1;
      _horarioEntrada = null;
      _horarioSaida = null;
      _docAprovacao = null;
      _filialSelecionada = null;
      _mostrarEtapa3 = false;
      _abrirChamadoTI = null;
      _precisaUsuarioRede = null;
      _acessoIgualColaborador = null;
      _precisaOffice365 = null;
      _precisaMaquina = null;
      _observacaoTICtrl.clear();
    });
  }

  void _onTipoAlterado(bool substituicao) {
    setState(() {
      _ehSubstituicao = substituicao;
      _colaboradorSubstituido = null;
    });
    if (substituicao && _equipe.isEmpty) _carregarEquipe();
  }

  bool get _podeEnviarEtapa3 {
    if (_abrirChamadoTI == null) return false;
    if (_abrirChamadoTI == false) return true;
    if (_precisaUsuarioRede == null) return false;
    if (_precisaUsuarioRede == true &&
        _acessoIgualColaborador == null &&
        _equipeDoSetorDaVaga.isNotEmpty) {
      return false;
    }
    if (_precisaOffice365 == null) return false;
    if (_precisaMaquina == null) return false;
    return true;
  }

  String _timeStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _enviar() async {
    final t = _templateSelecionado!;
    setState(() => _enviando = true);

    final motivo = _motivoCtrl.text.trim();
    String descricao = t['descricao'] as String? ?? '';
    if (motivo.isNotEmpty) {
      descricao += '${descricao.isNotEmpty ? '\n\n' : ''}Motivo: $motivo';
    }

    // Upload do documento se houver
    String? docUrl;
    if (!_ehSubstituicao && _docAprovacao != null) {
      final bytes = _docAprovacao!.bytes != null
          ? Uint8List.fromList(_docAprovacao!.bytes!)
          : null;
      if (bytes != null) {
        docUrl = await _api.uploadDocAprovacaoDiretoria(
          fileName: _docAprovacao!.name,
          bytes: bytes,
        );
      }
    }

    final vaga = VagaModel(
      id: 0,
      titulo: t['titulo'] as String,
      descricao: descricao.isEmpty ? null : descricao,
      departamento: t['departamento'] as String?,
      localidade: _api.colaboradorAtual?.setor,
      tipoContrato: t['tipo_contrato'] as String? ?? 'CLT',
      salarioAExibir: false,
      testePratico: t['teste_pratico'] as bool? ?? false,
      status: 'FECHADA',
      tipoVaga: _quantidade > 1 ? 'MULTIPLA' : (t['tipo_vaga'] as String? ?? 'UNICA'),
      requisitadoPorId: _api.colaboradorAtual?.id,
      statusRequisicao: 'AGUARDANDO_APROVACAO_RH',
      createdAt: DateTime.now(),
      templateId: t['id'] as int?,
      quantidadeVagas: _quantidade,
      horarioEntrada: _horarioEntrada != null ? _timeStr(_horarioEntrada!) : null,
      horarioSaida: _horarioSaida != null ? _timeStr(_horarioSaida!) : null,
      docAprovacaoUrl: docUrl,
      centroCusto: _centroCustoCtrl.text.trim().isEmpty ? null : _centroCustoCtrl.text.trim(),
      liderancaDiretaMatricula: _liderancaMatriculaCtrl.text.trim().isEmpty ? null : _liderancaMatriculaCtrl.text.trim(),
      filial: _filialSelecionada,
      colaboradorSubstituidoId: _ehSubstituicao ? _colaboradorSubstituido?.id : null,
    );

    final vagaId = await _api.solicitarVaga(vaga);
    if (vagaId != null && _abrirChamadoTI == true) {
      try {
        await _api.criarChamadoTIVaga(
          vagaId: vagaId,
          precisaUsuarioRede: _precisaUsuarioRede ?? false,
          acessoIgualColaboradorId:
              _precisaUsuarioRede == true ? _acessoIgualColaborador?.id : null,
          precisaOffice365: _precisaOffice365 ?? false,
          precisaMaquina: _precisaMaquina ?? false,
          observacao: _observacaoTICtrl.text.trim().isEmpty
              ? null
              : _observacaoTICtrl.text.trim(),
        );
      } catch (e, st) {
        // Vaga já foi criada; a falha em gravar o chamado de TI não deve
        // travar o fluxo do gestor. RH ainda vê a vaga normalmente.
        debugPrint('[CHAMADO_TI] ERRO ao criar chamado: $e\n$st');
      }
    }
    if (!mounted) return;
    setState(() => _enviando = false);

    if (vagaId != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Solicitação enviada! O RH será notificado. ✅',
            style: GoogleFonts.poppins()),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao enviar. Tente novamente.',
            style: GoogleFonts.poppins()),
        backgroundColor: AppColors.magenta,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 180,
            decoration: const BoxDecoration(gradient: AppColors.gradientePrincipal),
          ),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 24, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _mostrarEtapa3
                            ? () => setState(() => _mostrarEtapa3 = false)
                            : _templateSelecionado != null
                                ? _voltarParaTemplates
                                : () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _templateSelecionado == null
                                  ? 'Solicitar Vaga'
                                  : _mostrarEtapa3
                                      ? 'Chamado de TI'
                                      : 'Detalhes da Solicitação',
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700),
                            ),
                            Text(
                              _templateSelecionado == null
                                  ? 'Selecione o cargo'
                                  : _mostrarEtapa3
                                      ? 'Passo 3 de 3'
                                      : 'Passo 2 de 3',
                              style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: _templateSelecionado == null
                        ? _buildEtapa1()
                        : _mostrarEtapa3
                            ? _buildEtapa3()
                            : _buildEtapa2(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Etapa 1: Picker de template ───────────────────────────────────────────────

  Widget _buildEtapa1() {
    if (_carregandoTemplates) {
      return const Center(child: CircularProgressIndicator(color: AppColors.magenta));
    }
    if (_templates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined, size: 56, color: AppColors.cinzaTexto),
              const SizedBox(height: 16),
              Text('Nenhum cargo disponível',
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.dark)),
              const SizedBox(height: 6),
              Text('Peça ao RH para cadastrar os templates de cargo.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      itemCount: _templates.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Selecione o cargo da vaga',
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.cinzaTexto),
            ),
          );
        }
        return _cardTemplate(_templates[i - 1]);
      },
    );
  }

  Widget _cardTemplate(Map<String, dynamic> t) {
    final titulo = t['titulo'] as String? ?? '';
    final departamento = t['departamento'] as String? ?? '';
    final tipoContrato = t['tipo_contrato'] as String? ?? '';
    final tipoVaga = t['tipo_vaga'] as String? ?? 'UNICA';
    final testePratico = t['teste_pratico'] as bool? ?? false;

    return GestureDetector(
      onTap: () => _selecionarTemplate(t),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.laranja.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.work_outline_rounded, color: AppColors.laranja),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (departamento.isNotEmpty) _tag(departamento, const Color(0xFF6366F1)),
                      _tag(tipoContrato, AppColors.laranja),
                      if (tipoVaga == 'MULTIPLA') _tag('Múltiplas', const Color(0xFF10B981)),
                      if (testePratico) _tag('Teste prático', AppColors.magenta),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.cinzaTexto),
          ],
        ),
      ),
    );
  }

  // ── Etapa 2: Detalhes ─────────────────────────────────────────────────────────

  Widget _buildEtapa2() {
    final t = _templateSelecionado!;
    final titulo = t['titulo'] as String? ?? '';
    final departamento = t['departamento'] as String? ?? '';
    final tipoContrato = t['tipo_contrato'] as String? ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      children: [
        // Resumo do template selecionado (read-only)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.laranja.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.laranja.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.laranja.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.work_outline_rounded, color: AppColors.laranja, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark)),
                    if (departamento.isNotEmpty)
                      Text('$departamento · $tipoContrato',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: AppColors.cinzaTexto)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _voltarParaTemplates,
                child: Text('Trocar',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.magenta, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Tipo de requisição
        _secao('Tipo de requisição'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _botaoTipo(
                label: 'Nova vaga',
                icone: Icons.add_circle_outline_rounded,
                selecionado: !_ehSubstituicao,
                onTap: () => _onTipoAlterado(false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _botaoTipo(
                label: 'Substituição',
                icone: Icons.swap_horiz_rounded,
                selecionado: _ehSubstituicao,
                onTap: () => _onTipoAlterado(true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Picker de colaborador (só se substituição)
        if (_ehSubstituicao) ...[
          _secao('Quem será substituído?', obrigatorio: true),
          const SizedBox(height: 12),
          if (_carregandoEquipe)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: AppColors.magenta),
            ))
          else if (_equipeDoSetorDaVaga.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Nenhum colaborador encontrado no setor desta vaga.',
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: _colaboradorSubstituido != null
                      ? AppColors.magenta
                      : const Color(0xFFE5E7EB),
                  width: _colaboradorSubstituido != null ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: DropdownButtonHideUnderline(
                // Value é a matrícula, não o model inteiro — ColaboradorModel
                // não sobrescreve `==`, então usá-lo como value quebra o
                // dropdown silenciosamente se a equipe for recarregada
                // (mesmo bug já achado no dropdown de filial).
                child: DropdownButton<String>(
                  value: _colaboradorSubstituido?.matricula,
                  isExpanded: true,
                  hint: Text('Selecione...',
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: AppColors.cinzaTexto)),
                  items: _equipeDoSetorDaVaga.map((c) {
                    return DropdownMenuItem(
                      value: c.matricula,
                      child: Text(
                        c.cargo != null && c.cargo!.isNotEmpty
                            ? '${c.nome} – ${c.cargo}'
                            : c.nome,
                        style: GoogleFonts.poppins(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (matricula) => setState(() {
                    _colaboradorSubstituido = matricula == null
                        ? null
                        : _equipeDoSetorDaVaga
                            .firstWhere((c) => c.matricula == matricula);
                  }),
                ),
              ),
            ),
          const SizedBox(height: 20),
        ],

        // Quantidade de vagas
        _secao('Quantidade de vagas', obrigatorio: true),
        const SizedBox(height: 4),
        Text(
          'A vaga é encerrada automaticamente quando o número for atingido.',
          style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: _quantidade > 1
                    ? () => setState(() => _quantidade--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: AppColors.magenta,
                disabledColor: AppColors.cinzaTexto.withOpacity(0.3),
              ),
              Expanded(
                child: Text(
                  '$_quantidade',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _quantidade++),
                icon: const Icon(Icons.add_circle_outline_rounded),
                color: AppColors.magenta,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Horário
        _secao('Horário da vaga', obrigatorio: true),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _horarioPicker(
              label: 'Entrada',
              valor: _horarioEntrada,
              onSelecionado: (t) => setState(() => _horarioEntrada = t),
            )),
            const SizedBox(width: 12),
            Expanded(child: _horarioPicker(
              label: 'Saída',
              valor: _horarioSaida,
              onSelecionado: (t) => setState(() => _horarioSaida = t),
            )),
          ],
        ),
        const SizedBox(height: 20),

        // Documento de aprovação (só nova vaga)
        if (!_ehSubstituicao) ...[
          _secao('Documento de aprovação da diretoria'),
          const SizedBox(height: 4),
          Text(
            'Obrigatório para aumento de quadro.',
            style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                withData: true,
              );
              if (result != null && result.files.isNotEmpty) {
                if (mounted) setState(() => _docAprovacao = result.files.first);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _docAprovacao != null
                      ? AppColors.magenta
                      : const Color(0xFFE5E7EB),
                  width: _docAprovacao != null ? 1.5 : 1,
                ),
              ),
              child: _docAprovacao == null
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_file_outlined,
                            color: AppColors.cinzaTexto.withOpacity(0.6), size: 22),
                        const SizedBox(width: 10),
                        Text('Selecionar documento',
                            style: GoogleFonts.poppins(
                                fontSize: 13, color: AppColors.cinzaTexto)),
                      ],
                    )
                  : Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.magenta.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.description_outlined,
                              color: AppColors.magenta, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_docAprovacao!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.dark)),
                              Text(
                                '${(_docAprovacao!.size / 1024).toStringAsFixed(0)} KB',
                                style: GoogleFonts.poppins(
                                    fontSize: 11, color: AppColors.cinzaTexto),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _docAprovacao = null),
                          icon: const Icon(Icons.close_rounded,
                              size: 18, color: AppColors.cinzaTexto),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Informações da vaga
        _secao('Informações da vaga', obrigatorio: true),
        const SizedBox(height: 10),
        _campoTexto(
          ctrl: _centroCustoCtrl,
          label: 'Centro de custo',
          icone: Icons.account_balance_outlined,
        ),
        const SizedBox(height: 10),
        _campoTexto(
          ctrl: _liderancaMatriculaCtrl,
          label: 'Matrícula da liderança direta',
          icone: Icons.badge_outlined,
        ),
        const SizedBox(height: 10),
        _dropdownFilial(),
        const SizedBox(height: 20),

        // Motivo
        _secao('Motivo / Justificativa'),
        const SizedBox(height: 8),
        Text(
          'Opcional — explique brevemente a necessidade.',
          style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: TextField(
            controller: _motivoCtrl,
            maxLines: 4,
            style: GoogleFonts.poppins(fontSize: 14, color: AppColors.dark),
            decoration: InputDecoration(
              hintText: 'Ex: Aumento de demanda no setor, saída de colaborador...',
              hintStyle:
                  GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto.withOpacity(0.6)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Botão enviar
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: (_ehSubstituicao && _colaboradorSubstituido == null && _equipeDoSetorDaVaga.isNotEmpty) ||
                    (!_ehSubstituicao && _docAprovacao == null) ||
                    _horarioEntrada == null ||
                    _horarioSaida == null ||
                    _centroCustoCtrl.text.trim().isEmpty ||
                    _liderancaMatriculaCtrl.text.trim().isEmpty ||
                    _filialSelecionada == null
                ? null
                : () => setState(() => _mostrarEtapa3 = true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.magenta,
              disabledBackgroundColor: AppColors.cinzaTexto.withOpacity(0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: Text(
              _ehSubstituicao && _colaboradorSubstituido == null && _equipeDoSetorDaVaga.isNotEmpty
                  ? 'Selecione quem será substituído'
                  : 'Continuar',
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  // ── Etapa 3: Chamado de TI ──────────────────────────────────────────────────────

  Widget _buildEtapa3() {
    final precisaObservacao =
        _precisaOffice365 == true || _precisaMaquina == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      children: [
        _secao('Essa vaga vai precisar de chamado de TI?', obrigatorio: true),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _botaoTipo(
                label: 'Não',
                icone: Icons.close_rounded,
                selecionado: _abrirChamadoTI == false,
                onTap: () => setState(() {
                  _abrirChamadoTI = false;
                  _precisaUsuarioRede = null;
                  _acessoIgualColaborador = null;
                  _precisaOffice365 = null;
                  _precisaMaquina = null;
                  _observacaoTICtrl.clear();
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _botaoTipo(
                label: 'Sim',
                icone: Icons.build_outlined,
                selecionado: _abrirChamadoTI == true,
                onTap: () => setState(() => _abrirChamadoTI = true),
              ),
            ),
          ],
        ),
        if (_abrirChamadoTI == true) ...[
          const SizedBox(height: 24),
          _secao('Precisa de usuário de rede?', obrigatorio: true),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _botaoTipo(
                  label: 'Não',
                  icone: Icons.close_rounded,
                  selecionado: _precisaUsuarioRede == false,
                  onTap: () => setState(() {
                    _precisaUsuarioRede = false;
                    _acessoIgualColaborador = null;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _botaoTipo(
                  label: 'Sim',
                  icone: Icons.person_outline_rounded,
                  selecionado: _precisaUsuarioRede == true,
                  onTap: () {
                    setState(() => _precisaUsuarioRede = true);
                    if (_equipe.isEmpty) _carregarEquipe();
                  },
                ),
              ),
            ],
          ),
          if (_precisaUsuarioRede == true) ...[
            const SizedBox(height: 16),
            _secao('Acesso igual ao de qual colaborador?', obrigatorio: true),
            const SizedBox(height: 8),
            Text(
              'Colaboradores do mesmo setor da vaga.',
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto),
            ),
            const SizedBox(height: 8),
            if (_carregandoEquipe)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: AppColors.magenta),
              ))
            else if (_equipeDoSetorDaVaga.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Nenhum colaborador encontrado no setor desta vaga.',
                  style: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _acessoIgualColaborador != null
                        ? AppColors.laranja
                        : const Color(0xFFE5E7EB),
                    width: _acessoIgualColaborador != null ? 1.5 : 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: DropdownButtonHideUnderline(
                  // Value é a matrícula — mesmo motivo do dropdown de
                  // "Colaborador a substituir" acima.
                  child: DropdownButton<String>(
                    value: _acessoIgualColaborador?.matricula,
                    isExpanded: true,
                    hint: Text('Selecione...',
                        style:
                            GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto)),
                    style: GoogleFonts.poppins(fontSize: 13, color: AppColors.dark),
                    items: _equipeDoSetorDaVaga.map((c) {
                      return DropdownMenuItem(
                        value: c.matricula,
                        child: Text('${c.nome} – ${c.cargo}',
                            overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (matricula) => setState(() {
                      _acessoIgualColaborador = matricula == null
                          ? null
                          : _equipeDoSetorDaVaga
                              .firstWhere((c) => c.matricula == matricula);
                    }),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 24),
          _secao('Precisa de Office 365?', obrigatorio: true),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _botaoTipo(
                  label: 'Não',
                  icone: Icons.close_rounded,
                  selecionado: _precisaOffice365 == false,
                  onTap: () => setState(() => _precisaOffice365 = false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _botaoTipo(
                  label: 'Sim',
                  icone: Icons.email_outlined,
                  selecionado: _precisaOffice365 == true,
                  onTap: () => setState(() => _precisaOffice365 = true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _secao('Precisa de máquina?', obrigatorio: true),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _botaoTipo(
                  label: 'Não',
                  icone: Icons.close_rounded,
                  selecionado: _precisaMaquina == false,
                  onTap: () => setState(() => _precisaMaquina = false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _botaoTipo(
                  label: 'Sim',
                  icone: Icons.computer_outlined,
                  selecionado: _precisaMaquina == true,
                  onTap: () => setState(() => _precisaMaquina = true),
                ),
              ),
            ],
          ),
          if (precisaObservacao) ...[
            const SizedBox(height: 24),
            _secao('Alguma especificidade?'),
            const SizedBox(height: 4),
            Text(
              'Ex: versão do Office, configuração da máquina, sistema específico...',
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto),
            ),
            const SizedBox(height: 8),
            _campoTexto(
              ctrl: _observacaoTICtrl,
              label: 'Observação',
              icone: Icons.notes_outlined,
            ),
          ],
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: (_enviando || !_podeEnviarEtapa3)
                ? null
                : _enviar,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.magenta,
              disabledBackgroundColor: AppColors.cinzaTexto.withOpacity(0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: _enviando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Enviar para o RH',
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Widget _secao(String titulo, {bool obrigatorio = false}) => RichText(
        text: TextSpan(
          style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dark),
          children: [
            TextSpan(text: titulo),
            if (obrigatorio)
              TextSpan(
                text: ' *',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.magenta),
              ),
          ],
        ),
      );

  Widget _horarioPicker({
    required String label,
    required TimeOfDay? valor,
    required ValueChanged<TimeOfDay> onSelecionado,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: valor ?? const TimeOfDay(hour: 8, minute: 0),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
        if (picked != null) onSelecionado(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: valor != null ? AppColors.laranja : const Color(0xFFE5E7EB),
            width: valor != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded,
                size: 18,
                color: valor != null ? AppColors.laranja : AppColors.cinzaTexto),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                valor != null ? _timeStr(valor) : label,
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: valor != null ? FontWeight.w600 : FontWeight.normal,
                    color: valor != null ? AppColors.dark : AppColors.cinzaTexto),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _botaoTipo({
    required String label,
    required IconData icone,
    required bool selecionado,
    required VoidCallback onTap,
  }) {
    final cor = selecionado ? AppColors.laranja : AppColors.cinzaTexto.withOpacity(0.5);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selecionado ? AppColors.laranja.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selecionado ? AppColors.laranja : const Color(0xFFE5E7EB),
            width: selecionado ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: cor, size: 26),
            const SizedBox(height: 6),
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w600, color: cor)),
          ],
        ),
      ),
    );
  }

  Widget _campoTexto({
    required TextEditingController ctrl,
    required String label,
    required IconData icone,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: TextField(
          controller: ctrl,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.dark),
          decoration: InputDecoration(
            labelText: label,
            labelStyle:
                GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto),
            prefixIcon:
                Icon(icone, size: 18, color: AppColors.cinzaTexto),
            filled: true,
            fillColor: Colors.white,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      );

  Widget _dropdownFilial() {
    // O value do DropdownButton precisa bater com exatamente um item. Usar o
    // 'nome' como value quebra silenciosamente (dropdown não abre, sem erro
    // visível em build de produção) quando duas filiais têm o mesmo nome de
    // exibição — a 'chave' (código da filial) é a que garante unicidade.
    final chaveSelecionada = _filiais
        .firstWhere((f) => f['nome'] == _filialSelecionada, orElse: () => const {})['chave']
        as String?;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _filialSelecionada != null
              ? AppColors.laranja
              : const Color(0xFFE5E7EB),
          width: _filialSelecionada != null ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(children: [
        Icon(Icons.location_city_outlined,
            size: 18, color: AppColors.cinzaTexto),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: chaveSelecionada,
              hint: Text('Filial',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppColors.cinzaTexto)),
              isExpanded: true,
              style: GoogleFonts.poppins(fontSize: 14, color: AppColors.dark),
              items: _filiais.map((f) {
                final nome = f['nome'] as String;
                final chave = f['chave'] as String;
                return DropdownMenuItem<String>(
                  value: chave,
                  child: Text('$nome ($chave)'),
                );
              }).toList(),
              onChanged: (novaChave) {
                final nome = _filiais.firstWhere(
                    (f) => f['chave'] == novaChave)['nome'] as String;
                setState(() => _filialSelecionada = nome);
              },
            ),
          ),
        ),
      ]),
    );
  }

  Widget _tag(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 10, fontWeight: FontWeight.w500, color: color)),
      );
}
