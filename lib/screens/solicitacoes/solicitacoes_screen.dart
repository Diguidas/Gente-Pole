import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';

const _corSolicitacoes = Color(0xFF7C3AED);

const Map<String, String> _labelTipoSolicitacao = {
  'adesao_beneficio': 'Adesão de Benefício',
  'comunicado_interno': 'Comunicado Interno',
  'incentivo_educacional': 'Incentivo Educacional',
  'cracha': 'Crachá',
  'treinamento': 'Treinamento',
  'rota': 'Rota',
};

const Map<String, IconData> _iconeTipoSolicitacao = {
  'adesao_beneficio': Icons.card_giftcard_outlined,
  'comunicado_interno': Icons.campaign_outlined,
  'incentivo_educacional': Icons.school_outlined,
  'cracha': Icons.badge_outlined,
  'treinamento': Icons.menu_book_outlined,
  'rota': Icons.alt_route_outlined,
};

/// Mostra o payload de uma solicitação de forma legível (usado tanto na
/// tela do colaborador quanto na do gestor).
class PayloadSolicitacaoView extends StatelessWidget {
  final Map<String, dynamic> payload;
  const PayloadSolicitacaoView({super.key, required this.payload});

  @override
  Widget build(BuildContext context) {
    final entradas = payload.entries
        .where((e) => e.value != null && e.value.toString().trim().isNotEmpty)
        .toList();
    if (entradas.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entradas
            .map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${e.key}: ',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dark),
                        ),
                        TextSpan(
                          text: '${e.value}',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: AppColors.cinzaTexto),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

/// dd/mm/aaaa a partir do `data_admissao` (ISO ou já dd/mm/aaaa) do
/// colaborador — usado nos payloads das solicitações.
String? _formatarDataAdmissao(String? valor) {
  if (valor == null || valor.isEmpty) return null;
  final d = DateTime.tryParse(valor);
  if (d == null) return valor;
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

InputDecoration _decoracaoCampo({String? hint}) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    );

/// Rótulo + campo, no padrão usado em todos os formulários de solicitação.
class _CampoRotulado extends StatelessWidget {
  final String label;
  final Widget child;
  const _CampoRotulado({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.cinzaTexto)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// Casco comum de todo dialog de "abrir solicitação": título, subtítulo
/// opcional, corpo rolável definido por quem usa, erro e botões
/// Cancelar/Enviar. Espelha `SolicitacaoDialogShell` do gentepole_admin.
class _SolicitacaoDialogShell extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final List<Widget> campos;
  final String? erro;
  final bool enviando;
  final VoidCallback onEnviar;

  const _SolicitacaoDialogShell({
    required this.titulo,
    this.subtitulo,
    required this.campos,
    this.erro,
    required this.enviando,
    required this.onEnviar,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 620),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark)),
                if (subtitulo != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitulo!,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.cinzaTexto)),
                ],
                const SizedBox(height: 16),
                ...campos,
                if (erro != null) ...[
                  const SizedBox(height: 8),
                  Text(erro!,
                      style:
                          GoogleFonts.poppins(fontSize: 12, color: AppColors.erro)),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: enviando ? null : onEnviar,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _corSolicitacoes,
                        foregroundColor: Colors.white),
                    child: enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Enviar'),
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

/// "Solicitações" do colaborador — hub para abrir pedidos diversos (adesão
/// de benefício, comunicado interno, incentivo educacional, crachá,
/// treinamento, rota) e acompanhar o status das que já abriu. Porta fiel de
/// `solicitacoes_colab_screen.dart` + `solicitacoes_colab_formularios.dart`
/// do gentepole_admin, com um dialog específico por tipo (dropdowns/enums
/// exatos, sem formulário genérico de texto livre).
class SolicitacoesScreen extends StatefulWidget {
  const SolicitacoesScreen({super.key});

