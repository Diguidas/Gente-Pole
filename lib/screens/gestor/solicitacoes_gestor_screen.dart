import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';
import '../solicitacoes/solicitacoes_screen.dart' show PayloadSolicitacaoView;

const Map<String, String> _labelTipoSolicitacaoAprovacao = {
  'incentivo_educacional': 'Incentivo Educacional',
  'rota': 'Rota',
};

const Map<String, String> _labelTipoSolicitacaoGestor = {
  'moveis_administrativos': 'Móveis Administrativos',
  'swile': 'Swile',
  'uber': 'Uber',
  'adiantamento_13': 'Adiantamento de 13º',
};

const Map<String, IconData> _iconeTipoSolicitacaoGestor = {
  'moveis_administrativos': Icons.chair_outlined,
  'swile': Icons.card_giftcard_outlined,
  'uber': Icons.local_taxi_outlined,
  'adiantamento_13': Icons.payments_outlined,
};

/// Tipos gestor que pedem selecionar 1 colaborador da equipe.
const Set<String> _tiposComColabUnico = {'moveis_administrativos', 'adiantamento_13'};

/// Tipos gestor que pedem selecionar vários colaboradores da equipe.
const Set<String> _tiposComColabMultiplo = {'swile'};

/// Campos extras de texto por tipo — simplificação do formulário completo
/// do web (que tem seletores de unidade/aeroporto/endereço no Uber e
/// dropdowns fixos em Móveis) em favor de campos de texto livre.
const Map<String, List<(String label, bool multilinha)>> _camposPorTipoGestor = {
  'moveis_administrativos': [
    ('Tipo de solicitação (Material ou Serviço)', false),
    ('Ordem de investimento', false),
    ('Descrição', true),
    ('Referência (link)', false),
  ],
  'uber': [
    ('Data da corrida', false),
    ('Passageiro (nome e matrícula)', false),
    ('E-mail Uber do passageiro', false),
    ('Trajeto', false),
    ('Partida', false),
    ('Destino', false),
    ('Centro de custo solicitante', false),
    ('Observação', true),
  ],
  'adiantamento_13': [],
  'swile': [],
};

enum _AbaGestor { novo, pendentes, historico }

/// "Solicitações" do gestor — contrapartida de [SolicitacoesScreen]
/// (colaborador). Porta `solicitacoes_gestor_screen.dart` do gentepole_admin:
/// abre pedidos que não passam por aprovação (Móveis, Swile, Uber,
/// Adiantamento de 13º) e aprova/recusa os que exigem aprovação do gestor
/// (Incentivo Educacional e Rota), abertos pelos membros da equipe.
class SolicitacoesGestorScreen extends StatefulWidget {
  const SolicitacoesGestorScreen({super.key});

  @override
  State<SolicitacoesGestorScreen> createState() => _SolicitacoesGestorScreenState();
}

