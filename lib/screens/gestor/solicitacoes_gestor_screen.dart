import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';
import '../solicitacoes/solicitacoes_screen.dart'
    show PayloadSolicitacaoView, codigoSolicitacao, tituloComCodigo;
import 'solicitacoes_gestor_formularios.dart';

// Só pra exibir o histórico corretamente — não controla o que pode ser
// criado (isso é _labelTipoSolicitacaoGestor, o grid de "novo pedido").
const Map<String, String> _labelTipoSolicitacaoAprovacao = {
  'incentivo_educacional': 'Incentivo Educacional',
  'rota': 'Rota',
  'moveis_administrativos': 'Móveis Administrativos',
  'uber': 'Uber',
  'uber_fixo': 'Uber Fixo',
};

// Uber, Uber Fixo, Móveis Administrativos e Rota diária do gestor ficam na
// tela Facilites (facilites_gestor_screen.dart), como no web.
const Map<String, String> _labelTipoSolicitacaoGestor = {
  'adesao_beneficio': 'Adesão de Benefício',
  'swile': 'Swile',
  'adiantamento_13': 'Adiantamento de 13º',
};

const Map<String, IconData> _iconeTipoSolicitacaoGestor = {
  'adesao_beneficio': Icons.card_giftcard_outlined,
  'swile': Icons.card_giftcard_outlined,
  'adiantamento_13': Icons.payments_outlined,
};

/// "Solicitações" do gestor — contrapartida de [SolicitacoesScreen]
/// (colaborador). Porta `solicitacoes_gestor_screen.dart` do gentepole_admin:
/// abre pedidos que não passam por aprovação (Móveis, Swile, Uber,
/// Adiantamento de 13º) e aprova/recusa os que exigem aprovação do gestor
/// (Rota), abertos pelos membros da equipe. Incentivo Educacional vai direto
/// para o DP, sem aprovação do gestor.
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
    final equipe = await _api.buscarMinhaEquipe(
        apenasLiderDireto: true, funcionalidade: 'solicitacoes_gestor');
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
      builder: (_) => switch (tipo) {
        'adesao_beneficio' =>
          DialogAdesaoBeneficio(gestor: gestor, equipe: _equipe, api: _api),
        'swile' => DialogSwile(gestor: gestor, equipe: _equipe, api: _api),
        _ => DialogAdiantamento13(gestor: gestor, equipe: _equipe, api: _api),
      },
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
        title: Text('Recusar solicitação ${codigoSolicitacao(s)}'.trim(),
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
    final pendentes = _pendentes;
    final historico = _historico;
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
                  // Tudo numa tela só: novo pedido, o que espera a aprovação
                  // do gestor e o acompanhamento das já abertas/decididas.
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _tituloSecao('Abrir um novo pedido'),
                        _gridNovoPedido(),
                        if (pendentes.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _tituloSecao(
                              'Aguardando sua aprovação (${pendentes.length})'),
                          for (final s in pendentes) ...[
                            _card(s),
                            const SizedBox(height: 12),
                          ],
                        ],
                        const SizedBox(height: 24),
                        _tituloSecao('Acompanhamento'),
                        if (historico.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('Nenhuma solicitação por aqui ainda.',
                                  style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: AppColors.cinzaTexto)),
                            ),
                          )
                        else
                          for (final s in historico) ...[
                            _card(s),
                            const SizedBox(height: 12),
                          ],
                      ]),
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
                        tituloComCodigo(
                            s,
                            _labelTipoSolicitacaoAprovacao[tipo] ??
                                _labelTipoSolicitacaoGestor[tipo] ??
                                tipo),
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