  @override
  State<SolicitacoesScreen> createState() => _SolicitacoesScreenState();
}

class _SolicitacoesScreenState extends State<SolicitacoesScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _minhas = [];
  bool _abaMinhas = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final col = _api.colaboradorAtual;
    if (col == null) {
      setState(() => _loading = false);
      return;
    }
    final minhas = await _api.listarSolicitacoes(abertoPorId: col.id);
    if (!mounted) return;
    setState(() {
      _minhas = minhas;
      _loading = false;
    });
  }

  Future<void> _abrirFormulario(String tipo) async {
    final col = _api.colaboradorAtual;
    if (col == null) return;
    bool? enviado;
    switch (tipo) {
      case 'adesao_beneficio':
        enviado = await showDialog<bool>(
          context: context,
          builder: (_) => _DialogAdesaoBeneficio(colab: col, api: _api),
        );
        break;
      case 'comunicado_interno':
        enviado = await showDialog<bool>(
          context: context,
          builder: (_) => _DialogComunicadoInterno(colab: col, api: _api),
        );
        break;
      case 'incentivo_educacional':
        enviado = await showDialog<bool>(
          context: context,
          builder: (_) => _DialogIncentivoEducacional(colab: col, api: _api),
        );
        break;
      case 'cracha':
        enviado = await showDialog<bool>(
          context: context,
          builder: (_) => _DialogCracha(colab: col, api: _api),
        );
        break;
      case 'treinamento':
        enviado = await showDialog<bool>(
          context: context,
          builder: (_) => _DialogTreinamento(colab: col, api: _api),
        );
        break;
      case 'rota':
        enviado = await showDialog<bool>(
          context: context,
          builder: (_) => _DialogRota(colab: col, api: _api),
        );
        break;
    }
    if (enviado == true) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 200,
            decoration:
                const BoxDecoration(gradient: AppColors.gradientePrincipal),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📋 Solicitações',
                              style: AppTextStyles.tituloGrande
                                  .copyWith(color: Colors.white)),
                          Text('Abra um pedido e acompanhe o andamento',
                              style: AppTextStyles.corpoBranco
                                  .copyWith(color: AppColors.brancoOp80)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            _tabBtn('Novo pedido', !_abaMinhas,
                                () => setState(() => _abaMinhas = false)),
                            const SizedBox(width: 8),
                            _tabBtn('Minhas solicitações', _abaMinhas,
                                () => setState(() => _abaMinhas = true)),
                          ]),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator(
                                        color: _corSolicitacoes))
                                : (_abaMinhas ? _listaMinhas() : _grid()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, bool ativo, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: ativo ? _corSolicitacoes : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ativo ? Colors.white : AppColors.cinzaTexto)),
      ),
    );
  }

  Widget _grid() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 110,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _labelTipoSolicitacao.length,
      itemBuilder: (_, i) {
        final tipo = _labelTipoSolicitacao.keys.elementAt(i);
        final label = _labelTipoSolicitacao[tipo]!;
        final icone = _iconeTipoSolicitacao[tipo]!;
        return GestureDetector(
          onTap: () => _abrirFormulario(tipo),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icone, color: _corSolicitacoes, size: 24),
                Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _listaMinhas() {
    if (_minhas.isEmpty) {
      return Center(
          child: Text('Você ainda não abriu nenhuma solicitação.',
              style: GoogleFonts.poppins(color: AppColors.cinzaTexto)));
    }
    return ListView.separated(
      itemCount: _minhas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = _minhas[i];
        final tipo = s['tipo'] as String;
        final status = s['status'] as String? ?? 'pendente';
        final payload =
            (s['payload'] as Map?)?.cast<String, dynamic>() ?? {};
        final podeExtra = tipo == 'adesao_beneficio' &&
            status != 'concluido' &&
            status != 'cancelado';
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_iconeTipoSolicitacao[tipo] ?? Icons.assignment_outlined,
                  color: _corSolicitacoes, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_labelTipoSolicitacao[tipo] ?? tipo,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark)),
                    if (s['motivo_recusa_gestor'] != null)
                      Text('Motivo: ${s['motivo_recusa_gestor']}',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: AppColors.cinzaTexto)),
                  ],
                ),
              ),
              _statusChip(status),
            ]),
            if (payload.isNotEmpty) ...[
              const SizedBox(height: 8),
              PayloadSolicitacaoView(payload: payload),
            ],
            if (podeExtra) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _solicitarValorExtra(s),
                  child: Text('Solicitar valor extra',
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _corSolicitacoes)),
                ),
              ),
            ],
          ]),
        );
      },
    );
  }

  Future<void> _solicitarValorExtra(Map<String, dynamic> s) async {
    final valorCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Solicitar valor extra',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: valorCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'Valor extra'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: motivoCtrl,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Motivo'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _corSolicitacoes, foregroundColor: Colors.white),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirmado != true || valorCtrl.text.trim().isEmpty) return;
    final col = _api.colaboradorAtual;
    await _api.adicionarNotaSolicitacao(
      solicitacaoId: s['id'] as int,
      texto: '[Valor extra solicitado] R\$ ${valorCtrl.text.trim()}'
          '${motivoCtrl.text.trim().isNotEmpty ? ' — ${motivoCtrl.text.trim()}' : ''}',
      autorNome: col?.nome,
    );
    _carregar();
  }

  Widget _statusChip(String status) {
    final Color cor;
    final String label;
    switch (status) {
      case 'pendente_gestor':
        cor = const Color(0xFFD97706);
        label = 'Aguardando gestor';
        break;
      case 'recusado_gestor':
        cor = const Color(0xFFDC2626);
        label = 'Recusada pelo gestor';
        break;
      case 'em_andamento':
        cor = const Color(0xFF2563EB);
        label = 'Em andamento';
        break;
      case 'concluido':
        cor = const Color(0xFF16A34A);
        label = 'Concluído';
        break;
      case 'cancelado':
        cor = const Color(0xFFDC2626);
        label = 'Cancelado';
        break;
      default:
        cor = const Color(0xFFD97706);
        label = 'Pendente';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: cor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w700, color: cor)),
    );
  }
}

