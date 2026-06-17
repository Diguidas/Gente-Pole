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

  // Destinatário selecionado
  String _destinatario = 'todos';
  String _destinatarioLabel = 'Todos';

  // Estado do @mention overlay
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
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextoMudou);
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
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
      _sugestoes = resultados;
      _showSugestoes = resultados.isNotEmpty;
      _buscandoSugestoes = false;
    });
  }

  /// Quando o usuário escolhe uma sugestão, substitui o @query pelo valor
  /// e atualiza o destinatário do post.
  void _selecionarMencao(Map<String, String> sugestao) {
    final valor = sugestao['valor']!;
    final label = sugestao['label']!;

    // Substitui o fragmento @query no texto pelo label bonito
    final texto = _ctrl.text;
    final cursor = _ctrl.selection.baseOffset;
    final antes = texto.substring(0, cursor);
    final depois = texto.substring(cursor);
    final novoAntes = antes.replaceAll(RegExp(r'@\w*$'), '$label ');

    _ctrl.value = TextEditingValue(
      text: novoAntes + depois,
      selection: TextSelection.collapsed(offset: novoAntes.length),
    );

    setState(() {
      _destinatario = valor;
      _destinatarioLabel = label;
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
    if (conteudo.isEmpty && _imagemBytes == null) return;

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
    final temConteudo =
        _ctrl.text.trim().isNotEmpty || _imagemBytes != null;

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
                          onPressed: temConteudo ? _publicar : null,
                          style: TextButton.styleFrom(
                            backgroundColor: temConteudo
                                ? AppColors.magenta
                                : AppColors.cinzaTexto.withOpacity(0.15),
                            foregroundColor: temConteudo
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
                        // Chip de destinatário
                        if (_destinatario != 'todos')
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.magenta.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _destinatarioLabel,
                                    style: GoogleFonts.poppins(
                                      color: AppColors.magenta,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      _destinatario = 'todos';
                                      _destinatarioLabel = 'Todos';
                                    }),
                                    child: Icon(Icons.close_rounded,
                                        size: 14,
                                        color: AppColors.magenta),
                                  ),
                                ],
                              ),
                            ),
                          ),

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
    return Container(
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
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.magenta)),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
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