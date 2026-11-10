import 'package:gentepole/core/nome_foto.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../models/colaborador_model.dart';
import '../../services/api_service.dart';

class MinhaEquipeScreen extends StatefulWidget {
  const MinhaEquipeScreen({super.key});

  @override
  State<MinhaEquipeScreen> createState() => _MinhaEquipeScreenState();
}

class _MinhaEquipeScreenState extends State<MinhaEquipeScreen> {
  final _api = ApiService();
  late Future<List<ColaboradorModel>> _futureEquipe;
  final _buscaCtrl = TextEditingController();
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _futureEquipe = _carregarEquipe();
    _buscaCtrl.addListener(() => setState(() => _busca = _buscaCtrl.text));
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  /// Carrega a equipe com as mesmas mensagens de erro do web.
  Future<List<ColaboradorModel>> _carregarEquipe() async {
    if (_api.colaboradorAtual == null) {
      throw 'Perfil de colaborador não encontrado.';
    }
    try {
      final setores = await _api.buscarSetoresEfetivosDoGestor();
      if (setores.isEmpty) throw 'Nenhum setor associado a este gestor.';
      return await _api.buscarMinhaEquipeVisao();
    } catch (e) {
      if (e is String) rethrow;
      throw 'Erro ao carregar equipe: $e';
    }
  }

  void _recarregar() {
    setState(() => _futureEquipe = _carregarEquipe());
  }

  List<ColaboradorModel> _filtrar(List<ColaboradorModel> equipe) {
    final q = _busca.trim().toLowerCase();
    var lista = equipe;
    if (q.isNotEmpty) {
      lista = lista.where((c) {
        final nome = c.nome.toLowerCase();
        final cargo = (c.cargo ?? '').toLowerCase();
        final matricula = c.matricula.toLowerCase();
        return nome.contains(q) || cargo.contains(q) || matricula.contains(q);
      }).toList();
    }
    final ordenada = [...lista];
    ordenada.sort((a, b) {
      final diasA = _diasParaAniversario(a.dataNascimento);
      final diasB = _diasParaAniversario(b.dataNascimento);
      // Quem ainda vai fazer aniversário (dias >= 0) vem primeiro, do mais
      // próximo pro mais distante; quem já passou fica depois, em ordem
      // alfabética.
      if (diasA != null && diasB != null) return diasA.compareTo(diasB);
      if (diasA != null) return -1;
      if (diasB != null) return 1;
      return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });
    return ordenada;
  }