// ─── Adesão de Benefício ────────────────────────────────────────────────────

const _tiposBeneficio = {
  'alimentacao': 'Alimentação',
  'combustivel': 'Combustível',
  'ajuda_custo': 'Ajuda de Custo',
};

class _DialogAdesaoBeneficio extends StatefulWidget {
  final ColaboradorModel colab;
  final ApiService api;
  const _DialogAdesaoBeneficio({required this.colab, required this.api});

  @override
  State<_DialogAdesaoBeneficio> createState() => _DialogAdesaoBeneficioState();
}

class _DialogAdesaoBeneficioState extends State<_DialogAdesaoBeneficio> {
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
    if (_tipo == null ||
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
          'Colaborador': widget.colab.nome,
          'Matrícula': widget.colab.matricula,
          'Cargo': widget.colab.cargo,
          if (_formatarDataAdmissao(widget.colab.dataAdmissao) != null)
            'Data de admissão': _formatarDataAdmissao(widget.colab.dataAdmissao),
          'Tipo de benefício': _tiposBeneficio[_tipo],
          'Valor': _valorCtrl.text.trim(),
          'Justificativa': _justificativaCtrl.text.trim(),
        },
        abertoPorId: widget.colab.id,
        abertoPorNome: widget.colab.nome,
        abertoPorPapel: 'colaborador',
        setor: widget.colab.setor,
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
    return _SolicitacaoDialogShell(
      titulo: 'Adesão de Benefício',
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        _CampoRotulado(
          label: 'Tipo de benefício',
          child: DropdownButtonFormField<String>(
            value: _tipo,
            decoration: _decoracaoCampo(),
            items: _tiposBeneficio.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _tipo = v),
          ),
        ),
        _CampoRotulado(
          label: 'Valor',
          child: TextField(
            controller: _valorCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoracaoCampo(hint: 'Ex: 250.00'),
          ),
        ),
        _CampoRotulado(
          label: 'Justificativa',
          child: TextField(controller: _justificativaCtrl, maxLines: 3, decoration: _decoracaoCampo()),
        ),
      ],
    );
  }
}

