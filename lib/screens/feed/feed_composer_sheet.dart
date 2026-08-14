// screens/feed_composer_sheet.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gentepole/core/app_theme.dart';
import 'package:gentepole/services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';


/// Bottom sheet para criar um post no feed.
/// Abre com showModalBottomSheet — retorna true se o post foi enviado.
class FeedComposerSheet extends StatefulWidget {
  const FeedComposerSheet({super.key});

  @override
  State<FeedComposerSheet> createState() => _FeedComposerSheetState();
}

class _FeedComposerSheetState extends State<FeedComposerSheet> {
  final _api = ApiService();
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();

  // Imagem escolhida
  List<int>? _imagemBytes;
  String? _imagemNome;

  // "Para:" — quem pode ver o post. 'todos' | 'setor' | 'individual'
  String _tipoDestino = 'todos';
  String _destinatario = 'todos';
  List<String> _setores = [];
  final Set<String> _setoresSelecionados = {};
  final _buscaCtrl = TextEditingController();
  List<Map<String, dynamic>> _colabsBusca = [];
  bool _buscandoColabs = false;
  String? _individualSelecionadoNome;

  // Estado do @mention overlay — insere só texto no conteúdo, não afeta "Para:"
  bool _showSugestoes = false;
  List<Map<String, String>> _sugestoes = [];
  bool _buscandoSugestoes = false;
  String _queryMencao = '';

