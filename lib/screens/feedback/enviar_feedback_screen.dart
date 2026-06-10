import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

class EnviarFeedbackScreen extends StatefulWidget {
  const EnviarFeedbackScreen({super.key});

  @override
  State<EnviarFeedbackScreen> createState() => _EnviarFeedbackScreenState();
}

class _EnviarFeedbackScreenState extends State<EnviarFeedbackScreen> {
  final _api = ApiService();
  final _buscaCtrl = TextEditingController();

  List<Map<String, dynamic>> _todos = [];
  List<Map<String, dynamic>> _filtrados = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carregarColaboradores();
    _buscaCtrl.addListener(_filtrar);
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarColaboradores() async {
    final lista = await _api.buscarTodosColaboradores();
    if (mounted) {
      setState(() {
        _todos = lista;
        _filtrados = lista;
        _loading = false;
      });
    }
  }

  void _filtrar() {
    final q = _buscaCtrl.text.toLowerCase().trim();
    setState(() {
      _filtrados = q.isEmpty
          ? _todos
          : _todos.where((c) {
              final nome = (c['nome'] as String? ?? '').toLowerCase();
              final setor = (c['setor'] as String? ?? '').toLowerCase();
              return nome.contains(q) || setor.contains(q);
            }).toList();
    });
  }

  void _abrirFormulario(Map<String, dynamic> destinatario) {
    final textoCtrl = TextEditingController();
    bool anonimo = false;
    bool enviando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Para quem
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.laranja.withOpacity(0.15),
                      child: Text(
                        _iniciais(destinatario['nome'] as String? ?? ''),
                        style: AppTextStyles.labelSecao.copyWith(
                          color: AppColors.laranja,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          destinatario['nome'] as String? ?? '',
                          style: AppTextStyles.labelSecao,
                        ),
                        Text(
                          destinatario['setor'] as String? ?? '',
                          style: AppTextStyles.corpoCinza,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Campo de texto
                Text('Seu feedback', style: AppTextStyles.corpoMenor.copyWith(
                  fontWeight: FontWeight.w600,
                )),
                const SizedBox(height: 8),
                TextField(
                  controller: textoCtrl,
                  maxLines: 5,
                  maxLength: 1000,
                  style: AppTextStyles.corpoNormal,
                  decoration: InputDecoration(
                    hintText: 'Escreva seu feedback aqui... (mínimo 10 caracteres)',
                    hintStyle: AppTextStyles.corpoCinza,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.laranja),
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                // Toggle anônimo
                GestureDetector(
                  onTap: () => setModal(() => anonimo = !anonimo),
                  child: Row(
                    children: [
                      Switch(
                        value: anonimo,
                        activeColor: AppColors.magenta,
                        onChanged: (v) => setModal(() => anonimo = v),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enviar anonimamente',
                              style: AppTextStyles.corpoNormal.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              anonimo
                                  ? 'Seu nome não será exibido ao destinatário'
                                  : 'Seu nome será exibido ao destinatário',
                              style: AppTextStyles.corpoCinza.copyWith(
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Botão enviar
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: enviando
                        ? null
                        : () async {
                            final texto = textoCtrl.text.trim();
                            if (texto.length < 10) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Escreva pelo menos 10 caracteres.',
                                    style: AppTextStyles.corpoNormal
                                        .copyWith(color: Colors.white),
                                  ),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              return;
                            }
                            setModal(() => enviando = true);
                            final ok = await _api.enviarFeedback(
                              destinatarioId: destinatario['id'] as int,
                              texto: texto,
                              anonimo: anonimo,
                            );
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Feedback enviado com sucesso! 🎉'
                                      : 'Erro ao enviar. Tente novamente.',
                                  style: AppTextStyles.corpoNormal
                                      .copyWith(color: Colors.white),
                                ),
                                backgroundColor:
                                    ok ? AppColors.magenta : Colors.red,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                            if (ok) Navigator.pop(context);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.laranja,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: enviando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text('Enviar feedback', style: AppTextStyles.botaoPrimario),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 200,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💬 Enviar Feedback',
                            style: AppTextStyles.tituloGrande
                                .copyWith(color: Colors.white),
                          ),
                          Text(
                            'Escolha um colega',
                            style: AppTextStyles.corpoBranco
                                .copyWith(color: AppColors.brancoOp80),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Corpo
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Busca
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                          child: TextField(
                            controller: _buscaCtrl,
                            style: AppTextStyles.corpoNormal,
                            decoration: InputDecoration(
                              hintText: 'Buscar por nome ou setor...',
                              hintStyle: AppTextStyles.corpoCinza,
                              prefixIcon: const Icon(Icons.search_rounded),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),

                        // Lista
                        Expanded(
                          child: _loading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.magenta,
                                  ),
                                )
                              : _filtrados.isEmpty
                                  ? Center(
                                      child: Text(
                                        'Nenhum colaborador encontrado',
                                        style: AppTextStyles.corpoCinza,
                                      ),
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 8, 16, 32),
                                      itemCount: _filtrados.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 8),
                                      itemBuilder: (context, i) {
                                        final c = _filtrados[i];
                                        return _cardColaborador(c);
                                      },
                                    ),
                        ),
                      ],
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

  Widget _cardColaborador(Map<String, dynamic> c) {
    final nome = c['nome'] as String? ?? '';
    final setor = c['setor'] as String? ?? '';
    final cargo = c['cargo'] as String? ?? '';

    return GestureDetector(
      onTap: () => _abrirFormulario(c),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.laranja.withOpacity(0.12),
              child: Text(
                _iniciais(nome),
                style: AppTextStyles.labelSecao.copyWith(
                  color: AppColors.laranja,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nome, style: AppTextStyles.labelSecao.copyWith(
                    fontSize: 15,
                  )),
                  const SizedBox(height: 2),
                  Text(
                    [cargo, setor].where((e) => e.isNotEmpty).join(' · '),
                    style: AppTextStyles.corpoCinza,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.cinzaTexto,
            ),
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

