import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

String _dia(String? iso) {
  if (iso == null || iso.length < 10) return '-';
  final p = iso.substring(0, 10).split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

String _hora(String? h) => (h == null || h.length < 5) ? '' : h.substring(0, 5);

// ─────────────────────────────────────────────────────────────────────────────
// ConsultaMedicaScreen (colaborador)
// Solicita uma consulta médica informando o que precisa; o SESMT marca dia e
// hora e o colaborador acompanha aqui (e recebe push 1h antes e na hora).
// ─────────────────────────────────────────────────────────────────────────────

class ConsultaMedicaScreen extends StatefulWidget {
  const ConsultaMedicaScreen({super.key});

  @override
  State<ConsultaMedicaScreen> createState() => _ConsultaMedicaScreenState();
}

class _ConsultaMedicaScreenState extends State<ConsultaMedicaScreen> {
  final _api = ApiService();
  final _motivoCtrl = TextEditingController();
  List<Map<String, dynamic>> _consultas = [];
  bool _loading = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final l = await _api.listarMinhasConsultasMedicas();
      if (mounted) setState(() => _consultas = l);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _solicitar() async {
    if (_motivoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conte o que você precisa na consulta.')));
      return;
    }
    setState(() => _enviando = true);
    final ok = await _api.solicitarConsultaMedica(_motivoCtrl.text);
    if (!mounted) return;
    setState(() => _enviando = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Solicitação enviada! O SESMT vai marcar e você será avisado.'
            : 'Não foi possível enviar. Tente novamente.')));
    if (ok) {
      _motivoCtrl.clear();
      _carregar();
    }
  }

  Color _cor(String s) => switch (s) {
        'agendada' => const Color(0xFF0E7490),
        'realizada' => AppColors.sucesso,
        'cancelada' => Colors.grey,
        _ => AppColors.laranja,
      };

  String _rotulo(String s) => switch (s) {
        'agendada' => 'Agendada',
        'realizada' => 'Realizada',
        'cancelada' => 'Cancelada',
        _ => 'Aguardando agendamento',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Stack(children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
            child: Container(
              height: 160,
              width: double.infinity,
              decoration: const BoxDecoration(gradient: AppColors.gradientePrincipal),
              child: const Center(
                  child: Icon(Icons.medical_information_outlined, size: 56, color: Colors.white70)),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3), shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Consulta médica',
                style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700)),
            Text('Solicite e acompanhe o dia da sua consulta',
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
          ]),
        ),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: RefreshIndicator(
              onRefresh: _carregar,
              color: AppColors.laranja,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Solicitar consulta',
                        style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _motivoCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'O que você precisa? (ex.: dor nas costas há 2 semanas, renovar receita...)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _enviando ? null : _solicitar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.laranja,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _enviando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Enviar solicitação'),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                Text('Minhas consultas',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                if (_loading)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(color: AppColors.laranja)))
                else if (_consultas.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Você ainda não solicitou nenhuma consulta.',
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
                  )
                else
                  for (final c in _consultas) _cartao(c),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _cartao(Map<String, dynamic> c) {
    final st = c['status'] as String;
    final cor = _cor(st);
    final marcada = st == 'agendada' || st == 'realizada';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${c['motivo']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: cor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(_rotulo(st),
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w700, color: cor)),
          ),
        ]),
        if (marcada) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.event, size: 16, color: cor),
            const SizedBox(width: 6),
            Text('${_dia(c['data_agendada'] as String?)} às ${_hora(c['hora_agendada'] as String?)}',
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700, color: cor)),
          ]),
          if ((c['local'] as String?)?.isNotEmpty == true)
            Text('Local: ${c['local']}',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
          if ((c['profissional'] as String?)?.isNotEmpty == true)
            Text('Com: ${c['profissional']}',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
          if ((c['observacao_sesmt'] as String?)?.isNotEmpty == true)
            Text('${c['observacao_sesmt']}',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
          if (st == 'agendada')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Você receberá um aviso 1 hora antes e na hora da consulta.',
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600)),
            ),
        ],
        if (st == 'cancelada' && (c['motivo_cancelamento'] as String?)?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${c['motivo_cancelamento']}',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
          ),
        if (st == 'solicitada')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Solicitada em ${_dia(c['criado_em'] as String?)}. O SESMT vai marcar e te avisar.',
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600)),
          ),
      ]),
    );
  }
}
