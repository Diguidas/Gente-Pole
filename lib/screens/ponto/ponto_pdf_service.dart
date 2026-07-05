import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Gera o relatório mensal da Calculadora de Ponto (horas normais + horas
/// extras/sobreaviso) em PDF, com o logo da Pole no cabeçalho.
class PontoPdfService {
  static const _corPonto = PdfColor.fromInt(0xFF0EA5E9);
  static const _corExtra = PdfColor.fromInt(0xFF7C3AED);
  static const _dark = PdfColor.fromInt(0xFF1A202C);
  static const _cinzaTexto = PdfColor.fromInt(0xFF718096);
  static const _cinzaClaro = PdfColor.fromInt(0xFFF7FAFC);
  static const _borda = PdfColor.fromInt(0xFFE2E8F0);
  static const _erro = PdfColor.fromInt(0xFFEF4444);
  static const _sucesso = PdfColor.fromInt(0xFF10B981);

  static Future<void> gerar({
    required String nomeColaborador,
    required String mesAno,
    required List<Map<String, dynamic>> registros,
    required List<Map<String, dynamic>> horasExtras,
    required int saldoMesMin,
    required int? Function(Map<String, dynamic>) horasTrabalhadasMin,
    required int horasEsperadasMin,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.poppinsRegular();
    final fontBold = await PdfGoogleFonts.poppinsBold();
    final fontSemiBold = await PdfGoogleFonts.poppinsMedium();
    final logoBytes = await rootBundle.load('assets/logo_pole.png');
    final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());

    final totalExtraMin = horasExtras.fold<int>(0, (s, h) => s + (h['minutos'] as int));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (ctx) => _buildHeader(logo, nomeColaborador, mesAno, fontBold, fontSemiBold, font, ctx.pageNumber == 1),
        footer: (ctx) => _buildFooter(ctx, font),
        build: (ctx) => [
          pw.SizedBox(height: 16),
          pw.Row(children: [
            pw.Expanded(child: _cardResumo('Saldo do mês', _formatarSaldo(saldoMesMin), saldoMesMin < 0 ? _erro : _sucesso, fontBold, font)),
            pw.SizedBox(width: 10),
            pw.Expanded(child: _cardResumo('Horas extras/sobreaviso', _formatarSaldo(totalExtraMin).replaceFirst('+', ''), _corExtra, fontBold, font)),
          ]),
          pw.SizedBox(height: 20),

          _secaoTitulo('Registros de Ponto', fontBold),
          pw.SizedBox(height: 8),
          _tabelaRegistros(registros, horasTrabalhadasMin, horasEsperadasMin, font, fontSemiBold),

          if (horasExtras.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _secaoTitulo('Horas Extras / Sobreaviso', fontBold),
            pw.SizedBox(height: 8),
            _tabelaHorasExtras(horasExtras, font, fontSemiBold),
          ],
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: 'ponto_${nomeColaborador.replaceAll(' ', '_').toLowerCase()}_$mesAno.pdf',
    );
  }

  static pw.Widget _buildHeader(pw.MemoryImage logo, String nome, String mesAno, pw.Font fontBold, pw.Font fontSemiBold, pw.Font font, bool isFirstPage) {
    if (!isFirstPage) {
      return pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(nome, style: pw.TextStyle(font: fontSemiBold, fontSize: 10, color: _cinzaTexto)),
          pw.Text('Calculadora de Ponto — $mesAno', style: pw.TextStyle(font: font, fontSize: 9, color: _cinzaTexto)),
        ]),
        pw.Divider(color: _borda, thickness: 0.5),
        pw.SizedBox(height: 4),
      ]);
    }
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Container(height: 44, width: 44, child: pw.Image(logo, fit: pw.BoxFit.contain)),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Calculadora de Ponto', style: pw.TextStyle(font: fontBold, fontSize: 16, color: _dark)),
            pw.Text(nome, style: pw.TextStyle(font: fontSemiBold, fontSize: 12, color: _corPonto)),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(mesAno, style: pw.TextStyle(font: fontBold, fontSize: 13, color: _dark)),
          pw.Text('Gerado em ${_dataHoje()}', style: pw.TextStyle(font: font, fontSize: 9, color: _cinzaTexto)),
        ]),
      ]),
      pw.SizedBox(height: 10),
      pw.Divider(color: _borda, thickness: 0.8),
    ]);
  }

  static pw.Widget _buildFooter(pw.Context ctx, pw.Font font) {
    return pw.Column(children: [
      pw.Divider(color: _borda, thickness: 0.5),
      pw.SizedBox(height: 4),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Documento pessoal · Calculadora de Ponto', style: pw.TextStyle(font: font, fontSize: 8, color: _cinzaTexto)),
        pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}', style: pw.TextStyle(font: font, fontSize: 8, color: _cinzaTexto)),
      ]),
    ]);
  }

  static pw.Widget _secaoTitulo(String titulo, pw.Font fontBold) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(titulo.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 9, color: _cinzaTexto, letterSpacing: 0.8)),
      pw.SizedBox(height: 4),
      pw.Divider(color: _borda, thickness: 0.5),
    ]);
  }

  static pw.Widget _cardResumo(String label, String valor, PdfColor cor, pw.Font fontBold, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(color: _cinzaClaro, borderRadius: pw.BorderRadius.circular(8), border: pw.Border.all(color: _borda, width: 0.5)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: 9, color: _cinzaTexto)),
        pw.SizedBox(height: 4),
        pw.Text(valor, style: pw.TextStyle(font: fontBold, fontSize: 18, color: cor)),
      ]),
    );
  }

  static pw.Widget _tabelaRegistros(
    List<Map<String, dynamic>> registros,
    int? Function(Map<String, dynamic>) horasTrabalhadasMin,
    int horasEsperadasMin,
    pw.Font font,
    pw.Font fontSemiBold,
  ) {
    if (registros.isEmpty) {
      return pw.Text('Nenhum registro neste mês.', style: pw.TextStyle(font: font, fontSize: 10, color: _cinzaTexto));
    }
    final ordenados = [...registros]..sort((a, b) => (a['data'] as String).compareTo(b['data'] as String));

    return pw.Table(
      border: pw.TableBorder.all(color: _borda, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(1),
        4: pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _cinzaClaro),
          children: [
            _celula('Data', fontSemiBold, header: true),
            _celula('Entrada', fontSemiBold, header: true),
            _celula('Saída', fontSemiBold, header: true),
            _celula('Trabalhado', fontSemiBold, header: true),
            _celula('Saldo', fontSemiBold, header: true),
          ],
        ),
        ...ordenados.map((r) {
          final trabalhado = horasTrabalhadasMin(r);
          final saldoDia = trabalhado != null ? trabalhado - horasEsperadasMin : null;
          final data = DateTime.parse(r['data'] as String);
          return pw.TableRow(children: [
            _celula('${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}', font),
            _celula(_fmt(r['entrada'] as String?), font),
            _celula(_fmt(r['saida'] as String?), font),
            _celula(trabalhado != null ? _formatarSaldo(trabalhado).replaceFirst('+', '') : '—', font),
            _celula(saldoDia != null ? _formatarSaldo(saldoDia) : 'incompleto', fontSemiBold,
                cor: saldoDia == null ? _cinzaTexto : (saldoDia < 0 ? _erro : _sucesso)),
          ]);
        }),
      ],
    );
  }

  static pw.Widget _tabelaHorasExtras(List<Map<String, dynamic>> horasExtras, pw.Font font, pw.Font fontSemiBold) {
    final ordenados = [...horasExtras]..sort((a, b) => (a['data'] as String).compareTo(b['data'] as String));
    return pw.Table(
      border: pw.TableBorder.all(color: _borda, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(0.8),
        4: pw.FlexColumnWidth(1.6),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _cinzaClaro),
          children: [
            _celula('Data', fontSemiBold, header: true),
            _celula('Início', fontSemiBold, header: true),
            _celula('Fim', fontSemiBold, header: true),
            _celula('Total', fontSemiBold, header: true),
            _celula('Observação', fontSemiBold, header: true),
          ],
        ),
        ...ordenados.map((h) {
          final data = DateTime.parse(h['data'] as String);
          final obs = h['observacao'] as String? ?? '';
          return pw.TableRow(children: [
            _celula('${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}', font),
            _celula(_fmt(h['hora_inicio'] as String?), font),
            _celula(_fmt(h['hora_fim'] as String?), font),
            _celula(_formatarSaldo(h['minutos'] as int).replaceFirst('+', ''), fontSemiBold, cor: _corExtra),
            _celula(obs, font),
          ]);
        }),
      ],
    );
  }

  static pw.Widget _celula(String texto, pw.Font font, {bool header = false, PdfColor? cor}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(texto,
          style: pw.TextStyle(font: font, fontSize: header ? 9 : 10, color: cor ?? (header ? _cinzaTexto : _dark))),
    );
  }

  static String _fmt(String? hhmm) {
    if (hhmm == null || hhmm.isEmpty) return '--:--';
    final p = hhmm.split(':');
    return '${p[0].padLeft(2, '0')}:${p[1].padLeft(2, '0')}';
  }

  static String _formatarSaldo(int minutos) {
    final sinal = minutos < 0 ? '-' : '+';
    final abs = minutos.abs();
    final h = abs ~/ 60;
    final m = abs % 60;
    return '$sinal$h:${m.toString().padLeft(2, '0')}';
  }

  static String _dataHoje() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }
}