class _SolicitacoesGestorScreenState extends State<SolicitacoesGestorScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _todas = [];
  List<ColaboradorModel> _equipe = [];
  _AbaGestor _aba = _AbaGestor.pendentes;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final gestor = _api.colaboradorAtual;
    if (gestor == null) {
      setState(() => _loading = false);
      return;
    }
    final equipe = await _api.buscarMinhaEquipe();
    // Junta o que precisa da aprovação dele (gestorId) com o que ele mesmo
    // abriu direto (Móveis, Swile, Uber, Adiantamento de 13º).
    final results = await Future.wait([
      _api.listarSolicitacoes(gestorId: gestor.id),
      _api.listarSolicitacoes(abertoPorId: gestor.id),
    ]);
    final porId = <int, Map<String, dynamic>>{};
    for (final lista in results) {
      for (final s in lista) {
        porId[s['id'] as int] = s;
      }
    }
    final todas = porId.values.toList()
      ..sort((a, b) =>
          (b['criado_em'] as String).compareTo(a['criado_em'] as String));
    if (!mounted) return;
    setState(() {
      _equipe = equipe;
      _todas = todas;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _pendentes =>
      _todas.where((s) => s['status'] == 'pendente_gestor').toList();

  List<Map<String, dynamic>> get _historico =>
      _todas.where((s) => s['status'] != 'pendente_gestor').toList();

  Future<void> _abrirFormulario(String tipo) async {
    final gestor = _api.colaboradorAtual;
    if (gestor == null) return;
    final enviado = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _DialogSolicitacaoGestor(tipo: tipo, equipe: _equipe, api: _api),
    );
    if (enviado == true) _carregar();
  }

  Future<void> _aprovar(Map<String, dynamic> s) async {
    await _api.aprovarSolicitacaoGestor(s['id'] as int);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Solicitação aprovada e enviada ao RH.'),
        backgroundColor: AppColors.sucesso,
      ));
    }
    _carregar();
  }

  void _recusar(Map<String, dynamic> s) {
    final motivoCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Recusar solicitação',
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_labelTipoSolicitacaoAprovacao[s['tipo']] ?? s['tipo'] as String,
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.laranja)),
            const SizedBox(height: 4),
            Text('Aberto por ${s['aberto_por_nome']}',
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
            const SizedBox(height: 16),
            TextField(
              controller: motivoCtrl,
              maxLines: 3,
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Motivo da recusa (opcional)',
                hintStyle: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancelar', style: GoogleFonts.poppins(color: AppColors.cinzaTexto)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _api.recusarSolicitacaoGestor(
                s['id'] as int,
                motivo: motivoCtrl.text.trim().isEmpty ? null : motivoCtrl.text.trim(),
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Solicitação recusada.'),
                  backgroundColor: AppColors.erro,
                ));
              }
              _carregar();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.erro, foregroundColor: Colors.white),
            child: const Text('Recusar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _aba == _AbaGestor.historico ? _historico : _pendentes;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.laranja))
          : RefreshIndicator(
              onRefresh: _carregar,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Row(children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: AppColors.dark, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Text('Solicitações',
                              style: GoogleFonts.poppins(
                                  fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.dark)),
                        ]),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          _tabBtn('Novo pedido', _aba == _AbaGestor.novo,
                              () => setState(() => _aba = _AbaGestor.novo)),
                          const SizedBox(width: 8),
                          _tabBtn('Aguardando aprovação (${_pendentes.length})',
                              _aba == _AbaGestor.pendentes,
                              () => setState(() => _aba = _AbaGestor.pendentes)),
                          const SizedBox(width: 8),
                          _tabBtn('Histórico', _aba == _AbaGestor.historico,
                              () => setState(() => _aba = _AbaGestor.historico)),
                        ]),
                      ),
                    ),
                  ),
                  if (_aba == _AbaGestor.novo)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      sliver: SliverToBoxAdapter(child: _gridNovoPedido()),
                    )
                  else if (lista.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _aba == _AbaGestor.historico
                                ? 'Nenhuma decisão registrada ainda.'
                                : 'Nenhuma solicitação aguardando aprovação.',
                            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      sliver: SliverList.separated(
                        itemCount: lista.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _card(lista[i]),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _gridNovoPedido() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 110,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _labelTipoSolicitacaoGestor.length,
      itemBuilder: (_, i) {
        final tipo = _labelTipoSolicitacaoGestor.keys.elementAt(i);
        final label = _labelTipoSolicitacaoGestor[tipo]!;
        final icone = _iconeTipoSolicitacaoGestor[tipo]!;
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
                    color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icone, color: AppColors.laranja, size: 24),
                Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dark)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tabBtn(String label, bool ativo, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: ativo ? AppColors.laranja : const Color(0xFFF1F5F9),
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

  Widget _card(Map<String, dynamic> s) {
    final status = s['status'] as String? ?? 'pendente_gestor';
    final tipo = s['tipo'] as String;
    final payload = (s['payload'] as Map?)?.cast<String, dynamic>() ?? {};

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _labelTipoSolicitacaoAprovacao[tipo] ??
                            _labelTipoSolicitacaoGestor[tipo] ??
                            tipo,
                        style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark)),
                    const SizedBox(height: 2),
                    Text('Aberto por ${s['aberto_por_nome']}',
                        style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
                  ],
                ),
              ),
              _statusChip(status),
            ],
          ),
          if (payload.isNotEmpty) ...[
            const SizedBox(height: 10),
            PayloadSolicitacaoView(payload: payload),
          ],
          if (status == 'recusado_gestor' && s['motivo_recusa_gestor'] != null) ...[
            const SizedBox(height: 8),
            Text('Motivo: ${s['motivo_recusa_gestor']}',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.cinzaTexto, fontStyle: FontStyle.italic)),
          ],
          if (status == 'pendente_gestor') ...[
            const SizedBox(height: 12),
            Row(children: [
              TextButton(
                onPressed: () => _recusar(s),
                child: Text('Recusar',
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.erro)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _aprovar(s),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.sucesso, foregroundColor: Colors.white),
                child: const Text('Aprovar'),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final Color cor;
    final String label;
    switch (status) {
      case 'recusado_gestor':
        cor = const Color(0xFFDC2626);
        label = 'Recusada';
        break;
      case 'em_andamento':
        cor = const Color(0xFF2563EB);
        label = 'Em andamento (RH)';
        break;
      case 'concluido':
        cor = const Color(0xFF16A34A);
        label = 'Concluído';
        break;
      case 'cancelado':
        cor = const Color(0xFFDC2626);
        label = 'Cancelado';
        break;
      case 'pendente':
        cor = const Color(0xFFD97706);
        label = 'Aprovado · aguardando RH';
        break;
      default:
        cor = const Color(0xFFD97706);
        label = 'Aguardando você';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: cor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: cor)),
    );
  }
}

