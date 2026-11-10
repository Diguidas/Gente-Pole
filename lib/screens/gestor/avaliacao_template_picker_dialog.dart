import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../core/app_theme.dart';

/// Aberto na hora de avaliar um colaborador — o gestor pode escolher um
/// template pronto (retornado via `Navigator.pop`) ou fechar sem escolher
/// pra manter o grupo fixo de perguntas por função/setor.
class AvaliacaoTemplatePickerDialog extends StatefulWidget {
  final String tipo;

  /// Setor do colaborador sendo avaliado — quando informado, a lista só
  /// mostra templates daquele setor ou genéricos (setor null).
  final String? setorColaborador;

  /// Função (cargo) do colaborador sendo avaliado — quando informada, a
  /// lista só mostra templates daquela função ou genéricos (funcao null).
  final String? funcaoColaborador;

  const AvaliacaoTemplatePickerDialog(
      {super.key,
      this.tipo = 'desempenho',
      this.setorColaborador,
      this.funcaoColaborador});

  @override
  State<AvaliacaoTemplatePickerDialog> createState() =>
      _AvaliacaoTemplatePickerDialogState();
}

class _AvaliacaoTemplatePickerDialogState
    extends State<AvaliacaoTemplatePickerDialog> {
  List<Map<String, dynamic>> _templates = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final lista = await ApiService().listarAvaliacaoTemplates(
          apenasAtivos: true,
          tipo: widget.tipo,
          setorColaborador: widget.setorColaborador,
          funcaoColaborador: widget.funcaoColaborador);
      if (!mounted) return;
      setState(() {
        _templates = lista;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar templates.';
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: AppColors.branco,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                gradient: AppColors.gradientePrincipal,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.library_books_outlined, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text('Selecionar template',
                      style: GoogleFonts.poppins(
                          fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (widget.tipo == 'desempenho')
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop('__padrao__'),
                    icon: const Icon(Icons.undo_rounded, size: 16),
                    label: Text('Usar perguntas padrão da função',
                        style: GoogleFonts.poppins(fontSize: 12.5)),
                  ),
                ),
              ),
            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator())
                  : _erro != null
                      ? Center(
                          child:
                              Text(_erro!, style: GoogleFonts.poppins(color: AppColors.erro)))
                      : _templates.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.inbox_outlined,
                                      size: 48, color: AppColors.cinzaTexto),
                                  const SizedBox(height: 12),
                                  Text('Nenhum template disponível.',
                                      style: GoogleFonts.poppins(
                                          color: AppColors.cinzaTexto, fontSize: 14)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Peça ao RH para criar templates em Performance → Perguntas por função.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                        color: AppColors.cinzaTexto, fontSize: 12),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(20),
                              itemCount: _templates.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => _TemplateCard(
                                template: _templates[i],
                                onSelecionar: () =>
                                    Navigator.of(context).pop(_templates[i]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final Map<String, dynamic> template;
  final VoidCallback onSelecionar;

  const _TemplateCard({required this.template, required this.onSelecionar});

  @override
  Widget build(BuildContext context) {
    final nome = template['nome'] as String? ?? '';
    final descricao = template['descricao'] as String?;

    return InkWell(
      onTap: onSelecionar,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nome,
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.dark)),
                  if (descricao != null && descricao.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.cinzaTexto)),
                  ],
                ],
              ),
            ),
            ElevatedButton(
              onPressed: onSelecionar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.laranja,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Usar'),
            ),
          ],
        ),
      ),
    );
  }
}
