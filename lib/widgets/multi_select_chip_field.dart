import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';

/// Campo que abre um seletor com busca + múltipla escolha (checkboxes) ao
/// ser tocado, mostrando as opções escolhidas como chips. Usado onde antes
/// era um dropdown de escolha única mas o usuário precisa marcar vários de
/// uma vez (ex: vários setores, várias funções).
class MultiSelectChipField extends StatelessWidget {
  final List<String> opcoes;
  final Set<String> selecionados;
  final ValueChanged<Set<String>> onChanged;
  final String hint;
  final Color cor;
  final bool carregando;
  final bool habilitado;

  const MultiSelectChipField({
    super.key,
    required this.opcoes,
    required this.selecionados,
    required this.onChanged,
    this.hint = 'Selecionar...',
    this.cor = AppColors.laranja,
    this.carregando = false,
    this.habilitado = true,
  });

  Future<void> _abrirSeletor(BuildContext context) async {
    final resultado = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _MultiSelectDialog(opcoes: opcoes, selecionadosIniciais: selecionados, cor: cor),
    );
    if (resultado != null) onChanged(resultado);
  }

  @override
  Widget build(BuildContext context) {
    if (carregando) {
      return const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2));
    }
    return InkWell(
      onTap: habilitado ? () => _abrirSeletor(context) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: habilitado ? const Color(0xFFF8FAFC) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(children: [
          Expanded(
            child: selecionados.isEmpty
                ? Text(hint, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: selecionados
                        .map((s) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: cor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                              child: Text(s, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: cor)),
                            ))
                        .toList(),
                  ),
          ),
          Icon(Icons.arrow_drop_down, color: habilitado ? AppColors.cinzaTexto : Colors.grey.shade400),
        ]),
      ),
    );
  }
}

class _MultiSelectDialog extends StatefulWidget {
  final List<String> opcoes;
  final Set<String> selecionadosIniciais;
  final Color cor;
  const _MultiSelectDialog({required this.opcoes, required this.selecionadosIniciais, required this.cor});

  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
  late Set<String> _selecionados;
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _selecionados = {...widget.selecionadosIniciais};
  }

  List<String> get _filtradas {
    if (_busca.trim().isEmpty) return widget.opcoes;
    final q = _busca.toLowerCase();
    return widget.opcoes.where((o) => o.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text('Selecionar', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.dark)),
                ),
                Text('${_selecionados.length} selecionado${_selecionados.length == 1 ? '' : 's'}',
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
              ]),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _busca = v),
                style: GoogleFonts.poppins(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: widget.opcoes.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text('Nenhuma opção disponível.', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto)),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: _filtradas
                            .map((o) => CheckboxListTile(
                                  dense: true,
                                  value: _selecionados.contains(o),
                                  activeColor: widget.cor,
                                  title: Text(o, style: GoogleFonts.poppins(fontSize: 13)),
                                  onChanged: (v) => setState(() => v == true ? _selecionados.add(o) : _selecionados.remove(o)),
                                ))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selecionados),
                  style: ElevatedButton.styleFrom(backgroundColor: widget.cor, foregroundColor: Colors.white),
                  child: const Text('Confirmar'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
