import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../widgets/app_bar_gradiente.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';
import '../reserva_salas/layout_sala_screens.dart';
import '../solicitacoes/escolha_cotacao_dialog.dart';
import '../solicitacoes/solicitacoes_screen.dart'
    show DialogRota, PayloadSolicitacaoView;
import 'solicitacoes_gestor_formularios.dart';

const _tiposFacilites = {
  'uber': 'Uber',
  'uber_fixo': 'Uber Fixo',
  'moveis_administrativos': 'Móveis Administrativos',
  'rota': 'Rota diária',
};

/// Módulo Gestor → Facilites: pedidos de Uber (comum e fixo), Móveis
/// Administrativos e Rota diária, e acompanhamento do que já foi aberto.
/// Porta de `facilites_gestor_screen.dart` do gentepole_admin.
class FacilitesGestorScreen extends StatefulWidget {
  const FacilitesGestorScreen({super.key});

  @override
  State<FacilitesGestorScreen> createState() => _FacilitesGestorScreenState();
}

class _FacilitesGestorScreenState extends State<FacilitesGestorScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _erro;
  ColaboradorModel? _gestor;
  List<ColaboradorModel> _equipe = [];
  List<Map<String, dynamic>> _minhas = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final gestor = _api.colaboradorAtual;
      if (gestor == null) {
        if (!mounted) return;
        setState(() {
          _erro = 'Perfil não encontrado.';
          _loading = false;
        });
        return;
      }
      final equipe = await _api.buscarMinhaEquipe(
          apenasLiderDireto: true, funcionalidade: 'facilites_gestor');
      final todas = await _api.listarSolicitacoes(abertoPorId: gestor.id);
      if (!mounted) return;
      setState(() {
        _gestor = gestor;
        _equipe = equipe;
        _minhas =
            todas.where((s) => _tiposFacilites.containsKey(s['tipo'])).toList();
        _erro = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar: $e';
        _loading = false;
      });
    }
  }

  Future<void> _novo(String tipo) async {
    final gestor = _gestor;
    if (gestor == null) return;
    final enviado = await showDialog<bool>(
      context: context,
      builder: (_) => switch (tipo) {
        'uber' => DialogUber(gestor: gestor, equipe: _equipe, api: _api),
        'moveis_administrativos' =>
          DialogMoveisAdministrativos(gestor: gestor, equipe: _equipe, api: _api),
        _ => DialogRota(colab: gestor, api: _api, comoGestor: true),
      },
    );
    if (enviado == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Solicitação enviada ao Facilites.')));
      }
      _carregar();
    }
  }

  /// Escolheu Uber Flash na rota: abre a solicitação de Uber já preenchida
  /// com os dados da rota.
  Future<void> _abrirUberDaRota(Map<String, dynamic> rota) async {
    final gestor = _gestor;
    if (gestor == null || !mounted) return;
    final enviado = await showDialog<bool>(
      context: context,
      builder: (_) => DialogUber(
          gestor: gestor, equipe: _equipe, api: _api, rotaOrigem: rota),
    );
    if (enviado == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Solicitação de Uber enviada ao Facilites.')));
    }
  }

  Future<void> _cancelarFixo(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Uber fixo?'),
        content: const Text(
            'O Facilites será avisado para desativar o Uber deste colaborador.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Solicitar cancelamento')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.solicitarCancelamentoUberFixo(s['id'] as int);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
    _carregar();
  }

  String _data(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  (Color, String) _status(Map<String, dynamic> s) {
    final st = s['status'] as String? ?? 'pendente';
    if (s['desativado_em'] != null) return (AppColors.cinzaTexto, 'Desativado');
    return switch (st) {
      'aguardando_escolha' => (const Color(0xFF7C3AED), 'Escolha o frete'),
      'em_andamento' => (const Color(0xFF2563EB), 'Em andamento'),
      'concluido' => (const Color(0xFF16A34A), 'Concluído'),
      'cancelado' => (const Color(0xFFDC2626), 'Cancelado'),
      _ => (const Color(0xFFD97706), 'Aguardando Facilites'),
    };
  }

  Widget _botaoNovo(String tipo, IconData icone) => InkWell(
        onTap: () => _novo(tipo),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icone, color: AppColors.laranja, size: 26),
            const SizedBox(height: 14),
            Text(tipo == 'uber' ? 'Uber (comum ou fixo)' : _tiposFacilites[tipo]!,
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark)),
          ]),
        ),
      );

  Widget _card(Map<String, dynamic> s) {
    final tipo = s['tipo'] as String;
    final (cor, label) = _status(s);
    final payload = (s['payload'] as Map?)?.cast<String, dynamic>() ?? {};
    final ativoFixo = tipo == 'uber_fixo' &&
        s['status'] == 'concluido' &&
        s['desativado_em'] == null;
    final cotacao = resumoCotacao(s);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
                '${_tiposFacilites[tipo]} · ${_data(s['criado_em'] as String?)}',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: cor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20)),
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w700, color: cor)),
          ),
        ]),
        const SizedBox(height: 8),
        PayloadSolicitacaoView(payload: payload),
        if (cotacao != null) ...[
          const SizedBox(height: 8),
          Text(cotacao,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: const Color(0xFF92400E))),
        ],
        if (tipo == 'uber' && s['prazo_fim'] != null) ...[
          const SizedBox(height: 6),
          Text('Prazo do Uber: até ${_data(s['prazo_fim'] as String?)}',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.cinzaTexto)),
        ],
        if (tipo == 'rota' && s['status'] == 'aguardando_escolha')
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () async {
                final escolha = await mostrarEscolhaCotacao(context, s);
                if (escolha == null) return;
                if (escolha == 'uber_flash') await _abrirUberDaRota(s);
                _carregar();
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.laranja,
                  foregroundColor: Colors.white),
              child: const Text('Escolher Frete ou Uber Flash'),
            ),
          ),
        if (ativoFixo)
          Align(
            alignment: Alignment.centerRight,
            child: s['cancelamento_solicitado_em'] != null
                ? Text('Cancelamento solicitado — aguardando o Facilites desativar',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: const Color(0xFFB45309)))
                : TextButton(
                    onPressed: () => _cancelarFixo(s),
                    child: Text('Solicitar cancelamento',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.erro)),
                  ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: const AppBarGradiente(titulo: 'Facilites'),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.laranja))
                  : _erro != null
                      ? Center(child: Text(_erro!))
                      : RefreshIndicator(
                          onRefresh: _carregar,
                          child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              Text(
                                  'Solicite Uber, Móveis Administrativos, Rota diária e alteração de layout de sala.',
                                  style: GoogleFonts.poppins(
                                      fontSize: 12.5,
                                      color: AppColors.cinzaTexto)),
                              const SizedBox(height: 16),
                              Wrap(spacing: 14, runSpacing: 14, children: [
                                _botaoNovo('uber', Icons.local_taxi_outlined),
                                _botaoNovo('moveis_administrativos',
                                    Icons.chair_outlined),
                                _botaoNovo('rota', Icons.two_wheeler_outlined),
                                // Alteração de layout de sala: exclusivo do gestor.
                                InkWell(
                                  onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const LayoutSalaListaScreen())),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    width: 160,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                              Icons.dashboard_customize_outlined,
                                              color: AppColors.laranja,
                                              size: 26),
                                          const SizedBox(height: 14),
                                          Text('Layout de sala',
                                              style: GoogleFonts.poppins(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.dark)),
                                        ]),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 24),
                              Text('Minhas solicitações',
                                  style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.dark)),
                              const SizedBox(height: 10),
                              if (_minhas.isEmpty)
                                Text('Nenhuma solicitação ainda.',
                                    style: GoogleFonts.poppins(
                                        fontSize: 12.5,
                                        color: AppColors.cinzaTexto))
                              else
                                for (final s in _minhas) _card(s),
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
