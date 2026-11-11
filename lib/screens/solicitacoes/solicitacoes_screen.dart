import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';
import '../gestor/solicitacoes_gestor_formularios.dart' show DialogUber;
import 'escolha_cotacao_dialog.dart';

const _corSolicitacoes = Color(0xFF7C3AED);

const Map<String, String> _labelTipoSolicitacao = {
  'adesao_beneficio': 'Adesão de Benefício',
  'comunicado_interno': 'Comunicado Interno',
  'incentivo_educacional': 'Incentivo Educacional',
  'cracha': 'Crachá',
  'reembolso_sesmt': 'Reembolso SESMT',
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

// Tipos que aparecem no grid de "novo pedido" — igual ao web
// (solicitacoes_colab_screen.dart). Adesão de Benefício é exclusiva de líder
// (abre pela tela de Solicitações do gestor).
const List<String> _tiposAbriveis = [
  'comunicado_interno',
  'incentivo_educacional',
  'cracha',
  'treinamento',
  'rota',
];

bool _pareceUrl(String v) => v.startsWith('http://') || v.startsWith('https://');

/// Código de 4 dígitos da solicitação ("#1234"), ou vazio se ainda não tiver.
String codigoSolicitacao(Map<String, dynamic> s) {
  final c = s['codigo'];
  return c == null ? '' : '#$c';
}

/// "#1234 · Crachá" — título de cartão com o código na frente.
String tituloComCodigo(Map<String, dynamic> s, String titulo) {
  final c = codigoSolicitacao(s);
  return c.isEmpty ? titulo : '$c · $titulo';
}

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
                  child: _pareceUrl('${e.value}')
                      ? Row(children: [
                          Text('${e.key}: ',
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.dark)),
                          GestureDetector(
                            onTap: () => launchUrl(Uri.parse('${e.value}'),
                                mode: LaunchMode.externalApplication),
                            child: Text('Ver anexo',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: _corSolicitacoes,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline)),
                          ),
                        ])
                      : RichText(
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
String? formatarDataAdmissao(String? valor) {
  if (valor == null || valor.isEmpty) return null;
  final d = DateTime.tryParse(valor);
  if (d == null) return valor;
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

InputDecoration decoracaoCampo({String? hint}) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    );

/// Rótulo + campo, no padrão usado em todos os formulários de solicitação.
class CampoRotulado extends StatelessWidget {
  final String label;
  final Widget child;
  const CampoRotulado({super.key, required this.label, required this.child});

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
class SolicitacaoDialogShell extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final List<Widget> campos;
  final String? erro;
  final bool enviando;
  final VoidCallback onEnviar;
  final Color cor;
  final String labelBotao;

  const SolicitacaoDialogShell({
    super.key,
    required this.titulo,
    this.subtitulo,
    required this.campos,
    this.erro,
    required this.enviando,
    required this.onEnviar,
    this.cor = _corSolicitacoes,
    this.labelBotao = 'Enviar',
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
                        backgroundColor: cor,
                        foregroundColor: Colors.white),
                    child: enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(labelBotao),
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
  Map<int, List<Map<String, dynamic>>> _notasPorSolicitacao = {};

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
    final notas = await _api
        .listarNotasSolicitacoes(minhas.map((s) => s['id'] as int).toList());
    if (!mounted) return;
    setState(() {
      _minhas = minhas;
      _notasPorSolicitacao = notas;
      _loading = false;
    });
  }

  Future<void> _abrirFormulario(String tipo) async {
    final col = _api.colaboradorAtual;
    if (col == null) return;
    bool? enviado;
    switch (tipo) {
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
          builder: (_) => DialogRota(colab: col, api: _api),
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
                          Text('Solicitações',
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
                          // Tudo numa tela só: novo pedido no topo e, logo
                          // abaixo, o acompanhamento das já abertas.
                          Expanded(
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator(
                                        color: _corSolicitacoes))
                                : RefreshIndicator(
                                    onRefresh: _carregar,
                                    child: ListView(
                                      children: [
                                        _tituloSecao('Abrir um novo pedido'),
                                        _grid(),
                                        const SizedBox(height: 24),
                                        _tituloSecao('Minhas solicitações'),
                                        ..._listaMinhas(),
                                      ],
                                    ),
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
        ],
      ),
    );
  }

  Widget _tituloSecao(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(texto,
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.dark)),
    );
  }

  Widget _grid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 110,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _tiposAbriveis.length,
      itemBuilder: (_, i) {
        final tipo = _tiposAbriveis[i];
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

  static const List<(String, String)> _gruposStatus = [
    ('aberto', 'Em aberto'),
    ('concluido', 'Concluídas'),
    ('encerrado', 'Recusadas/Canceladas'),
  ];

  String _grupoDoStatus(String status) {
    switch (status) {
      case 'concluido':
        return 'concluido';
      case 'cancelado':
      case 'recusado_gestor':
        return 'encerrado';
      default:
        return 'aberto';
    }
  }

  List<Widget> _listaMinhas() {
    if (_minhas.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
              child: Text('Você ainda não abriu nenhuma solicitação.',
                  style: GoogleFonts.poppins(color: AppColors.cinzaTexto))),
        ),
      ];
    }
    final porGrupo = <String, List<Map<String, dynamic>>>{};
    for (final s in _minhas) {
      final status = s['status'] as String? ?? 'pendente';
      porGrupo.putIfAbsent(_grupoDoStatus(status), () => []).add(s);
    }
    final grupos = _gruposStatus
        .where((g) => (porGrupo[g.$1] ?? const []).isNotEmpty)
        .toList();
    return [
      for (final grupo in grupos) ...[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(grupo.$2,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.cinzaTexto)),
        ),
        for (final s in porGrupo[grupo.$1]!) ...[
          _cardSolicitacao(s),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
      ],
    ];
  }

  Widget _cardSolicitacao(Map<String, dynamic> s) {
    final tipo = s['tipo'] as String;
    final status = s['status'] as String? ?? 'pendente';
    final podeExtra = tipo == 'adesao_beneficio' &&
        status != 'concluido' &&
        status != 'cancelado';
    return GestureDetector(
      onTap: () => _abrirDetalhe(s),
      child: Container(
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
                  Text(tituloComCodigo(s, _labelTipoSolicitacao[tipo] ?? tipo),
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
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.cinzaTexto),
          ]),
          if (tipo == 'rota' && status == 'aguardando_escolha') ...[
            const SizedBox(height: 8),
            Text(resumoCotacao(s) ?? '',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.cinzaTexto)),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () async {
                  final escolha = await mostrarEscolhaCotacao(context, s);
                  if (escolha == null) return;
                  final col = _api.colaboradorAtual;
                  if (escolha == 'uber_flash' && col != null && mounted) {
                    // Uber Flash escolhido: abre o pedido de Uber já preenchido
                    // com os dados da rota (o colaborador é o passageiro).
                    final enviado = await showDialog<bool>(
                      context: context,
                      builder: (_) => DialogUber(
                          gestor: col,
                          equipe: [col],
                          api: _api,
                          rotaOrigem: s),
                    );
                    if (enviado == true && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content:
                              Text('Solicitação de Uber enviada ao Facilites.')));
                    }
                  }
                  _carregar();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: _corSolicitacoes,
                    foregroundColor: Colors.white),
                child: const Text('Escolher Frete ou Uber Flash'),
              ),
            ),
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
      ),
    );
  }

  Future<void> _abrirDetalhe(Map<String, dynamic> s) async {
    final atualizou = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogDetalheSolicitacao(
        solicitacao: s,
        notas: _notasPorSolicitacao[s['id'] as int] ?? const [],
        api: _api,
        autorNome: _api.colaboradorAtual?.nome,
      ),
    );
    if (atualizou == true) _carregar();
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

  Widget _statusChip(String status) => _statusChipSolicitacao(status);
}