// ─── Comunicado Interno ─────────────────────────────────────────────────────

const _tiposComunicado = {
  'peca_placa': 'Peça/Placas',
  'comunicado_padrao': 'Comunicados Padrões',
  'identidade_visual': 'Identidade Visual',
  'logotipo': 'Logotipos',
  'gravacao_video': 'Gravação de Vídeo',
  'edicao_video': 'Edição de Vídeos',
  'criacao_arte': 'Criação de Arte',
  'post_redes_sociais': 'Post para Redes Sociais',
};

class _DialogComunicadoInterno extends StatefulWidget {
  final ColaboradorModel colab;
  final ApiService api;
  const _DialogComunicadoInterno({required this.colab, required this.api});

  @override
  State<_DialogComunicadoInterno> createState() => _DialogComunicadoInternoState();
}

class _DialogComunicadoInternoState extends State<_DialogComunicadoInterno> {
  String? _tipo;
  final _objetivoCtrl = TextEditingController();
  final _textoCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _objetivoCtrl.dispose();
    _textoCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_tipo == null || _objetivoCtrl.text.trim().isEmpty) {
      setState(() => _erro = 'Selecione o tipo e informe o objetivo.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.api.criarSolicitacao(
        tipo: 'comunicado_interno',
        payload: {
          'Solicitante': widget.colab.nome,
          'Matrícula': widget.colab.matricula,
          'Cargo': widget.colab.cargo,
          'Tipo': _tiposComunicado[_tipo],
          'Objetivo': _objetivoCtrl.text.trim(),
          'Texto que acompanha': _textoCtrl.text.trim(),
          'Observações': _obsCtrl.text.trim(),
        },
        abertoPorId: widget.colab.id,
        abertoPorNome: widget.colab.nome,
        abertoPorPapel: 'colaborador',
        setor: widget.colab.setor,
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
    return _SolicitacaoDialogShell(
      titulo: 'Comunicado Interno',
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        _CampoRotulado(
          label: 'Tipo de material',
          child: DropdownButtonFormField<String>(
            value: _tipo,
            isExpanded: true,
            decoration: _decoracaoCampo(),
            items: _tiposComunicado.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _tipo = v),
          ),
        ),
        _CampoRotulado(
          label: 'Qual o objetivo do material?',
          child: TextField(controller: _objetivoCtrl, maxLines: 2, decoration: _decoracaoCampo()),
        ),
        _CampoRotulado(
          label: 'Qual texto acompanhará o material?',
          child: TextField(controller: _textoCtrl, maxLines: 3, decoration: _decoracaoCampo()),
        ),
        _CampoRotulado(
          label: 'Observações importantes (opcional)',
          child: TextField(controller: _obsCtrl, maxLines: 2, decoration: _decoracaoCampo()),
        ),
      ],
    );
  }
}

// ─── Crachá ─────────────────────────────────────────────────────────────────

const _motivosCracha = {
  'perda': 'Perda',
  'desgaste': 'Desgaste',
  'quebra': 'Quebra',
  'primeira_via': 'Primeira via',
};

class _DialogCracha extends StatefulWidget {
  final ColaboradorModel colab;
  final ApiService api;
  const _DialogCracha({required this.colab, required this.api});

  @override
  State<_DialogCracha> createState() => _DialogCrachaState();
}

class _DialogCrachaState extends State<_DialogCracha> {
  String? _motivo;
  PlatformFile? _foto;
  bool _enviando = false;
  String? _erro;

