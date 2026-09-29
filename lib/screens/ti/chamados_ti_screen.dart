import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import 'chamado_ti_detalhe_screen.dart';
import 'novo_chamado_ti_screen.dart';

const _corTi = Color(0xFFE64A19);
const _corTiEscuro = Color(0xFFC2410C);

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

class ChamadosTiScreen extends StatefulWidget {
  /// Work item id vindo de uma notificação push (deep link) — se
  /// presente, assim que a lista carregar já abre o detalhe desse
  /// chamado direto, sem o colaborador precisar procurar na lista.
  final int? workItemIdParaAbrir;

  const ChamadosTiScreen({super.key, this.workItemIdParaAbrir});

  @override
  State<ChamadosTiScreen> createState() => _ChamadosTiScreenState();
}

class _ChamadosTiScreenState extends State<ChamadosTiScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _chamados = [];
  Map<String, dynamic> _status = {};
  Set<int> _avaliados = {};
  bool _loading = true;
  bool _jaAbriuDeepLink = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final chamados = await _api.listarMeusChamadosTI();
    final ids = chamados.map((c) => c['azure_work_item_id'] as int).toList();
    final status = await _api.buscarStatusChamadosAzure(ids);
    final avaliados = await _api.listarChamadosTIAvaliados(ids);
    if (!mounted) return;
    setState(() {
      _chamados = chamados;
      _status = status;
      _avaliados = avaliados;
      _loading = false;
    });

    final idParaAbrir = widget.workItemIdParaAbrir;
    if (idParaAbrir != null && !_jaAbriuDeepLink) {
      final chamado = chamados.firstWhere(
        (c) => c['azure_work_item_id'] == idParaAbrir,
        orElse: () => const {},
      );
      if (chamado.isNotEmpty) {
        _jaAbriuDeepLink = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _abrirDetalhe(chamado));
      }
    }
  }

  Future<void> _abrirAvaliacao({required int workItemId, required String titulo}) async {
    final avaliado = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogAvaliacao(workItemId: workItemId, titulo: titulo),
    );
    if (avaliado == true) _carregar();
  }

  /// Primeiro chamado concluído e ainda não avaliado, se houver — usado
  /// pra travar a abertura de um novo chamado até avaliar o anterior.
  Map<String, dynamic>? get _chamadoAguardandoAvaliacao {
    for (final c in _chamados) {
      final workItemId = c['azure_work_item_id'] as int;
      final info = _status[workItemId.toString()] as Map<String, dynamic>?;
      final estado = info?['state'] as String?;
      final coluna = info?['boardColumn'] as String?;
      final concluido = estado == 'Closed' || _etapaLimpa(coluna ?? '') == 'Concluído';
      if (concluido && !_avaliados.contains(workItemId)) return c;
    }
    return null;
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

  Widget _tagInfo(String texto, {Color? cor}) {
    final c = cor ?? AppColors.cinzaTexto;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(.12), borderRadius: BorderRadius.circular(20)),
      child: Text(texto, style: AppTextStyles.corpoMinimo.copyWith(fontWeight: FontWeight.w600, color: c)),
    );
  }

  Future<void> _abrirNovoChamado() async {
    final chamadoPendente = _chamadoAguardandoAvaliacao;
    if (chamadoPendente != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Avalie o chamado anterior antes de abrir um novo.', style: AppTextStyles.corpoBranco),
        backgroundColor: AppColors.erro,
        behavior: SnackBarBehavior.floating,
      ));
      await _abrirAvaliacao(
        workItemId: chamadoPendente['azure_work_item_id'] as int,
        titulo: chamadoPendente['titulo'] as String? ?? 'Chamado #${chamadoPendente['azure_work_item_id']}',
      );
      return;
    }
    final escolha = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _EscolhaTipoChamadoSheet(),
    );
    if (escolha == null) return;
    final erroGentePole = escolha == 'erro_gente_pole';
    final aberto = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => NovoChamadoTiScreen(erroGentePole: erroGentePole)),
    );
    if (aberto == true) {
      _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Chamado aberto com sucesso!', style: AppTextStyles.corpoBranco),
        backgroundColor: AppColors.sucesso,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _abrirDetalhe(Map<String, dynamic> chamado) async {
    final workItemId = chamado['azure_work_item_id'] as int?;
    if (workItemId != null) _api.marcarChamadoTIVisto(workItemId);
    final nome = _api.colaboradorAtual?.nome ?? '';
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChamadoTiDetalheScreen(chamado: chamado, solicitanteNome: nome)),
    );
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _corTi,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [_corTi, _corTiEscuro], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
        title: const Text('Chamados de TI'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirNovoChamado,
        backgroundColor: _corTi,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Novo chamado', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _corTi))
          : _chamados.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.build_outlined, size: 48, color: AppColors.cinzaTexto),
                        const SizedBox(height: 12),
                        Text('Você ainda não abriu nenhum chamado.', style: AppTextStyles.corpoCinza, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    itemCount: _chamados.length,
                    itemBuilder: (_, i) {
                      final c = _chamados[i];
                      final workItemId = c['azure_work_item_id'] as int;
                      final info = _status[workItemId.toString()] as Map<String, dynamic>?;
                      final estado = info?['state'] as String?;
                      final coluna = info?['boardColumn'] as String?;
                      final comentarios = (info?['comentarios'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                      final tipoSolicitacao = (info?['tipoSolicitacao'] as String?) ?? (c['tipo_solicitacao'] as String?);
                      final departamento = (info?['departamento'] as String?) ?? (c['departamento'] as String?);
                      final nivelUrgencia = (info?['nivelUrgencia'] as String?) ?? (c['nivel_urgencia'] as String?);
                      final concluido = estado == 'Closed' || _etapaLimpa(coluna ?? '') == 'Concluído';
                      final etapaAtual = coluna != null ? _etapaLimpa(coluna) : (estado ?? 'Carregando...');
                      final indiceEtapa = _indiceEtapa(coluna, estado);
                      final progresso = (indiceEtapa + 1) / _etapasBoard.length;
                      final corEtapa = _corEtapa(indiceEtapa, concluido);
                      final pedeAvaliacao = concluido && !_avaliados.contains(workItemId);
                      final temNovidade = c['notificacao_pendente'] as bool? ?? false;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _abrirDetalhe(c),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (temNovidade)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.only(top: 5, right: 8),
                                          decoration: const BoxDecoration(color: AppColors.erro, shape: BoxShape.circle),
                                        ),
                                      Expanded(
                                        child: Text(c['titulo'] as String? ?? '—',
                                            style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w700, fontSize: 14.5)),
                                      ),
                                      Text('#$workItemId', style: AppTextStyles.corpoMinimo),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      if (tipoSolicitacao?.isNotEmpty == true) _tagInfo(tipoSolicitacao!),
                                      if (departamento?.isNotEmpty == true) _tagInfo(departamento!),
                                      if (nivelUrgencia != null) _tagInfo(nivelUrgencia, cor: _corUrgencia(nivelUrgencia)),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(color: corEtapa.withOpacity(.07), borderRadius: BorderRadius.circular(10)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(concluido ? Icons.check_circle_rounded : Icons.autorenew_rounded, size: 15, color: corEtapa),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(etapaAtual,
                                                  style: AppTextStyles.corpoMedio.copyWith(color: corEtapa, fontWeight: FontWeight.w700)),
                                            ),
                                            if (comentarios.isNotEmpty) ...[
                                              const Icon(Icons.forum_outlined, size: 13, color: AppColors.cinzaTexto),
                                              const SizedBox(width: 3),
                                              Text('${comentarios.length}', style: AppTextStyles.corpoMinimo),
                                              const SizedBox(width: 6),
                                            ],
                                            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.cinzaTexto),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(20),
                                          child: LinearProgressIndicator(
                                            value: progresso,
                                            minHeight: 6,
                                            backgroundColor: Colors.white,
                                            valueColor: AlwaysStoppedAnimation(corEtapa),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (pedeAvaliacao) ...[
                                    const SizedBox(height: 10),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => _abrirAvaliacao(
                                          workItemId: workItemId, titulo: c['titulo'] as String? ?? 'Chamado #$workItemId'),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFDF4E3),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(.3)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.star_rate_rounded, size: 18, color: Color(0xFFF59E0B)),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text('Avalie o atendimento deste chamado',
                                                  style: AppTextStyles.corpoMenor
                                                      .copyWith(fontWeight: FontWeight.w600, color: AppColors.dark)),
                                            ),
                                            const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFFF59E0B)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

