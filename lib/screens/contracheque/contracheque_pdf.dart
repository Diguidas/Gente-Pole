import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/colaborador_model.dart';

/// 1234.5 -> "1.234,50"
String formatarValorFolha(num v) {
  final negativo = v < 0;
  final partes = v.abs().toStringAsFixed(2).split('.');
  final inteiro = partes[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  return '${negativo ? '-' : ''}$inteiro,${partes[1]}';
}

String _dataBr(String? iso) {
  if (iso == null || iso.length < 10) return '';
  final p = iso.substring(0, 10).split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

const _meses = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

/// PDF do contracheque no formato do demonstrativo de pagamento, só com os
/// dados que temos (o que a folha não traz — endereço, banco, PIS... — fica de
/// fora). Abre a folha de compartilhar do celular (salvar, enviar, imprimir).
Future<void> compartilharContrachequePdf({
  required Map<String, dynamic> folha,
  required String nomePeriodo,
  required int mes,
  required int ano,
  required String matricula,
  ColaboradorModel? colab,
}) async {
  const cinza = PdfColor.fromInt(0xFF666666);
  const borda = PdfColor.fromInt(0xFF222222);
  const fundoCab = PdfColor.fromInt(0xFFD9D9D9);

  final doc = pw.Document();

  pw.MemoryImage? logo;
  try {
    final bytes = await rootBundle.load('assets/logo1.png');
    logo = pw.MemoryImage(bytes.buffer.asUint8List());
  } catch (_) {}

  final eventos = (folha['eventos'] as List).cast<Map<String, dynamic>>();
  final resumo = folha['resumo'] as Map<String, dynamic>?;
  final filial = folha['filial'] as Map<String, dynamic>?;
  final totalProventos = (folha['totalProventos'] as num).toDouble();
  final totalDescontos = (folha['totalDescontos'] as num).toDouble();
  final liquido = (folha['liquido'] as num).toDouble();
  final pensao = (folha['pensao'] as num?)?.toDouble() ?? 0;

  final razao = (filial?['razao_social_filial'] ?? filial?['razao_social_empresa'])
      ?.toString();
  final cnpj = (filial?['cnpj_filial'] ?? filial?['cnpj_empresa'])?.toString();

  pw.Widget campo(String rotulo, String valor, {bool direita = false}) => pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 4),
        child: pw.Column(
          crossAxisAlignment:
              direita ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
          children: [
            pw.Text(rotulo,
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(valor, style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      );

  pw.Widget caixa(List<pw.Widget> filhos) => pw.Container(
        decoration: const pw.BoxDecoration(
            border: pw.Border(
                left: pw.BorderSide(color: borda),
                right: pw.BorderSide(color: borda),
                bottom: pw.BorderSide(color: borda))),
        child: pw.Row(children: filhos),
      );

  pw.Widget celulaTotal(String rotulo, String valor, {bool destaque = false}) =>
      pw.Expanded(
        child: pw.Container(
          color: destaque ? fundoCab : null,
          padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(rotulo,
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(valor, style: const pw.TextStyle(fontSize: 10))),
            ],
          ),
        ),
      );

  pw.Widget celula(String texto, {bool direita = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(texto,
            textAlign: direita ? pw.TextAlign.right : pw.TextAlign.left,
            style: const pw.TextStyle(fontSize: 9)),
      );

  final cargo = colab?.cargo ?? '';
  final temLinhaAdmissao = cargo.isNotEmpty || (colab?.dataAdmissao != null);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => [
        pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: borda)),
          padding: const pw.EdgeInsets.all(8),
          child: pw.Row(children: [
            if (logo != null) pw.SizedBox(height: 44, child: pw.Image(logo)),
            pw.SizedBox(width: 10),
            pw.Text(
                nomePeriodo == 'Folha Mensal'
                    ? 'DEMONSTRATIVO DE PAGAMENTO MENSAL'
                    : 'DEMONSTRATIVO DE PAGAMENTO - ${nomePeriodo.toUpperCase()}',
                style: const pw.TextStyle(fontSize: 11)),
          ]),
        ),
        if (razao != null || cnpj != null)
          caixa([
            pw.Expanded(child: campo('Razão Social', razao ?? '')),
            campo('CNPJ', cnpj ?? '', direita: true),
          ]),
        caixa([
          pw.SizedBox(width: 90, child: campo('Matrícula', matricula)),
          pw.Expanded(child: campo('Nome', colab?.nome ?? '')),
        ]),
        if (temLinhaAdmissao)
          caixa([
            pw.Expanded(flex: 3, child: campo('Função', cargo)),
            pw.Expanded(
                flex: 2,
                child: campo('Data de Admissão', _dataBr(colab?.dataAdmissao))),
            pw.Expanded(
                flex: 2, child: campo('Competência', '${_meses[mes - 1]}/$ano')),
          ])
        else
          caixa([pw.Expanded(child: campo('Competência', '${_meses[mes - 1]}/$ano'))]),
        pw.SizedBox(height: 10),
        pw.Table(
          border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.4)),
          columnWidths: {
            0: const pw.FixedColumnWidth(42),
            1: const pw.FlexColumnWidth(),
            2: const pw.FixedColumnWidth(58),
            3: const pw.FixedColumnWidth(78),
            4: const pw.FixedColumnWidth(78),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: fundoCab),
              children: [
                for (final t in ['Código', 'Descrição', 'Referência', 'Provento', 'Desconto'])
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(t,
                        textAlign: t == 'Descrição' || t == 'Código'
                            ? pw.TextAlign.left
                            : pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ),
              ],
            ),
            for (final e in eventos)
              pw.TableRow(children: [
                celula('${e['codigo']}'),
                celula('${e['descricao']}'),
                celula(e['referencia'] == null ? '' : formatarValorFolha(e['referencia'] as num),
                    direita: true),
                celula(e['tipo'] == 'Provento' ? formatarValorFolha(e['valor'] as num) : '',
                    direita: true),
                celula(e['tipo'] == 'Desconto' ? formatarValorFolha(e['valor'] as num) : '',
                    direita: true),
              ]),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: borda)),
          child: pw.Column(children: [
            pw.Row(children: [
              if (resumo != null) celulaTotal('Base para FGTS', formatarValorFolha((resumo['base_fgts'] ?? 0) as num)),
              if (resumo != null) celulaTotal('FGTS do Mês', formatarValorFolha((resumo['fgts_mes'] ?? 0) as num)),
              celulaTotal('Total de Proventos', formatarValorFolha(totalProventos)),
            ]),
            pw.Divider(height: 0, color: borda, thickness: 0.6),
            pw.Row(children: [
              if (resumo != null) celulaTotal('Base Cálc. IRRF', formatarValorFolha((resumo['base_irrf'] ?? 0) as num)),
              if (resumo != null) celulaTotal('Pensão Alimentícia', formatarValorFolha(pensao)),
              celulaTotal('Total de Descontos', formatarValorFolha(totalDescontos)),
            ]),
            pw.Divider(height: 0, color: borda, thickness: 0.6),
            pw.Row(children: [
              if (resumo != null) celulaTotal('Sal. Contribuição INSS', formatarValorFolha((resumo['base_inss'] ?? 0) as num)),
              if (resumo != null) pw.Expanded(child: pw.SizedBox()),
              celulaTotal('Líquido a Receber', formatarValorFolha(liquido), destaque: true),
            ]),
          ]),
        ),
        pw.SizedBox(height: 8),
        pw.Text('Documento gerado pelo app Gente Pole.',
            style: const pw.TextStyle(fontSize: 7.5, color: cinza)),
      ],
    ),
  );

  final bytes = await doc.save();
  final nome = (colab?.nome ?? matricula)
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
  await Printing.sharePdf(
    bytes: bytes,
    filename: 'contracheque_${nome}_$ano${mes.toString().padLeft(2, '0')}.pdf',
  );
}
