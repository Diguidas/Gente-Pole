import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const _corTi = Color(0xFFE64A19);

const _etapasBoard = [
  'Triagem',
  'Backlog',
  'Em Andamento',
  'Liberado para Desenvolvimento',
  'Desenvolvimento',
  'Aguard. Def. Usuário',
  'Aguardando Fornecedor',
  'Validação Funcional',
  'Validação de Usuário',
  'Em Correção',
  'Concluído',
];

class ChamadoTiDetalheScreen extends StatefulWidget {
  final Map<String, dynamic> chamado;
  final String solicitanteNome;
  const ChamadoTiDetalheScreen({super.key, required this.chamado, required this.solicitanteNome});

  @override
  State<ChamadoTiDetalheScreen> createState() => _ChamadoTiDetalheScreenState();
}

class _ChamadoTiDetalheScreenState extends State<ChamadoTiDetalheScreen> {
  final _api = ApiService();
  final _comentarioCtrl = TextEditingController();
  Map<String, dynamic>? _info;
  List<Map<String, dynamic>> _comentariosExtra = [];
  PlatformFile? _anexo;
  bool _loading = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final workItemId = widget.chamado['azure_work_item_id'] as int;
    final status = await _api.buscarStatusChamadosAzure([workItemId]);
    if (!mounted) return;
    setState(() {
      _info = status[workItemId.toString()] as Map<String, dynamic>?;
      // Os comentários "extra" (otimistas, adicionados na hora do envio)
      // já vêm de volta dentro de `_info.comentarios` assim que recarrega
      // do Azure — mantê-los aqui duplicaria a mensagem na tela.
      _comentariosExtra = [];
      _loading = false;
    });
  }

  String _etapaLimpa(String coluna) => coluna.replaceFirst(RegExp(r'^\d+-\s*'), '').trim();

  int _indiceEtapa(String? coluna, String? estado) {
    if (coluna != null) {
      final limpa = _etapaLimpa(coluna);
      final i = _etapasBoard.indexWhere((e) => e.toLowerCase() == limpa.toLowerCase());
      if (i != -1) return i;
    }
    if (estado == 'Closed') return _etapasBoard.length - 1;
    return 0;
  }

  Color _corEtapa(int indice, bool concluido) {
    if (concluido) return AppColors.sucesso;
    if (indice == 0) return AppColors.cinzaTexto;
    return _corTi;
  }

  Color _corUrgencia(String? nivel) {
    if (nivel == null) return AppColors.cinzaTexto;
    if (nivel.startsWith('1')) return AppColors.erro;
    if (nivel.startsWith('2')) return const Color(0xFFF97316);
    if (nivel.startsWith('3')) return const Color(0xFFEAB308);
    return AppColors.sucesso;
  }

  String _semHtml(String html) => html.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  String _formatarData(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final data = DateTime.tryParse(iso);
    if (data == null) return '';
    final local = data.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} às '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _escolherAnexo() async {
    final resultado = await FilePicker.platform.pickFiles(withData: true);
    if (!mounted) return;
    if (resultado != null && resultado.files.isNotEmpty) {
      setState(() => _anexo = resultado.files.first);
    }
  }

  Future<void> _enviarComentario() async {
    final texto = _comentarioCtrl.text.trim();
    final anexo = _anexo;
    if (texto.isEmpty && anexo == null) return;
    setState(() => _enviando = true);
    try {
      final workItemId = widget.chamado['azure_work_item_id'] as int;
      final anexoUrl = await _api.comentarChamadoAzureTI(
        workItemId: workItemId,
        texto: texto,
        anexoBytes: anexo?.bytes != null ? Uint8List.fromList(anexo!.bytes!) : null,
        anexoNomeArquivo: anexo?.name,
      );
      if (!mounted) return;
      setState(() {
        _comentariosExtra = [
          ..._comentariosExtra,
          {
            'texto': texto,
            'autor': widget.solicitanteNome,
            'data': DateTime.now().toIso8601String(),
            'viaApp': true,
            'anexoUrl': anexoUrl,
            'anexoNome': anexo?.name,
          },
        ];
        _comentarioCtrl.clear();
        _anexo = null;
        _enviando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Não foi possível enviar: $e', style: AppTextStyles.corpoBranco),
        backgroundColor: AppColors.erro,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Widget _linha(String rotulo, String? valor, {IconData? icone}) {
    if (valor == null || valor.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone ?? Icons.circle, size: 14, color: AppColors.cinzaTexto),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rotulo, style: AppTextStyles.corpoMinimo.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(valor, style: AppTextStyles.corpoNormal),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chamado = widget.chamado;
    final info = _info;
    final workItemId = chamado['azure_work_item_id'] as int;
    final estado = info?['state'] as String?;
    final coluna = info?['boardColumn'] as String?;
    final comentarios = [
      ...(info?['comentarios'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      ..._comentariosExtra,
    ];
    final descricao = info != null ? _semHtml((info['descricao'] as String?) ?? '') : (chamado['descricao'] as String? ?? '');
    final tipoSolicitacao = (info?['tipoSolicitacao'] as String?) ?? (chamado['tipo_solicitacao'] as String?);
    final departamento = (info?['departamento'] as String?) ?? (chamado['departamento'] as String?);
    final nivelUrgencia = (info?['nivelUrgencia'] as String?) ?? (chamado['nivel_urgencia'] as String?);
    final concluido = estado == 'Closed' || _etapaLimpa(coluna ?? '') == 'Concluído';
    final etapaAtual = coluna != null ? _etapaLimpa(coluna) : (estado ?? 'Carregando...');
    final indice = _indiceEtapa(coluna, estado);
    final progresso = (indice + 1) / _etapasBoard.length;
    final cor = _corEtapa(indice, concluido);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _corTi,
        title: Text(chamado['titulo'] as String? ?? 'Chamado #$workItemId', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _corTi))
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('#$workItemId', style: AppTextStyles.corpoMinimo),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (tipoSolicitacao?.isNotEmpty == true) _Tag(texto: tipoSolicitacao!),
                            if (departamento?.isNotEmpty == true) _Tag(texto: departamento!),
                            if (nivelUrgencia != null) _Tag(texto: nivelUrgencia, cor: _corUrgencia(nivelUrgencia)),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Icon(concluido ? Icons.check_circle_rounded : Icons.autorenew_rounded, size: 16, color: cor),
                            const SizedBox(width: 6),
                            Text(etapaAtual, style: AppTextStyles.corpoMedio.copyWith(color: cor, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LinearProgressIndicator(
                            value: progresso,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFE5E7EB),
                            valueColor: AlwaysStoppedAnimation(cor),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (descricao.isNotEmpty) ...[
                          Text('Descrição', style: AppTextStyles.corpoMenor.copyWith(fontWeight: FontWeight.w700, color: AppColors.dark)),
                          const SizedBox(height: 6),
                          Text(descricao, style: AppTextStyles.corpoCinza.copyWith(height: 1.4)),
                          const SizedBox(height: 20),
                        ],
                        if (info != null) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: AppColors.cinzaClaro, borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Preenchido pela TI',
                                    style: AppTextStyles.corpoMenor.copyWith(fontWeight: FontWeight.w700, color: AppColors.dark)),
                                const SizedBox(height: 12),
                                _linha('Responsável', info['responsavelAtribuido'] as String?, icone: Icons.person_outline_rounded),
                                _linha('Complexidade', info['complexidade'] as String?, icone: Icons.speed_outlined),
                                _linha('Desenvolvedor', info['desenvolvedor'] as String?, icone: Icons.code_rounded),
                                _linha('Objetivo', info['objetivo'] as String?, icone: Icons.flag_outlined),
                                _linha('Contato', info['contato'] as String?, icone: Icons.phone_outlined),
                                _linha('Satisfação do cliente', info['satisfacaoCliente'] as String?,
                                    icone: Icons.sentiment_satisfied_outlined),
                                _linha(
                                    'Prazo',
                                    _formatarData(info['prazo'] as String?).isEmpty ? null : _formatarData(info['prazo'] as String?),
                                    icone: Icons.event_outlined),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        Text('Conversa (${comentarios.length})',
                            style: AppTextStyles.corpoMenor.copyWith(fontWeight: FontWeight.w700, color: AppColors.dark)),
                        const SizedBox(height: 8),
                        if (comentarios.isEmpty)
                          Text('Ainda sem comentários.', style: AppTextStyles.corpoCinza)
                        else
                          ...comentarios.map((com) {
                            final autor = com['autor'] as String? ?? 'TI';
                            final mine = com['viaApp'] == true;
                            final anexoUrl = com['anexoUrl'] as String?;
                            final anexoNome = com['anexoNome'] as String?;
                            final textoLimpo = com['texto'] is String ? _semHtml(com['texto'] as String) : '';
                            return _CardComentario(
                              mine: mine,
                              autor: autor,
                              texto: textoLimpo,
                              hora: _formatarData(com['data'] as String?),
                              anexoUrl: anexoUrl,
                              anexoNome: anexoNome,
                            );
                          }),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Column(
                        children: [
                          if (_anexo != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(color: AppColors.cinzaClaro, borderRadius: BorderRadius.circular(20)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.attach_file_rounded, size: 14, color: _corTi),
                                      const SizedBox(width: 6),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 180),
                                        child: Text(_anexo!.name, overflow: TextOverflow.ellipsis, style: AppTextStyles.corpoMinimo),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () => setState(() => _anexo = null),
                                        child: const Icon(Icons.close_rounded, size: 14, color: AppColors.cinzaTexto),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              IconButton(
                                onPressed: _enviando ? null : _escolherAnexo,
                                icon: Icon(Icons.attach_file_rounded, size: 20, color: _anexo == null ? AppColors.cinzaTexto : _corTi),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _comentarioCtrl,
                                  minLines: 1,
                                  maxLines: 3,
                                  decoration: InputDecoration(
                                    hintText: 'Escreva um comentário...',
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: _enviando ? null : _enviarComentario,
                                style: IconButton.styleFrom(
                                  backgroundColor: _corTi,
                                  padding: const EdgeInsets.all(12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: _enviando
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String texto;
  final Color? cor;
  const _Tag({required this.texto, this.cor});

  @override
  Widget build(BuildContext context) {
    final c = cor ?? AppColors.cinzaTexto;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(.12), borderRadius: BorderRadius.circular(20)),
      child: Text(texto, style: AppTextStyles.corpoMinimo.copyWith(fontWeight: FontWeight.w600, color: c)),
    );
  }
}

class _CardComentario extends StatelessWidget {
  final bool mine;
  final String autor;
  final String texto;
  final String hora;
  final String? anexoUrl;
  final String? anexoNome;

  const _CardComentario({
    required this.mine,
    required this.autor,
    required this.texto,
    required this.hora,
    this.anexoUrl,
    this.anexoNome,
  });

  @override
  Widget build(BuildContext context) {
    final corFaixa = mine ? _corTi : const Color(0xFF16A34A);
    final corFundo = mine ? _corTi.withOpacity(.06) : const Color(0xFF16A34A).withOpacity(.06);

    final faixa = Container(width: 3, color: corFaixa);
    final conteudo = Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(autor, style: AppTextStyles.corpoMenor.copyWith(fontWeight: FontWeight.w700, color: corFaixa)),
                const SizedBox(width: 6),
                Text(mine ? '· solicitante' : '· TI', style: AppTextStyles.corpoMinimo),
                const Spacer(),
                if (hora.isNotEmpty) Text(hora, style: AppTextStyles.corpoMinimo),
              ],
            ),
            if (texto.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(texto, style: AppTextStyles.corpoNormal.copyWith(height: 1.35)),
            ],
            if (anexoUrl != null) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () => launchUrl(Uri.parse(anexoUrl!), mode: LaunchMode.externalApplication),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.attach_file_rounded, size: 14, color: corFaixa),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(anexoNome ?? 'Anexo',
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.corpoMenor.copyWith(color: corFaixa, decoration: TextDecoration.underline)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: corFundo, borderRadius: BorderRadius.circular(10)),
      child: Row(children: mine ? [conteudo, faixa] : [faixa, conteudo]),
    );
  }
}
