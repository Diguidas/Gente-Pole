import 'package:flutter/material.dart';
import 'package:gentepole/screens/aniversariante_screen.dart';
import '../core/app_theme.dart';
import '../models/aniversariante_model.dart';
import '../models/comunicado_model.dart';
import '../services/api_service.dart';
import '../widgets/avatar_colaborador.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onVerComunicados;
  const HomeScreen({super.key, this.onVerComunicados});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  late Future<List<ComunicadoModel>> _futureComunicados;
  late Future<List<AniversarianteModel>> _futureAniversariantes;

  @override
  void initState() {
    super.initState();
    _futureComunicados = _api.buscarUltimosComunicados();
    _futureAniversariantes = _api.buscarAniversariantesMes();
  }

  void _recarregar() => setState(() {
        _futureComunicados = _api.buscarUltimosComunicados();
        _futureAniversariantes = _api.buscarAniversariantesMes();
      });

  @override
  Widget build(BuildContext context) {
    final colaborador = _api.colaboradorAtual;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 240,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      _avatarUsuario(colaborador?.nome ?? ''),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Olá, ${colaborador?.primeiroNome ?? ''} 👋',
                              style: AppTextStyles.tituloBranco,
                            ),
                            Text(
                              [colaborador?.cargo, colaborador?.setor]
                                  .where((e) => e != null && e!.isNotEmpty)
                                  .join(' · '),
                              style: AppTextStyles.corpoBrancoOpaco,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      _headerIconButton(
                        icon: Icons.lock_outline_rounded,
                        tooltip: 'Alterar senha',
                        onTap: () => _abrirAlterarSenha(context),
                      ),
                      _headerIconButton(
                        icon: Icons.logout_rounded,
                        tooltip: 'Sair',
                        onTap: () => _confirmarSaida(context),
                      ),
                    ],
                  ),
                ),

                // Chips matrícula + admissão
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _chipInfo(Icons.badge_outlined, 'Matrícula',
                          colaborador?.matricula ?? '—'),
                      const SizedBox(width: 10),
                      _chipInfo(Icons.calendar_today_outlined, 'Admissão',
                          colaborador?.dataAdmissaoFormatada ?? '—'),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Corpo ────────────────────────────────────────────────────
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: FutureBuilder<List<ComunicadoModel>>(
                      future: _futureComunicados,
                      builder: (context, snapCom) {
                        if (snapCom.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.magenta),
                          );
                        }

                        final lista = snapCom.data ?? [];

                        return RefreshIndicator(
                          color: AppColors.magenta,
                          onRefresh: () async => _recarregar(),
                          child: ListView(
                            padding:
                                const EdgeInsets.fromLTRB(16, 24, 16, 32),
                            children: [
                              // ── Comunicado destaque ──────────────────────
                              if (lista.isNotEmpty) ...[
                                _labelSecao('📢 Em destaque'),
                                const SizedBox(height: 10),
                                _cardDestaque(lista.first),
                                const SizedBox(height: 24),
                              ],

                              // ── Aniversariantes ──────────────────────────
                              _buildSecaoAniversariantes(),
                              const SizedBox(height: 24),

                              // ── Últimos comunicados ──────────────────────
                              if (lista.length > 1) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _labelSecao('Últimos comunicados'),
                                    TextButton(
                                      onPressed: widget.onVerComunicados,
                                      child: Text(
                                        'Ver todos',
                                        style: AppTextStyles.corpoCinza.copyWith(color: AppColors.magenta, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...lista
                                    .skip(1)
                                    .take(3)
                                    .map(_cardComunicadoSimples),
                              ],

                              if (lista.isEmpty) _semComunicados(),
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

  // ── Seção aniversariantes ────────────────────────────────────────────────────

  Widget _buildSecaoAniversariantes() {
    return FutureBuilder<List<AniversarianteModel>>(
      future: _futureAniversariantes,
      builder: (context, snap) {
        // Carregando — mostra esqueleto leve
        if (snap.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _labelSecao('🎂 Aniversariantes'),
              const SizedBox(height: 10),
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 4,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, __) => Container(
                    width: 70,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final todos = snap.data ?? [];
        if (todos.isEmpty) return const SizedBox.shrink();

        final now = DateTime.now();
        // Hoje primeiro, depois os próximos do mês
        final hoje = todos.where((a) => a.ehHoje).toList();
        final proximos = todos
            .where((a) => !a.ehHoje && a.diaNascimento > now.day)
            .take(10)
            .toList();
        final exibir = [...hoje, ...proximos];
        if (exibir.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _labelSecao('🎂 Aniversariantes'),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AniversariantesScreen()),
                  ),
                  child: Text(
                    'Ver mais',
                    style: AppTextStyles.corpoCinza.copyWith(color: AppColors.magenta, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: exibir.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _cardAniversarianteHorizontal(exibir[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _cardAniversarianteHorizontal(AniversarianteModel a) {
    final ehHoje = a.ehHoje;
    final iniciais = _iniciais(a.colaborador.nome);

    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: ehHoje
            ? Border.all(color: AppColors.magentaOp50, width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: ehHoje ? AppColors.magentaOp15 : AppColors.pretoOp04,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Avatar
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              AvatarColaborador(fotoUrl: a.colaborador.fotoUrl, nome: a.colaborador.nome, raio: 22),
              if (ehHoje)
                const Text('🎂', style: TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          // Dia
          Text(
            ehHoje
                ? 'Hoje'
                : 'Dia ${a.diaNascimento.toString().padLeft(2, '0')}',
            style: AppTextStyles.corpoMinimo.copyWith(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: ehHoje ? AppColors.magenta : AppColors.cinzaTexto,
            ),
          ),
          // Primeiro nome
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              a.colaborador.primeiroNome,
              style: AppTextStyles.corpoMinimo.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.dark),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ── Card destaque ────────────────────────────────────────────────────────────

  Widget _cardDestaque(ComunicadoModel c) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: AppColors.magentaOp18,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagem — se adapta ao tamanho real sem cortar
            if (c.fotoUrl != null && c.fotoUrl!.isNotEmpty)
              Image.network(
                c.fotoUrl!,
                width: double.infinity,
                // sem height fixo — a imagem define sua própria altura
                fit: BoxFit.fitWidth,
                errorBuilder: (_, __, ___) => _bannerSemFoto(),
              )
            else
              _bannerSemFoto(),

            // Texto
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.titulo,
                    style: AppTextStyles.tituloPequeno,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (c.descricao != null && c.descricao!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      c.descricao!,
                      style: AppTextStyles.corpoCinza,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(c.dataFormatada, style: AppTextStyles.corpoMinimo),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bannerSemFoto() => Container(
        height: 120,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppColors.gradientePrincipal,
        ),
        child: const Center(
          child:
              Icon(Icons.campaign_rounded, color: Colors.white, size: 48),
        ),
      );

  // ── Card comunicado simples ──────────────────────────────────────────────────

  Widget _cardComunicadoSimples(ComunicadoModel c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppColors.laranjaOp10,
              ),
              child: c.fotoUrl != null && c.fotoUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        c.fotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.campaign_outlined,
                            color: AppColors.laranja,
                            size: 22),
                      ),
                    )
                  : const Icon(Icons.campaign_outlined,
                      color: AppColors.laranja, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.titulo,
                    style: AppTextStyles.corpoMedio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(c.dataFormatada, style: AppTextStyles.corpoMinimo),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.cinzaTexto, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Widgets de apoio ─────────────────────────────────────────────────────────

  Widget _avatarUsuario(String nome) {
    final iniciais = _iniciais(nome);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.brancoOp25,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          iniciais,
          style: AppTextStyles.corpoBranco.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _headerIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      );

  Widget _chipInfo(IconData icon, String label, String valor) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.brancoOp18,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.corpoMinimo.copyWith(color: AppColors.brancoOp70, fontSize: 10),
                  ),
                  Text(
                    valor,
                    style: AppTextStyles.corpoMenor.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelSecao(String texto) => Text(
        texto,
        style: AppTextStyles.labelSecao,
      );

  Widget _semComunicados() => Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Column(
            children: [
              const Icon(Icons.campaign_outlined,
                  size: 52, color: AppColors.cinzaTexto),
              const SizedBox(height: 12),
              Text('Nenhum comunicado ainda', style: AppTextStyles.corpoCinza.copyWith(fontSize: 15)),
            ],
          ),
        ),
      );

  // ── Modals ───────────────────────────────────────────────────────────────────

  void _abrirAlterarSenha(BuildContext context) {
    final senhaAtualCtrl = TextEditingController();
    final novaSenhaCtrl = TextEditingController();
    bool enviando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.cinzaTextoOp30,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('🔒 Alterar senha', style: AppTextStyles.tituloMedio),
                const SizedBox(height: 20),
                TextField(
                  controller: senhaAtualCtrl,
                  obscureText: true,
                  style: AppTextStyles.corpoNormal,
                  decoration: const InputDecoration(
                    labelText: 'Senha atual',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: novaSenhaCtrl,
                  obscureText: true,
                  style: AppTextStyles.corpoNormal,
                  decoration: const InputDecoration(
                    labelText: 'Nova senha',
                    prefixIcon: Icon(Icons.lock_reset_rounded),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: enviando
                        ? null
                        : () async {
                            final atual = senhaAtualCtrl.text.trim();
                            final nova = novaSenhaCtrl.text.trim();
                            if (atual.isEmpty || nova.length < 6) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Nova senha deve ter pelo menos 6 caracteres.',
                                    style: AppTextStyles.corpoNormal.copyWith(color: Colors.white),
                                  ),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              return;
                            }
                            setModalState(() => enviando = true);
                            final ok = await _api.alterarSenha(
                              senhaAtual: atual,
                              novaSenha: nova,
                            );
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Senha alterada com sucesso!'
                                      : 'Senha atual incorreta.',
                                  style: AppTextStyles.corpoNormal.copyWith(color: Colors.white),
                                ),
                                backgroundColor:
                                    ok ? AppColors.magenta : Colors.red,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.magenta,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: enviando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'Salvar',
                            style: AppTextStyles.botaoPrimario,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmarSaida(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text('Sair da conta?', style: AppTextStyles.tituloPequeno.copyWith(fontWeight: FontWeight.w600)),
        content: Text('Você precisará digitar sua matrícula e senha novamente.', style: AppTextStyles.corpoNormal),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: AppTextStyles.corpoCinza),
          ),
          ElevatedButton(
            onPressed: () {
              _api.limparSessao();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            child: Text('Sair', style: AppTextStyles.botaoPrimario),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _iniciais(String nome) {
    final p = nome.trim().split(' ');
    return p.length >= 2
        ? '${p.first[0]}${p.last[0]}'.toUpperCase()
        : nome.isNotEmpty
            ? nome[0].toUpperCase()
            : '?';
  }
}