  Future<void> _escolherFoto() async {
    final resultado = await FilePicker.platform.pickFiles(withData: true, type: FileType.image);
    if (!mounted) return;
    if (resultado != null && resultado.files.isNotEmpty) {
      setState(() => _foto = resultado.files.first);
    }
  }

  Future<void> _enviar() async {
    if (_motivo == null || _foto == null) {
      setState(() => _erro = 'Selecione o motivo e a foto para o crachá.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final fotoUrl = await widget.api.uploadAnexoSolicitacao(
        Uint8List.fromList(_foto!.bytes!),
        _foto!.name,
      );
      await widget.api.criarSolicitacao(
        tipo: 'cracha',
        payload: {
          'Colaborador': widget.colab.nome,
          'Matrícula': widget.colab.matricula,
          'Cargo': widget.colab.cargo,
          if (_formatarDataAdmissao(widget.colab.dataAdmissao) != null)
            'Data de admissão': _formatarDataAdmissao(widget.colab.dataAdmissao),
          'Motivo': _motivosCracha[_motivo],
          'Foto': fotoUrl,
        },
        abertoPorId: widget.colab.id,
        abertoPorNome: widget.colab.nome,
        abertoPorPapel: 'colaborador',
        setor: widget.colab.setor,
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
    return _SolicitacaoDialogShell(
      titulo: 'Solicitação de Crachá',
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        _CampoRotulado(
          label: 'Motivo',
          child: DropdownButtonFormField<String>(
            value: _motivo,
            decoration: _decoracaoCampo(),
            items: _motivosCracha.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _motivo = v),
          ),
        ),
        _CampoRotulado(
          label: 'Foto para o crachá',
          child: OutlinedButton.icon(
            onPressed: _escolherFoto,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text(_foto?.name ?? 'Escolher foto', overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size(double.infinity, 44),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Treinamento ────────────────────────────────────────────────────────────

class _DialogTreinamento extends StatefulWidget {
  final ColaboradorModel colab;
  final ApiService api;
  const _DialogTreinamento({required this.colab, required this.api});

  @override
  State<_DialogTreinamento> createState() => _DialogTreinamentoState();
}

class _DialogTreinamentoState extends State<_DialogTreinamento> {
  final _publicoCtrl = TextEditingController();
  final _temaCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  bool _online = false;
  List<Map<String, dynamic>> _filiais = [];
  final Set<String> _filiaisSelecionadas = {};
  bool _carregandoFiliais = true;
  bool _enviando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
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
    _publicoCtrl.dispose();
    _temaCtrl.dispose();
    _descricaoCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_publicoCtrl.text.trim().isEmpty || _temaCtrl.text.trim().isEmpty) {
      setState(() => _erro = 'Informe o público-alvo e o tema.');
      return;
    }
    if (_filiaisSelecionadas.isEmpty && !_online) {
      setState(() => _erro = 'Selecione ao menos um local (filial ou online).');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final locais = [..._filiaisSelecionadas, if (_online) 'Online'];
    try {
      await widget.api.criarSolicitacao(
        tipo: 'treinamento',
        payload: {
          'Colaborador': widget.colab.nome,
          'Matrícula': widget.colab.matricula,
          'Cargo': widget.colab.cargo,
          'Público-alvo': _publicoCtrl.text.trim(),
          'Tema': _temaCtrl.text.trim(),
          'Locais': locais.join(', '),
          'Descrição prévia': _descricaoCtrl.text.trim(),
        },
        abertoPorId: widget.colab.id,
        abertoPorNome: widget.colab.nome,
        abertoPorPapel: 'colaborador',
        setor: widget.colab.setor,
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
    return _SolicitacaoDialogShell(
      titulo: 'Solicitar Treinamento',
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        _CampoRotulado(label: 'Público-alvo', child: TextField(controller: _publicoCtrl, decoration: _decoracaoCampo())),
        _CampoRotulado(label: 'Tema', child: TextField(controller: _temaCtrl, decoration: _decoracaoCampo())),
        _CampoRotulado(
          label: 'Locais do treinamento',
          child: _carregandoFiliais
              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ..._filiais.map((f) {
                      final nome = f['nome'] as String;
                      final sel = _filiaisSelecionadas.contains(nome);
                      return FilterChip(
                        label: Text(nome, style: GoogleFonts.poppins(fontSize: 12)),
                        selected: sel,
                        onSelected: (v) => setState(() => v ? _filiaisSelecionadas.add(nome) : _filiaisSelecionadas.remove(nome)),
                      );
                    }),
                    FilterChip(
                      label: Text('Online', style: GoogleFonts.poppins(fontSize: 12)),
                      selected: _online,
                      onSelected: (v) => setState(() => _online = v),
                    ),
                  ],
                ),
        ),
        _CampoRotulado(
          label: 'Descrição prévia de tópicos e temas',
          child: TextField(controller: _descricaoCtrl, maxLines: 3, decoration: _decoracaoCampo()),
        ),
      ],
    );
  }
}

// ─── Rota (passa por aprovação do gestor) ──────────────────────────────────

const _contasRazaoRota = {
  '32204014': 'PJ Custo Direto',
  '32304004': 'PJ Custo Indireto',
  '31103003': 'PJ Despesa ADM',
  '31209011': 'PJ Comercial',
};

class _DialogRota extends StatefulWidget {
  final ColaboradorModel colab;
  final ApiService api;
  const _DialogRota({required this.colab, required this.api});

  @override
  State<_DialogRota> createState() => _DialogRotaState();
}

class _DialogRotaState extends State<_DialogRota> {
  DateTime _data = DateTime.now();
  TimeOfDay _horaSaida = TimeOfDay.now();
  String _tipo = 'moto';
  final _localSaidaNomeCtrl = TextEditingController();
  final _localSaidaEnderecoCtrl = TextEditingController();
  final _localDestinoNomeCtrl = TextEditingController();
  final _localDestinoEnderecoCtrl = TextEditingController();
  final _descricaoTarefaCtrl = TextEditingController();
  final _procurarPorCtrl = TextEditingController();
  bool _recolhimentoValor = false;
  final _justificativaCtrl = TextEditingController();
  String? _contaRazao;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _localSaidaNomeCtrl.dispose();
    _localSaidaEnderecoCtrl.dispose();
    _localDestinoNomeCtrl.dispose();
    _localDestinoEnderecoCtrl.dispose();
    _descricaoTarefaCtrl.dispose();
    _procurarPorCtrl.dispose();
    _justificativaCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_localSaidaNomeCtrl.text.trim().isEmpty ||
        _localDestinoNomeCtrl.text.trim().isEmpty ||
        _justificativaCtrl.text.trim().isEmpty ||
        _contaRazao == null) {
      setState(() => _erro = 'Preencha origem, destino, justificativa e conta razão.');
      return;
    }
    if (widget.colab.setor == null || widget.colab.setor!.isEmpty) {
      setState(() => _erro = 'Você não tem um setor definido. Fale com o RH.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final gestor = await widget.api.buscarGestorDoSetor(
          widget.colab.setor!, widget.colab.empresa ?? '',
          colaboradorId: widget.colab.id);
      if (gestor == null) {
        setState(() {
          _enviando = false;
          _erro = 'Nenhum gestor encontrado para o seu setor. Fale com o RH.';
        });
        return;
      }
      final dataStr = '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}';
      final horaStr = '${_horaSaida.hour.toString().padLeft(2, '0')}:${_horaSaida.minute.toString().padLeft(2, '0')}';
      await widget.api.criarSolicitacao(
        tipo: 'rota',
        payload: {
          'Colaborador solicitante': widget.colab.nome,
          'Matrícula': widget.colab.matricula,
          'Cargo': widget.colab.cargo,
          'Centro de custo': widget.colab.codCentro ?? '',
          'Conta razão': '$_contaRazao - ${_contasRazaoRota[_contaRazao]}',
          'Data da rota': dataStr,
          'Horário de saída': horaStr,
          'Tipo': _tipo == 'moto' ? 'Moto' : 'Carro frete',
          'Local de saída': '${_localSaidaNomeCtrl.text.trim()} — ${_localSaidaEnderecoCtrl.text.trim()}',
          'Local de destino': '${_localDestinoNomeCtrl.text.trim()} — ${_localDestinoEnderecoCtrl.text.trim()}',
          'Descrição da tarefa': _descricaoTarefaCtrl.text.trim(),
          'Procurar por': _procurarPorCtrl.text.trim(),
          'Recolhimento de valor': _recolhimentoValor ? 'Sim' : 'Não',
          'Justificativa': _justificativaCtrl.text.trim(),
        },
        abertoPorId: widget.colab.id,
        abertoPorNome: widget.colab.nome,
        abertoPorPapel: 'colaborador',
        setor: widget.colab.setor,
        requerAprovacaoGestor: true,
        gestorId: gestor.id,
        gestorNome: gestor.nome,
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
    return _SolicitacaoDialogShell(
      titulo: 'Solicitar Rota',
      subtitulo: 'Vai passar pela aprovação do seu gestor antes de ir para o RH.',
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        Row(children: [
          Expanded(
            child: _CampoRotulado(
              label: 'Data',
              child: OutlinedButton(
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context, initialDate: _data, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setState(() => _data = d);
                },
                child: Text('${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CampoRotulado(
              label: 'Horário de saída',
              child: OutlinedButton(
                onPressed: () async {
                  final t = await showTimePicker(context: context, initialTime: _horaSaida);
                  if (t != null) setState(() => _horaSaida = t);
                },
                child: Text('${_horaSaida.hour.toString().padLeft(2, '0')}:${_horaSaida.minute.toString().padLeft(2, '0')}'),
              ),
            ),
          ),
        ]),
        _CampoRotulado(
          label: 'Tipo',
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'moto', label: Text('Moto')),
              ButtonSegment(value: 'carro_frete', label: Text('Carro frete')),
            ],
            selected: {_tipo},
            onSelectionChanged: (v) => setState(() => _tipo = v.first),
          ),
        ),
        _CampoRotulado(label: 'Nome do local de saída', child: TextField(controller: _localSaidaNomeCtrl, decoration: _decoracaoCampo())),
        _CampoRotulado(label: 'Endereço de saída', child: TextField(controller: _localSaidaEnderecoCtrl, decoration: _decoracaoCampo())),
        _CampoRotulado(label: 'Nome do local de destino', child: TextField(controller: _localDestinoNomeCtrl, decoration: _decoracaoCampo())),
        _CampoRotulado(label: 'Endereço de destino', child: TextField(controller: _localDestinoEnderecoCtrl, decoration: _decoracaoCampo())),
        _CampoRotulado(label: 'Descrição da tarefa', child: TextField(controller: _descricaoTarefaCtrl, maxLines: 2, decoration: _decoracaoCampo())),
        _CampoRotulado(label: 'Procurar por (opcional)', child: TextField(controller: _procurarPorCtrl, decoration: _decoracaoCampo())),
        _CampoRotulado(
          label: 'Recolhimento de valor?',
          child: SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('Sim')), ButtonSegment(value: false, label: Text('Não'))],
            selected: {_recolhimentoValor},
            onSelectionChanged: (v) => setState(() => _recolhimentoValor = v.first),
          ),
        ),
        _CampoRotulado(label: 'Justificativa', child: TextField(controller: _justificativaCtrl, maxLines: 2, decoration: _decoracaoCampo())),
        _CampoRotulado(
          label: 'Conta razão (serviços profissionais contratados)',
          child: DropdownButtonFormField<String>(
            value: _contaRazao,
            isExpanded: true,
            decoration: _decoracaoCampo(),
            items: _contasRazaoRota.entries.map((e) => DropdownMenuItem(value: e.key, child: Text('${e.key} - ${e.value}'))).toList(),
            onChanged: (v) => setState(() => _contaRazao = v),
          ),
        ),
      ],
    );
  }
}