/// Formulário genérico de nova solicitação do gestor — os campos exibidos
/// variam por [tipo] (ver `_camposPorTipoGestor`). Nenhum desses 4 tipos
/// exige aprovação (vão direto para a fila do RH/DP).
class _DialogSolicitacaoGestor extends StatefulWidget {
  final String tipo;
  final List<ColaboradorModel> equipe;
  final ApiService api;
  const _DialogSolicitacaoGestor(
      {required this.tipo, required this.equipe, required this.api});

  @override
  State<_DialogSolicitacaoGestor> createState() => _DialogSolicitacaoGestorState();
}

class _DialogSolicitacaoGestorState extends State<_DialogSolicitacaoGestor> {
  final _ctrls = <String, TextEditingController>{};
  ColaboradorModel? _colabAlvo;
  final Set<ColaboradorModel> _selecionados = {};
  bool _enviando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final campos = _camposPorTipoGestor[widget.tipo] ?? <(String, bool)>[];
    for (final (label, _) in campos) {
      _ctrls[label] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _enviar() async {
    final gestor = widget.api.colaboradorAtual;
    if (gestor == null) return;
    if (_tiposComColabUnico.contains(widget.tipo) && _colabAlvo == null) {
      setState(() => _erro = 'Selecione o colaborador.');
      return;
    }
    if (_tiposComColabMultiplo.contains(widget.tipo) && _selecionados.isEmpty) {
      setState(() => _erro = 'Selecione ao menos um colaborador.');
      return;
    }
    final camposVazios = _ctrls.values.any((c) => c.text.trim().isEmpty);
    if (camposVazios) {
      setState(() => _erro = 'Preencha todos os campos.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final payload = <String, dynamic>{
        if (_colabAlvo != null) ...{
          'Colaborador': _colabAlvo!.nome,
          'Matrícula': _colabAlvo!.matricula,
          'Cargo': _colabAlvo!.cargo,
        },
        if (_selecionados.isNotEmpty)
          'Colaboradores':
              _selecionados.map((c) => '${c.nome} (${c.matricula})').join(', '),
        for (final entry in _ctrls.entries) entry.key: entry.value.text.trim(),
      };

      await widget.api.criarSolicitacao(
        tipo: widget.tipo,
        payload: payload,
        abertoPorId: gestor.id,
        abertoPorNome: gestor.nome,
        abertoPorPapel: 'gestor',
        setor: gestor.setor,
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
    final campos = _camposPorTipoGestor[widget.tipo] ?? <(String, bool)>[];
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
                Text(_labelTipoSolicitacaoGestor[widget.tipo] ?? widget.tipo,
                    style: GoogleFonts.poppins(
                        fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dark)),
                const SizedBox(height: 16),
                if (_tiposComColabUnico.contains(widget.tipo)) ...[
                  Text('Colaborador',
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.cinzaTexto)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<ColaboradorModel>(
                    initialValue: _colabAlvo,
                    isExpanded: true,
                    items: widget.equipe
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.nome)))
                        .toList(),
                    onChanged: (v) => setState(() => _colabAlvo = v),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_tiposComColabMultiplo.contains(widget.tipo)) ...[
                  Text('Colaboradores',
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.cinzaTexto)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.equipe.map((c) {
                      final sel = _selecionados.contains(c);
                      return FilterChip(
                        label: Text(c.nome),
                        selected: sel,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _selecionados.add(c);
                          } else {
                            _selecionados.remove(c);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                ...campos.map((campo) {
                  final (label, multilinha) = campo;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: GoogleFonts.poppins(
                                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.cinzaTexto)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _ctrls[label],
                          maxLines: multilinha ? 3 : 1,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (_erro != null) ...[
                  const SizedBox(height: 4),
                  Text(_erro!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.erro)),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _enviando ? null : _enviar,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.laranja, foregroundColor: Colors.white),
                    child: _enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