  bool _enviando = false;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextoMudou);
    _carregarSetores();
    _buscaCtrl.addListener(_onBuscaColabMudou);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextoMudou);
    _ctrl.dispose();
    _focusNode.dispose();
    _buscaCtrl.removeListener(_onBuscaColabMudou);
    _buscaCtrl.dispose();
    super.dispose();
  }

  // ── Lógica de "Para:" (destinatário/audiência) ──────────────────────────

  Future<void> _carregarSetores() async {
    final setores = await _api.listarSetoresDistintos();
    if (mounted) setState(() => _setores = setores);
  }

  void _onBuscaColabMudou() {
    final q = _buscaCtrl.text.trim();
    if (q.length < 2) {
      setState(() => _colabsBusca = []);
      return;
    }
    _buscarColabsDestinatario(q);
  }

  Future<void> _buscarColabsDestinatario(String query) async {
    setState(() => _buscandoColabs = true);
    final res = await _api.buscarColaboradoresParaDestinatario(query);
    if (!mounted) return;
    setState(() {
      _colabsBusca = res;
      _buscandoColabs = false;
    });
  }

  void _selecionarTipoDestino(String tipo) {
    setState(() {
      _tipoDestino = tipo;
      _setoresSelecionados.clear();
      _colabsBusca = [];
      _buscaCtrl.clear();
      _individualSelecionadoNome = null;
      _destinatario = tipo == 'todos' ? 'todos' : '';
    });
  }

  void _alternarSetorDestino(String setor) {
    setState(() {
      if (_setoresSelecionados.contains(setor)) {
        _setoresSelecionados.remove(setor);
      } else {
        _setoresSelecionados.add(setor);
      }
      _destinatario =
          _setoresSelecionados.isEmpty ? '' : '@setor:${_setoresSelecionados.join(',')}';
    });
  }

  void _selecionarColabDestino(int id, String nome) {
    setState(() {
      _destinatario = '@colaborador:$id|$nome';
      _individualSelecionadoNome = nome;
      _buscaCtrl.text = nome;
      _colabsBusca = [];
    });
  }

  // ── Lógica de @menção ────────────────────────────────────────────────────────

  void _onTextoMudou() {
    final texto = _ctrl.text;
    final cursor = _ctrl.selection.baseOffset;
    if (cursor < 0) return;

    // Pega a palavra antes do cursor
    final antes = texto.substring(0, cursor);
    final match = RegExp(r'@(\w*)$').firstMatch(antes);

    if (match != null) {
      final query = match.group(1) ?? '';
      if (query != _queryMencao) {
        _queryMencao = query;
        _buscarSugestoes(query);
      }
    } else {
      if (_showSugestoes) {
        setState(() {
          _showSugestoes = false;
          _sugestoes = [];
        });
      }
    }
  }

  Future<void> _buscarSugestoes(String query) async {
    setState(() => _buscandoSugestoes = true);
    final resultados = await _api.buscarSugestoesMencao(query);
    if (!mounted) return;
    setState(() {
      // "Todos" é uma opção de audiência, não faz sentido como menção no texto.
      _sugestoes = resultados.where((s) => s['tipo'] != 'todos').toList();
      _showSugestoes = _sugestoes.isNotEmpty;
      _buscandoSugestoes = false;
    });
  }

  /// Quando o usuário escolhe uma sugestão, substitui o @query pelo label
  /// como texto puro no conteúdo — não afeta quem pode ver o post (isso é
  /// controlado só pela seção "Para:").
  void _selecionarMencao(Map<String, String> sugestao) {
    // O label já vem com "@" (ex: "@Rafael Fiuza de Sousa"). Nomes com
    // espaço ficam entre colchetes para o destaque no feed reconhecer o
    // nome inteiro, não só a primeira palavra.
    final nomeSemArroba = sugestao['label']!.replaceFirst('@', '');
    final marcado = nomeSemArroba.contains(' ') ? '@[$nomeSemArroba]' : '@$nomeSemArroba';

    final texto = _ctrl.text;
    final cursor = _ctrl.selection.baseOffset;
    final antes = texto.substring(0, cursor);
    final depois = texto.substring(cursor);
    final novoAntes = antes.replaceAll(RegExp(r'@\w*$'), '$marcado ');

    _ctrl.value = TextEditingValue(
      text: novoAntes + depois,
      selection: TextSelection.collapsed(offset: novoAntes.length),
    );

    setState(() {
      _showSugestoes = false;
      _sugestoes = [];
    });
  }

  // ── Imagem ───────────────────────────────────────────────────────────────────

  Future<void> _escolherImagem() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _imagemBytes = bytes;
      _imagemNome = picked.name;
    });
  }

  void _removerImagem() => setState(() {
        _imagemBytes = null;
        _imagemNome = null;
      });

  // ── Publicar ─────────────────────────────────────────────────────────────────

  Future<void> _publicar() async {
    final conteudo = _ctrl.text.trim();
    if ((conteudo.isEmpty && _imagemBytes == null) || _destinatario.isEmpty) return;

    setState(() => _enviando = true);

    final ok = await _api.criarPost(
      conteudo: conteudo,
      destinatario: _destinatario,
      imagemBytes: _imagemBytes,
      imagemNome: _imagemNome,
    );

    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true); // sinaliza que houve novo post
    } else {
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao publicar. Tente novamente.',
              style: AppTextStyles.corpoNormal.copyWith(color: Colors.white)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colab = _api.colaboradorAtual;
    final podePublicar =
        (_ctrl.text.trim().isNotEmpty || _imagemBytes != null) &&
            _destinatario.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cinzaTexto.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Cabeçalho
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Text('Nova publicação',
                      style: AppTextStyles.tituloMedio),
                  const Spacer(),
                  _enviando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.magenta),
                        )
                      : TextButton(
                          onPressed: podePublicar ? _publicar : null,
                          style: TextButton.styleFrom(
                            backgroundColor: podePublicar
                                ? AppColors.magenta
                                : AppColors.cinzaTexto.withOpacity(0.15),
                            foregroundColor: podePublicar
                                ? Colors.white
                                : AppColors.cinzaTexto,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                          ),
                          child: Text('Publicar',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              )),
                        ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Avatar + campo de texto
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _avatar(colab?.nome ?? '', colab?.fotoUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Campo de texto
                        TextField(
                          controller: _ctrl,
                          focusNode: _focusNode,
                          autofocus: true,
                          maxLines: null,
                          minLines: 3,
                          style: AppTextStyles.corpoNormal,
                          decoration: InputDecoration(
                            hintText:
                                'No que você está pensando?\nUse @ para mencionar alguém ou um setor…',
                            hintStyle: GoogleFonts.poppins(
                              color: AppColors.cinzaTexto.withOpacity(0.6),
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),

                        // Sugestões de @menção
                        if (_showSugestoes) ...[
                          const SizedBox(height: 8),
                          _buildSugestoesMencao(),
                        ],

                        const SizedBox(height: 14),
                        _buildSecaoPara(),

                        // Preview da imagem
                        if (_imagemBytes != null) ...[
                          const SizedBox(height: 12),
                          Stack(
                            alignment: Alignment.topRight,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  Uint8List.fromList(_imagemBytes!),
                                  height: 180,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              GestureDetector(
                                onTap: _removerImagem,
                                child: Container(
                                  margin: const EdgeInsets.all(8),
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close_rounded,
                                      color: Colors.white, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Barra de ações
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _actionButton(
                    icon: Icons.image_outlined,
                    label: 'Foto',
                    onTap: _escolherImagem,
                  ),
                  const SizedBox(width: 8),
                  _actionButton(
                    icon: Icons.alternate_email_rounded,
                    label: 'Mencionar',
                    onTap: () {
                      // Insere @ na posição atual do cursor
                      final offset = _ctrl.selection.baseOffset
                          .clamp(0, _ctrl.text.length);
                      final texto = _ctrl.text;
                      _ctrl.value = TextEditingValue(
                        text: '${texto.substring(0, offset)}@${texto.substring(offset)}',
                        selection: TextSelection.collapsed(offset: offset + 1),
                      );
                      _focusNode.requestFocus();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSugestoesMencao() {
    // Altura fixa: evita que a tela cresça/encolha a cada tecla digitada
    // conforme o número de sugestões muda.
    return Container(
      height: 168,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: _buscandoSugestoes
          ? const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.magenta),
            )
          : _sugestoes.isEmpty
              ? Center(
                  child: Text('Nenhum resultado',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.cinzaTexto)),
                )
              : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _sugestoes.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16),
              itemBuilder: (_, i) {
                final s = _sugestoes[i];
                final tipo = s['tipo']!;
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: tipo == 'setor'
                        ? AppColors.laranja.withOpacity(0.15)
                        : tipo == 'todos'
                            ? AppColors.magenta.withOpacity(0.15)
                            : const Color(0xFFEEEEEE),
                    child: Icon(
                      tipo == 'setor'
                          ? Icons.group_rounded
                          : tipo == 'todos'
                              ? Icons.people_alt_rounded
                              : Icons.person_rounded,
                      size: 18,
                      color: tipo == 'setor'
                          ? AppColors.laranja
                          : AppColors.magenta,
                    ),
                  ),
                  title: Text(s['label']!,
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: s['sublabel']!.isNotEmpty
                      ? Text(s['sublabel']!,
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.cinzaTexto))
                      : null,
                  onTap: () => _selecionarMencao(s),
                );
              },
            ),
    );
  }

  /// Seção "Para:" — controla quem pode VER o post. Separado da menção
  /// dentro do texto, que é só um destaque visual no conteúdo.
  Widget _buildSecaoPara() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Para: quem vai ver este post',
            style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.dark)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _chipDestino('🌍 Todos', 'todos'),
          _chipDestino('📢 Por setor', 'setor'),
          _chipDestino('👤 Individual', 'individual'),
        ]),
        if (_tipoDestino == 'todos') ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 14, color: Color(0xFFB45309)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Precisa de aprovação do RH antes de aparecer no feed.',
                    style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFFB45309))),
              ),
            ]),
          ),
        ],
        if (_tipoDestino == 'setor') ...[
          const SizedBox(height: 10),
          Text('Toque para selecionar um ou mais setores:',
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto)),
          const SizedBox(height: 8),
          if (_setores.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.magenta),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _setores.map((s) {
                final selecionado = _setoresSelecionados.contains(s);
                return GestureDetector(
                  onTap: () => _alternarSetorDestino(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selecionado
                          ? AppColors.magenta.withOpacity(0.12)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: selecionado ? AppColors.magenta : Colors.transparent),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (selecionado) ...[
                        const Icon(Icons.check_circle_rounded, size: 13, color: AppColors.magenta),
                        const SizedBox(width: 4),
                      ],
                      Text('@$s',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: selecionado ? AppColors.magenta : AppColors.cinzaTexto,
                              fontWeight: selecionado ? FontWeight.w700 : FontWeight.w400)),
                    ]),
                  ),
                );
              }).toList(),
            ),
        ],
        if (_tipoDestino == 'individual') ...[
          const SizedBox(height: 10),
          TextField(
            controller: _buscaCtrl,
            style: GoogleFonts.poppins(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Buscar colaborador pelo nome...',
              hintStyle: GoogleFonts.poppins(color: AppColors.cinzaTexto, fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: const Color(0xFFF3F4F6),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          if (_buscandoColabs)
            const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(color: AppColors.magenta)),
          if (_colabsBusca.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEEEEEE)),
              ),
              child: Column(
                children: _colabsBusca.map((c) {
                  final id = c['id'] as int;
                  final nome = c['nome'] as String? ?? '';
                  final setor = c['setor'] as String? ?? '';
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.magenta.withOpacity(0.15),
                      child: Text(nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                          style: GoogleFonts.poppins(
                              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.magenta)),
                    ),
                    title: Text(nome, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: setor.isNotEmpty
                        ? Text(setor, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto))
                        : null,
                    onTap: () => _selecionarColabDestino(id, nome),
                  );
                }).toList(),
              ),
            ),
          if (_individualSelecionadoNome != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.person_rounded, size: 14, color: AppColors.magenta),
                const SizedBox(width: 4),
                Text('Selecionado: $_individualSelecionadoNome',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.magenta, fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
      ],
    );
  }

  Widget _chipDestino(String label, String valor) {
    final selecionado = _tipoDestino == valor;
    return GestureDetector(
      onTap: () => _selecionarTipoDestino(valor),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selecionado ? AppColors.magenta.withOpacity(0.1) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selecionado ? AppColors.magenta : Colors.transparent),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 12,
                color: selecionado ? AppColors.magenta : AppColors.cinzaTexto,
                fontWeight: selecionado ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }

  Widget _avatar(String nome, String? fotoUrl) {
    if (fotoUrl != null && fotoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: NetworkImage(fotoUrl),
      );
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: AppColors.magenta,
      child: Text(
        _iniciais(nome),
        style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.cinzaTexto),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.cinzaTexto,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  String _iniciais(String nome) {
    final p = nome.trim().split(' ');
    return p.length >= 2
        ? '${p.first[0]}${p.last[0]}'.toUpperCase()
        : nome.isNotEmpty
            ? nome[0].toUpperCase()
            : '?';
  }
}

// Adicione este import no topo do arquivo onde o sheet é chamado:
// import 'dart:typed_data';