/// Primeiro passo do "Novo chamado": escolher entre abrir um card normal
/// pra Sistemas Corporativos e Dados ou reportar um erro do próprio Gente
/// Pole (que já sai endereçado e priorizado, sem o colaborador escolher
/// responsável/tipo/urgência).
class _EscolhaTipoChamadoSheet extends StatelessWidget {
  const _EscolhaTipoChamadoSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text('Novo chamado',
                style: AppTextStyles.corpoMedio.copyWith(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.dark)),
            const SizedBox(height: 16),
            _OpcaoNovoChamado(
              icone: Icons.confirmation_number_outlined,
              titulo: 'Abertura de card',
              descricao: 'Ajuda com a equipe de sistemas corporativos e dados',
              onTap: () => Navigator.of(context).pop('abertura_card'),
            ),
            const SizedBox(height: 12),
            _OpcaoNovoChamado(
              icone: Icons.bug_report_outlined,
              titulo: 'Erro no Gente Pole',
              descricao: 'Ajuda com erro encontrado dentro do sistema Gente Pole',
              onTap: () => Navigator.of(context).pop('erro_gente_pole'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpcaoNovoChamado extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String descricao;
  final VoidCallback onTap;

  const _OpcaoNovoChamado({
    required this.icone,
    required this.titulo,
    required this.descricao,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cinzaClaro,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _corTi.withOpacity(.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icone, size: 20, color: _corTi),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: AppTextStyles.corpoMedio.copyWith(
                          fontWeight: FontWeight.w700, color: AppColors.dark)),
                  const SizedBox(height: 2),
                  Text(descricao,
                      style: AppTextStyles.corpoMinimo.copyWith(color: AppColors.cinzaTexto)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.cinzaTexto),
          ]),
        ),
      ),
    );
  }
}

