import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/api_service.dart';

/// Conversa RH <-> gestor sobre uma candidatura (tabela `candidatura_mensagens`).
/// [papel] = 'rh' ou 'gestor' (lado de quem está usando). Tolerante a tabela
/// ausente: se der erro, o ícone aparece sem badge e o thread mostra o erro.
class CandidaturaChatBotao extends StatefulWidget {
  final int candidaturaId;
  final String nomeCandidato;
  final String papel;
  final int autorId;
  final String autorNome;
  final double tamanho;
  final Color cor;

  const CandidaturaChatBotao({
    super.key,
    required this.candidaturaId,
    required this.nomeCandidato,
    required this.papel,
    required this.autorId,
    required this.autorNome,
    this.tamanho = 20,
    this.cor = const Color(0xFFFF6B00),
  });

  @override
  State<CandidaturaChatBotao> createState() => _CandidaturaChatBotaoState();
}

class _CandidaturaChatBotaoState extends State<CandidaturaChatBotao> {
  int _naoLidas = 0;

  String get _outroLado => widget.papel == 'rh' ? 'gestor' : 'rh';

  @override
  void initState() {
    super.initState();
    _contar();
  }

  Future<void> _contar() async {
    try {
      final res = await Supabase.instance.client
          .from('candidatura_mensagens')
          .select('id')
          .eq('candidatura_id', widget.candidaturaId)
          .eq('autor_papel', _outroLado)
          .isFilter('lida_em', null);
      if (mounted) setState(() => _naoLidas = (res as List).length);
    } catch (_) {}
  }

  Future<void> _abrir() async {
    await mostrarCandidaturaChat(
      context,
      candidaturaId: widget.candidaturaId,
      nomeCandidato: widget.nomeCandidato,
      papel: widget.papel,
      autorId: widget.autorId,
      autorNome: widget.autorNome,
    );
    _contar();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Conversa sobre o candidato',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _abrir,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Badge(
            isLabelVisible: _naoLidas > 0,
            label: Text('$_naoLidas'),
            child: Icon(Icons.chat_bubble_outline,
                size: widget.tamanho, color: widget.cor),
          ),
        ),
      ),
    );
  }
}

Future<void> mostrarCandidaturaChat(
  BuildContext context, {
  required int candidaturaId,
  required String nomeCandidato,
  required String papel,
  required int autorId,
  required String autorNome,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _CandidaturaChatSheet(
      candidaturaId: candidaturaId,
      nomeCandidato: nomeCandidato,
      papel: papel,
      autorId: autorId,
      autorNome: autorNome,
    ),
  );
}

class _CandidaturaChatSheet extends StatefulWidget {
  final int candidaturaId;
  final String nomeCandidato;
  final String papel;
  final int autorId;
  final String autorNome;

  const _CandidaturaChatSheet({
    required this.candidaturaId,
    required this.nomeCandidato,
    required this.papel,
    required this.autorId,
    required this.autorNome,
  });

  @override
  State<_CandidaturaChatSheet> createState() => _CandidaturaChatSheetState();
}

class _CandidaturaChatSheetState extends State<_CandidaturaChatSheet> {
  final _client = Supabase.instance.client;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _msgs = [];
  bool _loading = true;
  bool _enviando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final res = await _client
          .from('candidatura_mensagens')
          .select()
          .eq('candidatura_id', widget.candidaturaId)
          .order('criado_em', ascending: true);
      if (!mounted) return;
      setState(() {
        _msgs = List<Map<String, dynamic>>.from(res as List);
        _loading = false;
        _erro = null;
      });
      _marcarLidas();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _erro = 'Conversa indisponível no momento.';
      });
    }
  }

  Future<void> _marcarLidas() async {
    try {
      await _client
          .from('candidatura_mensagens')
          .update({'lida_em': DateTime.now().toUtc().toIso8601String()})
          .eq('candidatura_id', widget.candidaturaId)
          .eq('autor_papel', widget.papel == 'rh' ? 'gestor' : 'rh')
          .isFilter('lida_em', null);
    } catch (_) {}
  }

  Future<void> _enviar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      await _client.from('candidatura_mensagens').insert({
        'candidatura_id': widget.candidaturaId,
        'autor_id': widget.autorId,
        'autor_nome': widget.autorNome,
        'autor_papel': widget.papel,
        'texto': texto,
      });
      _ctrl.clear();
      await _carregar();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível enviar a mensagem.')));
      }
    }
    if (mounted) setState(() => _enviando = false);
  }

  String _hora(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)} ${p(d.hour)}:${p(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(children: [
              const Icon(Icons.chat_bubble_outline, color: Color(0xFFFF6B00)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Conversa · ${widget.nomeCandidato}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _erro != null
                    ? Center(child: Text(_erro!))
                    : _msgs.isEmpty
                        ? const Center(
                            child: Text('Nenhuma mensagem ainda.',
                                style: TextStyle(color: Color(0xFF6B7280))))
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.all(12),
                            itemCount: _msgs.length,
                            itemBuilder: (_, i) => _bolha(_msgs[i]),
                          ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Escreva uma mensagem...',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B00)),
                onPressed: _enviando ? null : _enviar,
                icon: const Icon(Icons.send, size: 18),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _bolha(Map<String, dynamic> m) {
    final minha = m['autor_papel'] == widget.papel;
    final papel = m['autor_papel'] == 'rh' ? 'RH' : 'Gestor';
    return Align(
      alignment: minha ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: minha ? const Color(0xFFFFF1E6) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${m['autor_nome'] ?? ''} ($papel) · ${_hora(m['criado_em']?.toString())}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280))),
            const SizedBox(height: 3),
            Text(m['texto']?.toString() ?? '',
                style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Abre o thread a partir do push ('candidato_chat'). Só no app (gestor).
Future<void> abrirCandidaturaChatDaNotificacao(
    BuildContext context, int candidaturaId) async {
  final col = ApiService().colaboradorAtual;
  var nome = 'Candidato';
  try {
    final r = await Supabase.instance.client
        .from('candidaturas')
        .select('candidatos(nome)')
        .eq('id', candidaturaId)
        .maybeSingle();
    nome = (r?['candidatos'] as Map?)?['nome']?.toString() ?? nome;
  } catch (_) {}
  if (!context.mounted) return;
  await mostrarCandidaturaChat(
    context,
    candidaturaId: candidaturaId,
    nomeCandidato: nome,
    papel: 'gestor',
    autorId: col?.id ?? 0,
    autorNome: col?.nome ?? 'Gestor',
  );
}