  /// Dias até o próximo aniversário, ou `null` se já passou este ano
  /// (aniversariante de hoje conta como 0).
  int? _diasParaAniversario(String? dataNascimento) {
    if (dataNascimento == null) return null;
    final nasc = DateTime.tryParse(dataNascimento);
    if (nasc == null) return null;
    final hoje = DateTime.now();
    final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);
    var proximo = DateTime(hoje.year, nasc.month, nasc.day);
    if (proximo.isBefore(hojeSemHora)) return null;
    return proximo.difference(hojeSemHora).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final setor = _api.colaboradorAtual?.setor ?? '';

    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 220,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 24, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Minha Equipe',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (setor.isNotEmpty)
                              Text(
                                setor,
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 24),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: FutureBuilder<List<ColaboradorModel>>(
                      future: _futureEquipe,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.magenta),
                          );
                        }

                        if (snap.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline,
                                      size: 48, color: AppColors.cinzaTexto),
                                  const SizedBox(height: 12),
                                  Text(
                                    '${snap.error}',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                        color: AppColors.cinzaTexto),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _recarregar,
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.laranja),
                                    child: Text('Tentar novamente',
                                        style: GoogleFonts.poppins(
                                            color: Colors.white)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        final equipeCompleta = snap.data ?? [];
                        final equipe = _filtrar(equipeCompleta);

                        if (equipeCompleta.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.group_outlined,
                                    size: 56, color: AppColors.cinzaTexto),
                                const SizedBox(height: 16),
                                Text(
                                  'Nenhum colaborador encontrado',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.dark,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Nenhum colaborador no seu setor.',
                                  style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: AppColors.cinzaTexto),
                                ),
                              ],
                            ),
                          );
                        }

                        return RefreshIndicator(
                          color: AppColors.magenta,
                          onRefresh: () async {
                            _recarregar();
                          },
                          child: ListView(
                            padding:
                                const EdgeInsets.fromLTRB(16, 20, 16, 32),
                            children: [
                              TextField(
                                controller: _buscaCtrl,
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText:
                                      'Buscar por nome, cargo ou matrícula...',
                                  hintStyle: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: AppColors.cinzaTexto),
                                  prefixIcon: const Icon(Icons.search_rounded,
                                      size: 20),
                                  suffixIcon: _busca.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(
                                              Icons.close_rounded,
                                              size: 18),
                                          onPressed: () =>
                                              _buscaCtrl.clear(),
                                        ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '${equipe.length} colaborador${equipe.length == 1 ? '' : 'es'}',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.cinzaTexto,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (equipe.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 24),
                                  child: Center(
                                    child: Text(
                                      'Nenhum colaborador encontrado.',
                                      style: GoogleFonts.poppins(
                                          color: AppColors.cinzaTexto),
                                    ),
                                  ),
                                )
                              else
                                ...equipe.map((c) => _cardColaborador(c)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _textoAniversario(int dias) {
    if (dias == 0) return 'Aniversário hoje!';
    if (dias == 1) return 'Aniversário amanhã';
    return 'Faltam $dias dias p/ aniversário';
  }

  Widget _cardColaborador(ColaboradorModel c) {
    final iniciais = c.nome
        .trim()
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    final dias = _diasParaAniversario(c.dataNascimento);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showDialog(
        context: context,
        builder: (_) => _DadosColaboradorDialog(colaborador: c),
      ),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          FotoClicavel(
            url: c.fotoUrl,
            nome: c.nome,
            child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.laranja.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: c.fotoUrl != null
                ? ClipOval(
                    child: Image.network(c.fotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _avatarIniciais(iniciais)),
                  )
                : _avatarIniciais(iniciais),
          ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.nome,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.dark,
                  ),
                ),
                if (c.cargo != null && c.cargo!.isNotEmpty)
                  Text(
                    c.cargo!,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.cinzaTexto),
                  ),
                if (dias != null)
                  Text(
                    _textoAniversario(dias),
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: dias == 0 ? FontWeight.w700 : FontWeight.w500,
                      color: dias == 0 ? AppColors.laranja : AppColors.magenta,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            c.matricula,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.cinzaTexto,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _avatarIniciais(String iniciais) {
    return Center(
      child: Text(
        iniciais,
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.laranja,
        ),
      ),
    );
  }
}

// ─── Dados do colaborador (abre ao tocar no card) ────────────────────────────
//
// Só dados cadastrais e hierarquia. Exames, pesquisas respondidas, SAP e CPF
// ficam de fora de propósito (mesma regra do web).

class _DadosColaboradorDialog extends StatefulWidget {
  final ColaboradorModel colaborador;
  const _DadosColaboradorDialog({required this.colaborador});

  @override
  State<_DadosColaboradorDialog> createState() =>
      _DadosColaboradorDialogState();
}

class _DadosColaboradorDialogState extends State<_DadosColaboradorDialog> {
  List<Map<String, dynamic>> _hierarquia = [];
  Map<String, dynamic>? _extras;

  static const _niveis = {
    'gerente_geral': 'Gerente Geral',
    'gestor': 'Gestor',
    'coordenador': 'Coordenador',
    'supervisor': 'Supervisor',
    'encarregado': 'Encarregado',
    'lider': 'Líder',
  };

  @override
  void initState() {
    super.initState();
    final api = ApiService();
    final id = widget.colaborador.id;
    api.buscarHierarquiaResolvidaDoColaborador(id).then((h) {
      if (mounted) setState(() => _hierarquia = h);
    }).catchError((_) {});
    api.buscarDadosExtrasColaborador(id).then((e) {
      if (mounted) setState(() => _extras = e);
    }).catchError((_) {});
  }

  String _fmt(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return '—';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(dt.day)}/${p(dt.month)}/${dt.year}';
  }

  /// "2 anos e 3 meses" a partir da admissão.
  String? _tempoDeCasa(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return null;
    final hoje = DateTime.now();
    var meses = (hoje.year - dt.year) * 12 + hoje.month - dt.month;
    if (hoje.day < dt.day) meses--;
    if (meses < 1) return 'menos de 1 mês';
    final anos = meses ~/ 12;
    final resto = meses % 12;
    final partes = [
      if (anos > 0) '$anos ${anos == 1 ? 'ano' : 'anos'}',
      if (resto > 0) '$resto ${resto == 1 ? 'mês' : 'meses'}',
    ];
    return partes.join(' e ');
  }

  Widget _item(String rotulo, String? valor) {
    if (valor == null || valor.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(rotulo,
            style: GoogleFonts.poppins(
                fontSize: 11, color: AppColors.cinzaTexto)),
        SelectableText(valor,
            style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.dark)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colaborador;
    final nome = c.nome;
    final fotoUrl = c.fotoUrl;
    final iniciais = nome
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final admissao = c.dataAdmissao;
    final tempo = _tempoDeCasa(admissao);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.laranja.withOpacity(0.12),
                  backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty
                      ? NetworkImage(fotoUrl)
                      : null,
                  child: fotoUrl == null || fotoUrl.isEmpty
                      ? Text(iniciais,
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              color: AppColors.laranja))
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nome,
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.dark)),
                        Text(c.cargo ?? '',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: AppColors.cinzaTexto)),
                      ]),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ]),
              const Divider(height: 28),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _item('Matrícula', c.matricula),
                      _item('Setor', c.setor),
                      _item(
                          'Data de admissão',
                          admissao == null
                              ? null
                              : '${_fmt(admissao)}${tempo != null ? '  ·  $tempo de casa' : ''}'),
                      _item('Data de nascimento',
                          c.dataNascimento == null ? null : _fmt(c.dataNascimento)),
                      _item('Horário de trabalho',
                          _extras?['horario_trabalho']?.toString()),
                      _item('E-mail', _extras?['email']?.toString()),
                      if (_hierarquia.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Hierarquia',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.laranja)),
                        const SizedBox(height: 8),
                        for (final h in _hierarquia)
                          _item(
                              _niveis[h['nivel']] ?? '${h['nivel']}',
                              (h['colaboradores'] as Map?)?['nome'] as String?),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