class _DialogAvaliacao extends StatefulWidget {
  final int workItemId;
  final String titulo;
  const _DialogAvaliacao({required this.workItemId, required this.titulo});

  @override
  State<_DialogAvaliacao> createState() => _DialogAvaliacaoState();
}

class _DialogAvaliacaoState extends State<_DialogAvaliacao> {
  final _comentarioCtrl = TextEditingController();
  int? _nota;
  bool _enviando = false;

  static const _rotulos = {
    1: 'Muito insatisfeito',
    2: 'Insatisfeito',
    3: 'Neutro',
    4: 'Satisfeito',
    5: 'Muito satisfeito',
  };

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_nota == null) return;
    setState(() => _enviando = true);
    try {
      await ApiService().avaliarChamadoTI(
        workItemId: widget.workItemId,
        nota: _nota!,
        comentario: _comentarioCtrl.text,
      );
      if (mounted) Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Como foi o atendimento?', style: AppTextStyles.tituloPequeno),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.titulo, style: AppTextStyles.corpoCinza, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 14),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  final valor = i + 1;
                  final marcada = _nota != null && valor <= _nota!;
                  return IconButton(
                    onPressed: () => setState(() => _nota = valor),
                    icon: Icon(
                      marcada ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 32,
                      color: const Color(0xFFF59E0B),
                    ),
                  );
                }),
              ),
            ),
            if (_nota != null)
              Center(
                child: Text(_rotulos[_nota]!,
                    style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _comentarioCtrl,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Quer contar mais alguma coisa? (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Agora não', style: TextStyle(color: AppColors.cinzaTexto)),
        ),
        ElevatedButton(
          onPressed: (_nota == null || _enviando) ? null : _enviar,
          style: ElevatedButton.styleFrom(backgroundColor: _corTi),
          child: _enviando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Enviar', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