// ─── Incentivo Educacional (passa por aprovação do gestor) ─────────────────

class _DialogIncentivoEducacional extends StatefulWidget {
  final ColaboradorModel colab;
  final ApiService api;
  const _DialogIncentivoEducacional({required this.colab, required this.api});

  @override
  State<_DialogIncentivoEducacional> createState() => _DialogIncentivoEducacionalState();
}

class _DialogIncentivoEducacionalState extends State<_DialogIncentivoEducacional> {
  final _justificativaCtrl = TextEditingController();
  PlatformFile? _comprovante;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _justificativaCtrl.dispose();
    super.dispose();
  }

  Future<void> _escolherComprovante() async {
    final resultado = await FilePicker.platform.pickFiles(withData: true);
    if (!mounted) return;
    if (resultado != null && resultado.files.isNotEmpty) {
      setState(() => _comprovante = resultado.files.first);
    }
  }

  Future<void> _enviar() async {
    if (_comprovante == null) {
      setState(() => _erro = 'Anexe o comprovante.');
      return;
    }
    if (_justificativaCtrl.text.trim().isEmpty) {
      setState(() => _erro = 'Preencha a justificativa.');
      return;
    }
    if (widget.colab.setor == null || widget.colab.setor!.isEmpty) {
      setState(() => _erro = 'Você não tem um setor definido. Fale com o RH.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });

    try {
      final gestor = await widget.api.buscarGestorDoSetor(
          widget.colab.setor!, widget.colab.empresa ?? '',
          colaboradorId: widget.colab.id);
      if (gestor == null) {
        setState(() {
          _enviando = false;
          _erro = 'Nenhum gestor encontrado para o seu setor. Fale com o RH.';
        });
        return;
      }

      final anexoUrl = await widget.api.uploadAnexoSolicitacao(
        Uint8List.fromList(_comprovante!.bytes!),
        _comprovante!.name,
      );

      await widget.api.criarSolicitacao(
        tipo: 'incentivo_educacional',
        payload: {
          'Colaborador': widget.colab.nome,
          'Matrícula': widget.colab.matricula,
          'Cargo': widget.colab.cargo,
          'Setor': widget.colab.setor,
          if (_formatarDataAdmissao(widget.colab.dataAdmissao) != null)
            'Data de admissão': _formatarDataAdmissao(widget.colab.dataAdmissao),
          'Justificativa': _justificativaCtrl.text.trim(),
          'Comprovante': anexoUrl,
        },
        abertoPorId: widget.colab.id,
        abertoPorNome: widget.colab.nome,
        abertoPorPapel: 'colaborador',
        setor: widget.colab.setor,
        requerAprovacaoGestor: true,
        gestorId: gestor.id,
        gestorNome: gestor.nome,
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
    return _SolicitacaoDialogShell(
      titulo: 'Incentivo Educacional',
      subtitulo: 'Vai passar pela aprovação do seu gestor antes de ir para o RH.',
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        _CampoRotulado(
          label: 'Comprovante',
          child: OutlinedButton.icon(
            onPressed: _escolherComprovante,
            icon: const Icon(Icons.attach_file, size: 18),
            label: Text(_comprovante?.name ?? 'Escolher arquivo', overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size(double.infinity, 44),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
        ),
        _CampoRotulado(
          label: 'Justificativa',
          child: TextField(
            controller: _justificativaCtrl,
            maxLines: 3,
            decoration: _decoracaoCampo(hint: 'Explique o motivo do pedido'),
          ),
        ),
      ],
    );
  }
}