Widget _statusChipSolicitacao(String status) {
  final (cor, label) = switch (status) {
    'pendente_gestor' => (const Color(0xFFD97706), 'Aguardando gestor'),
    'recusado_gestor' => (const Color(0xFFDC2626), 'Recusada pelo gestor'),
    'aguardando_escolha' => (const Color(0xFF7C3AED), 'Escolha o frete'),
    'em_andamento' => (const Color(0xFF2563EB), 'Em andamento'),
    'concluido' => (const Color(0xFF16A34A), 'Concluído'),
    'cancelado' => (const Color(0xFFDC2626), 'Cancelado'),
    _ => (const Color(0xFFD97706), 'Pendente'),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
        color: cor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
    child: Text(label,
        style: GoogleFonts.poppins(
            fontSize: 11, fontWeight: FontWeight.w700, color: cor)),
  );
}

// ─── Detalhe de uma solicitação: dados enviados + comentários ───────────────

class _DialogDetalheSolicitacao extends StatefulWidget {
  final Map<String, dynamic> solicitacao;
  final List<Map<String, dynamic>> notas;
  final ApiService api;
  final String? autorNome;

  const _DialogDetalheSolicitacao({
    required this.solicitacao,
    required this.notas,
    required this.api,
    this.autorNome,
  });

