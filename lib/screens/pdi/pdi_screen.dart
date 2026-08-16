import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

const _modalidadesAcao = {
  'blearning': 'B-learning',
  'benchmarking': 'Benchmarking',
  'elearning': 'E-learning',
};

/// "Meu PDI" — Plano de Desenvolvimento Individual do colaborador logado.
/// Porta a tela `pdi_colab_screen.dart` do app admin.
class PdiScreen extends StatefulWidget {
  const PdiScreen({super.key});

  @override
  State<PdiScreen> createState() => _PdiScreenState();
}

class _PdiScreenState extends State<PdiScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _erro;
  List<Map<String, dynamic>> _planos = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final col = _api.colaboradorAtual;
      if (col == null) {
        setState(() {
          _erro = 'Perfil não encontrado.';
          _loading = false;
        });
        return;
      }
      final planos = await _api.listarPdiPlanos(col.id);
      if (!mounted) return;
      setState(() {
        _planos = planos;
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

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _anexarArquivo(int acaoId) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    try {
      await _api.uploadAnexoAcaoPdi(
        acaoId: acaoId,
        bytes: file.bytes as Uint8List,
        nomeArquivo: file.name,
      );
      _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao anexar arquivo: $e'),
        backgroundColor: AppColors.erro,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _alternarStatusAcao(Map<String, dynamic> acao) async {
    final novoStatus = acao['status'] == 'concluido' ? 'pendente' : 'concluido';
    try {
      await _api.atualizarStatusAcaoPdi(acao['id'] as int, novoStatus);
      _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao atualizar: $e'),
        backgroundColor: AppColors.erro,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 200,
            decoration: const BoxDecoration(gradient: AppColors.gradientePrincipal),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                          Text('🎯 Meu PDI',
                              style: AppTextStyles.tituloGrande
                                  .copyWith(color: Colors.white)),
                          Text('Seu plano de desenvolvimento individual',
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
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.laranja));
    }
    if (_erro != null) {
      return Center(child: Text(_erro!, style: AppTextStyles.corpoCinza));
    }
    if (_planos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Você ainda não tem um plano de desenvolvimento.\nQuando seu gestor criar um, ele aparece aqui.',
            textAlign: TextAlign.center,
            style: AppTextStyles.corpoCinza,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _carregar,
      color: AppColors.laranja,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: _planos.map(_buildPlanoCard).toList(),
      ),
    );
  }

  Widget _buildPlanoCard(Map<String, dynamic> plano) {
    final acoes =
        (plano['pdi_acoes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final termos = (plano['pdi_termos_compromisso'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final total = acoes.length;
    final concluidas = acoes.where((a) => a['status'] == 'concluido').length;
    final status = plano['status'] as String? ?? 'em_andamento';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.laranja.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plano['objetivo'] as String? ?? '',
                    style: AppTextStyles.labelSecao),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (status == 'concluido' ? AppColors.sucesso : AppColors.laranja)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status == 'concluido'
                      ? 'Concluído'
                      : status == 'cancelado'
                          ? 'Cancelado'
                          : 'Em andamento',
                  style: AppTextStyles.corpoMinimo.copyWith(
                    fontWeight: FontWeight.w600,
                    color: status == 'concluido' ? AppColors.sucesso : AppColors.laranja,
                  ),
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: concluidas / total,
                minHeight: 8,
                backgroundColor: AppColors.cinzaClaro,
                valueColor: const AlwaysStoppedAnimation(AppColors.laranja),
              ),
            ),
            const SizedBox(height: 4),
            Text('$concluidas de $total ações concluídas', style: AppTextStyles.corpoMinimo),
          ],
          const SizedBox(height: 12),
          ...acoes.map(_buildAcaoItem),
          if (termos.isNotEmpty) ...[
            const Divider(height: 24),
            Text('Termo de compromisso',
                style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...termos.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    onTap: () => _abrirUrl(t['arquivo_url'] as String),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.download_rounded, size: 15, color: AppColors.laranja),
                        const SizedBox(width: 6),
                        Text(t['nome_arquivo'] as String? ?? 'termo.pdf',
                            style: AppTextStyles.corpoMedio.copyWith(
                                color: AppColors.laranja, decoration: TextDecoration.underline)),
                      ],
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildAcaoItem(Map<String, dynamic> acao) {
    final link = acao['link'] as String?;
    final modalidade = acao['modalidade'] as String?;
    final anexoNome = acao['anexo_nome'] as String?;
    final anexoUrl = acao['anexo_url'] as String?;
    final concluida = acao['status'] == 'concluido';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _alternarStatusAcao(acao),
                child: Icon(
                  concluida ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  size: 20,
                  color: concluida ? AppColors.sucesso : AppColors.cinzaTexto,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(acao['descricao'] as String? ?? '',
                    style: AppTextStyles.corpoMedio),
              ),
              if (acao['prazo'] != null)
                Text(acao['prazo'] as String, style: AppTextStyles.corpoMinimo),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (modalidade != null)
                  Text(_modalidadesAcao[modalidade] ?? modalidade,
                      style: AppTextStyles.corpoMinimo),
                if (link != null)
                  InkWell(
                    onTap: () => _abrirUrl(link),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link_rounded, size: 13, color: AppColors.laranja),
                        const SizedBox(width: 3),
                        Text('Abrir link',
                            style: AppTextStyles.corpoMinimo.copyWith(
                                color: AppColors.laranja, decoration: TextDecoration.underline)),
                      ],
                    ),
                  ),
                if (anexoNome != null)
                  InkWell(
                    onTap: () => _abrirUrl(anexoUrl!),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.attach_file_rounded, size: 13, color: AppColors.cinzaTexto),
                        const SizedBox(width: 3),
                        Text(anexoNome, style: AppTextStyles.corpoMinimo),
                      ],
                    ),
                  ),
                InkWell(
                  onTap: () => _anexarArquivo(acao['id'] as int),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.upload_file_rounded, size: 13, color: AppColors.laranja),
                      const SizedBox(width: 3),
                      Text(
                        anexoNome == null ? 'Anexar arquivo' : 'Trocar arquivo',
                        style: AppTextStyles.corpoMinimo.copyWith(
                            color: AppColors.laranja, decoration: TextDecoration.underline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
