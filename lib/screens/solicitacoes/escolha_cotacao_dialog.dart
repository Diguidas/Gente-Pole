import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

String moedaBr(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

/// Texto curto com os valores e a escolha de uma rota cotada pelo Facilites.
/// Porta de `escolha_cotacao_dialog.dart` do gentepole_admin.
String? resumoCotacao(Map<String, dynamic> s) {
  final c = (s['cotacao'] as Map?)?.cast<String, dynamic>();
  if (c == null) return null;
  final frete = (c['frete'] as num?)?.toDouble();
  final flash = (c['uber_flash'] as num?)?.toDouble();
  if (frete == null || flash == null) return null;
  final escolha = s['escolha_cotacao'] as String?;
  final base = 'Frete ${moedaBr(frete)} · Uber Flash ${moedaBr(flash)}';
  if (escolha == null) return base;
  final nome = escolha == 'frete' ? 'Frete' : 'Uber Flash';
  final just = (s['escolha_justificativa'] as String?)?.trim();
  return '$base\nEscolhido: $nome${just != null && just.isNotEmpty ? ' — "$just"' : ''}';
}

/// O solicitante escolhe entre Frete e Uber Flash. Se escolher o de maior
/// valor, a justificativa é obrigatória. Retorna a escolha ('frete' ou
/// 'uber_flash') se salvou, ou null se o usuário fechou sem escolher.
Future<String?> mostrarEscolhaCotacao(
    BuildContext context, Map<String, dynamic> solicitacao) async {
  final c = (solicitacao['cotacao'] as Map).cast<String, dynamic>();
  final frete = (c['frete'] as num).toDouble();
  final flash = (c['uber_flash'] as num).toDouble();
  final justCtrl = TextEditingController();
  String? escolha;
  String? erro;
  var salvando = false;

  final ok = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      bool maisCaro(String e) => e == 'frete' ? frete > flash : flash > frete;
      Widget opcao(String chave, String nome, double valor) =>
          RadioListTile<String>(
            value: chave,
            groupValue: escolha,
            onChanged: salvando ? null : (v) => setD(() => escolha = v),
            title: Text('$nome — ${moedaBr(valor)}',
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          );
      return AlertDialog(
        title: Text('Escolha como a rota será feita',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('O Facilites informou os valores. Escolha uma opção:',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.cinzaTexto)),
                  opcao('frete', 'Frete', frete),
                  opcao('uber_flash', 'Uber Flash', flash),
                  if (escolha != null && maisCaro(escolha!)) ...[
                    const SizedBox(height: 8),
                    Text(
                        'Você escolheu a opção de maior valor — informe a justificativa:',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: const Color(0xFF9A5B13))),
                    const SizedBox(height: 6),
                    TextField(
                        controller: justCtrl,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(border: OutlineInputBorder())),
                  ],
                  if (erro != null) ...[
                    const SizedBox(height: 8),
                    Text(erro!,
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.erro)),
                  ],
                ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: salvando ? null : () => Navigator.pop(ctx),
              child: const Text('Depois')),
          ElevatedButton(
            onPressed: salvando
                ? null
                : () async {
                    if (escolha == null) {
                      setD(() => erro = 'Selecione uma opção.');
                      return;
                    }
                    final precisa = maisCaro(escolha!);
                    if (precisa && justCtrl.text.trim().isEmpty) {
                      setD(() => erro =
                          'A justificativa é obrigatória ao escolher o maior valor.');
                      return;
                    }
                    setD(() {
                      salvando = true;
                      erro = null;
                    });
                    try {
                      await ApiService().escolherCotacaoRota(
                        id: solicitacao['id'] as int,
                        escolha: escolha!,
                        justificativa: precisa ? justCtrl.text : null,
                      );
                      if (ctx.mounted) Navigator.pop(ctx, escolha);
                    } catch (e) {
                      setD(() {
                        salvando = false;
                        erro = 'Erro: $e';
                      });
                    }
                  },
            child: const Text('Confirmar'),
          ),
        ],
      );
    }),
  );
  justCtrl.dispose();
  return ok;
}