  @override
  State<_DialogDetalheSolicitacao> createState() =>
      _DialogDetalheSolicitacaoState();
}

class _DialogDetalheSolicitacaoState extends State<_DialogDetalheSolicitacao> {
  final _comentarioCtrl = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviarComentario() async {
    final texto = _comentarioCtrl.text.trim();
    if (texto.isEmpty) return;
    setState(() => _enviando = true);
    try {
      await widget.api.adicionarNotaSolicitacao(
        solicitacaoId: widget.solicitacao['id'] as int,
        texto: texto,
        autorNome: widget.autorNome,
      );
      if (!mounted) return;
      _comentarioCtrl.clear();
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao comentar: $e')));
    }
  }

  String _formatarDataHora(String iso) {
    final d = DateTime.parse(iso).toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$min';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.solicitacao;
    final tipo = s['tipo'] as String;
    final status = s['status'] as String? ?? 'pendente';
    final payload = (s['payload'] as Map?)?.cast<String, dynamic>() ?? {};

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 620),
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(_iconeTipoSolicitacao[tipo] ?? Icons.assignment_outlined,
                      color: _corSolicitacoes, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(tituloComCodigo(s, _labelTipoSolicitacao[tipo] ?? tipo),
                        style: GoogleFonts.poppins(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark)),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: Text(
                        'Aberta em ${_formatarDataHora(s['criado_em'] as String)}',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.cinzaTexto)),
                  ),
                  _statusChipSolicitacao(status),
                ]),
                if (s['motivo_recusa_gestor'] != null) ...[
                  const SizedBox(height: 8),
                  Text('Motivo da recusa: ${s['motivo_recusa_gestor']}',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.erro)),
                ],
                const SizedBox(height: 16),
                Text('O que você enviou',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.cinzaTexto)),
                const SizedBox(height: 6),
                PayloadSolicitacaoView(payload: payload),
                if (resumoCotacao(s) != null) ...[
                  const SizedBox(height: 10),
                  Text(resumoCotacao(s)!,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: const Color(0xFF92400E))),
                ],
                const SizedBox(height: 16),
                Text('Comentários',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.cinzaTexto)),
                const SizedBox(height: 6),
                if (widget.notas.isEmpty)
                  Text('Nenhum comentário ainda.',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.cinzaTexto))
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: widget.notas
                          .map((n) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: RichText(
                                  text: TextSpan(
                                    style: GoogleFonts.poppins(
                                        fontSize: 11.5, color: AppColors.dark),
                                    children: [
                                      TextSpan(
                                        text:
                                            '${_formatarDataHora(n['criado_em'] as String)}'
                                            '${n['autor_nome'] != null ? ' · ${n['autor_nome']}' : ''} — ',
                                        style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.cinzaTexto),
                                      ),
                                      TextSpan(text: n['texto'] as String),
                                    ],
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _comentarioCtrl,
                      style: GoogleFonts.poppins(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Escrever um comentário...',
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 13, color: Colors.grey.shade400),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      onSubmitted: (_) => _enviarComentario(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _enviando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          onPressed: _enviarComentario,
                          icon: const Icon(Icons.send_rounded,
                              color: _corSolicitacoes),
                          tooltip: 'Comentar',
                        ),
                ]),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Fechar')),
                ),
              ],
            ),
          ),
        ),
      ),
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
    return SolicitacaoDialogShell(
      titulo: 'Comunicado Interno',
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        CampoRotulado(
          label: 'Tipo de material',
          child: DropdownButtonFormField<String>(
            value: _tipo,
            isExpanded: true,
            decoration: decoracaoCampo(),
            items: _tiposComunicado.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _tipo = v),
          ),
        ),
        CampoRotulado(
          label: 'Qual o objetivo do material?',
          child: TextField(controller: _objetivoCtrl, maxLines: 2, decoration: decoracaoCampo()),
        ),
        CampoRotulado(
          label: 'Qual texto acompanhará o material?',
          child: TextField(controller: _textoCtrl, maxLines: 3, decoration: decoracaoCampo()),
        ),
        CampoRotulado(
          label: 'Observações importantes (opcional)',
          child: TextField(controller: _obsCtrl, maxLines: 2, decoration: decoracaoCampo()),
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
          if (formatarDataAdmissao(widget.colab.dataAdmissao) != null)
            'Data de admissão': formatarDataAdmissao(widget.colab.dataAdmissao),
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
    return SolicitacaoDialogShell(
      titulo: 'Solicitação de Crachá',
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        CampoRotulado(
          label: 'Motivo',
          child: DropdownButtonFormField<String>(
            value: _motivo,
            decoration: decoracaoCampo(),
            items: _motivosCracha.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _motivo = v),
          ),
        ),
        CampoRotulado(
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
    return SolicitacaoDialogShell(
      titulo: 'Solicitar Treinamento',
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        CampoRotulado(label: 'Público-alvo', child: TextField(controller: _publicoCtrl, decoration: decoracaoCampo())),
        CampoRotulado(label: 'Tema', child: TextField(controller: _temaCtrl, decoration: decoracaoCampo())),
        CampoRotulado(
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
        CampoRotulado(
          label: 'Descrição prévia de tópicos e temas',
          child: TextField(controller: _descricaoCtrl, maxLines: 3, decoration: decoracaoCampo()),
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

class DialogRota extends StatefulWidget {
  final ColaboradorModel colab;
  final ApiService api;

  /// Gestor abrindo a rota (Facilites): não precisa da aprovação de outro gestor.
  final bool comoGestor;
  const DialogRota(
      {super.key,
      required this.colab,
      required this.api,
      this.comoGestor = false});

  @override
  State<DialogRota> createState() => _DialogRotaState();
}

class _DialogRotaState extends State<DialogRota> {
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
  final _valorRecolhimentoCtrl = TextEditingController();
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
    _valorRecolhimentoCtrl.dispose();
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
    final valorRecolhimento = double.tryParse(
        _valorRecolhimentoCtrl.text.trim().replaceAll(',', '.'));
    if (_recolhimentoValor &&
        (valorRecolhimento == null || valorRecolhimento <= 0)) {
      setState(() => _erro = 'Informe o valor a ser recolhido.');
      return;
    }
    if (!widget.comoGestor &&
        (widget.colab.setor == null || widget.colab.setor!.isEmpty)) {
      setState(() => _erro = 'Você não tem um setor definido. Fale com o RH.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final gestor = widget.comoGestor
          ? widget.colab
          : await widget.api.buscarGestorDoSetor(
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
          if (_recolhimentoValor)
            'Valor a recolher':
                'R\$ ${valorRecolhimento!.toStringAsFixed(2).replaceAll('.', ',')}',
          'Justificativa': _justificativaCtrl.text.trim(),
        },
        abertoPorId: widget.colab.id,
        abertoPorNome: widget.colab.nome,
        abertoPorPapel: widget.comoGestor ? 'gestor' : 'colaborador',
        setor: widget.colab.setor,
        requerAprovacaoGestor: !widget.comoGestor,
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
    return SolicitacaoDialogShell(
      titulo: 'Solicitar Rota',
      subtitulo: widget.comoGestor
          ? 'Vai direto para o Facilites.'
          : 'Vai passar pela aprovação do seu gestor antes de ir para o Facilites.',
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        Row(children: [
          Expanded(
            child: CampoRotulado(
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
            child: CampoRotulado(
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
        CampoRotulado(
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
        CampoRotulado(label: 'Nome do local de saída', child: TextField(controller: _localSaidaNomeCtrl, decoration: decoracaoCampo())),
        CampoRotulado(label: 'Endereço de saída', child: TextField(controller: _localSaidaEnderecoCtrl, decoration: decoracaoCampo())),
        CampoRotulado(label: 'Nome do local de destino', child: TextField(controller: _localDestinoNomeCtrl, decoration: decoracaoCampo())),
        CampoRotulado(label: 'Endereço de destino', child: TextField(controller: _localDestinoEnderecoCtrl, decoration: decoracaoCampo())),
        CampoRotulado(label: 'Descrição da tarefa', child: TextField(controller: _descricaoTarefaCtrl, maxLines: 2, decoration: decoracaoCampo())),
        CampoRotulado(label: 'Procurar por (opcional)', child: TextField(controller: _procurarPorCtrl, decoration: decoracaoCampo())),
        CampoRotulado(
          label: 'Recolhimento de valor?',
          child: SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('Sim')), ButtonSegment(value: false, label: Text('Não'))],
            selected: {_recolhimentoValor},
            onSelectionChanged: (v) => setState(() => _recolhimentoValor = v.first),
          ),
        ),
        if (_recolhimentoValor)
          CampoRotulado(
            label: 'Valor a ser recolhido (R\$)',
            child: TextField(
              controller: _valorRecolhimentoCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: decoracaoCampo(hint: '0,00'),
            ),
          ),
        CampoRotulado(label: 'Justificativa', child: TextField(controller: _justificativaCtrl, maxLines: 2, decoration: decoracaoCampo())),
        CampoRotulado(
          label: 'Conta razão (serviços profissionais contratados)',
          child: DropdownButtonFormField<String>(
            value: _contaRazao,
            isExpanded: true,
            decoration: decoracaoCampo(),
            items: _contasRazaoRota.entries.map((e) => DropdownMenuItem(value: e.key, child: Text('${e.key} - ${e.value}'))).toList(),
            onChanged: (v) => setState(() => _contaRazao = v),
          ),
        ),
      ],
    );
  }
}

// ─── Incentivo Educacional (direto para o DP, sem aprovação do gestor) ──────

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
    setState(() {
      _enviando = true;
      _erro = null;
    });

    try {
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
          if (formatarDataAdmissao(widget.colab.dataAdmissao) != null)
            'Data de admissão': formatarDataAdmissao(widget.colab.dataAdmissao),
          'Justificativa': _justificativaCtrl.text.trim(),
          'Comprovante': anexoUrl,
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
    return SolicitacaoDialogShell(
      titulo: 'Incentivo Educacional',
      subtitulo: 'Cai direto na fila do DP (é só o comprovante de uso do incentivo).',
      erro: _erro,
      enviando: _enviando,
      onEnviar: _enviar,
      campos: [
        CampoRotulado(
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
        CampoRotulado(
          label: 'Justificativa',
          child: TextField(
            controller: _justificativaCtrl,
            maxLines: 3,
            decoration: decoracaoCampo(hint: 'Explique o motivo do pedido'),
          ),
        ),
      ],
    );
  }
}
