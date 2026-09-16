import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Seletor de nota numa escala de 1 a 5 — usado em todas as telas de
/// avaliação de desempenho/potencial (9-box) e de período de experiência,
/// tanto do colaborador quanto do gestor, pra manter a mesma escala usada
/// no web (`SeletorNota1a5` em
/// `gentepole_admin/lib/features/performance/presentation/widgets/seletor_nota_widget.dart`).
/// Substitui o antigo seletor de 3 botões (Baixo/Médio/Alto).
class SeletorNota1a5 extends StatelessWidget {
  final int valor;
  final ValueChanged<int> onChanged;
  final Color corSelecionada;
  final double alturaBotao;
  final String? legendaBaixa;
  final String? legendaAlta;

  const SeletorNota1a5({
    super.key,
    required this.valor,
    required this.onChanged,
    this.corSelecionada = AppColors.laranja,
    this.alturaBotao = 40,
    this.legendaBaixa,
    this.legendaAlta,
  });

  static const descricaoBaixa = 'Não atende as expectativas';
  static const descricaoAlta = 'Supera muito as expectativas';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: List.generate(5, (i) {
            final n = i + 1;
            final sel = valor == n;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(n),
                child: Container(
                  margin: EdgeInsets.only(right: i < 4 ? 6 : 0),
                  height: alturaBotao,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel ? corSelecionada : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: sel ? corSelecionada : const Color(0xFFE2E8F0)),
                  ),
                  child: Text('$n',
                      style: AppTextStyles.corpoMinimo.copyWith(
                          fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : AppColors.dark)),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(legendaBaixa ?? descricaoBaixa,
                  style: AppTextStyles.corpoMinimo),
            ),
            Expanded(
              child: Text(legendaAlta ?? descricaoAlta,
                  textAlign: TextAlign.right, style: AppTextStyles.corpoMinimo),
            ),
          ],
        ),
      ],
    );
  }
}

/// Exibição textual de uma nota de 1 a 5 (ex: "4/5") — usada onde antes se
/// mostrava o rótulo Baixo/Médio/Alto.
String labelNota1a5(int? n) => (n != null && n >= 1 && n <= 5) ? '$n/5' : '—';
