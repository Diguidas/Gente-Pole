import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import 'main_layout.dart';
import 'massoterapia/admin_massoterapia_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();

  final _matriculaController = TextEditingController();
  final _senhaController = TextEditingController();
  final _dataController = TextEditingController();

  final _dateMask = MaskTextInputFormatter(
    mask: '##/##/####',
    filter: {'#': RegExp(r'[0-9]')},
  );

  // 0 = só matrícula | 1 = primeiro acesso | 2 = login normal
  int _etapa = 0;
  bool _carregando = false;
  bool _senhaVisivel = false;
  bool _ehFornecedor = false;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animController.dispose();
    _matriculaController.dispose();
    _senhaController.dispose();
    _dataController.dispose();
    super.dispose();
  }

  // ─── Lógica ──────────────────────────────────────────────────────────────────

  Future<void> _continuar() async {
    final matricula = _matriculaController.text.trim();

    if (_etapa == 0) {
      if (matricula.isEmpty) return;
      setState(() => _carregando = true);

      final resultado = await _api.verificarMatricula(matricula);

      setState(() => _carregando = false);

      switch (resultado.status) {
        case 'NAO_ENCONTRADO':
          _mostrarErro('Matrícula não encontrada.');
        case 'FORNECEDOR':
          setState(() {
            _etapa = 2;
            _ehFornecedor = true;
          });
          _animController.forward(from: 0);
        case 'PRIMEIRO_ACESSO':
          setState(() => _etapa = 1);
          _animController.forward(from: 0);
        case 'CADASTRADO':
          setState(() => _etapa = 2);
          _animController.forward(from: 0);
      }
      return;
    }

    // ── Primeiro acesso ──────────────────────────────────────────────────────
    if (_etapa == 1) {
      final senha = _senhaController.text;
      final data = _dataController.text.trim();

      if (senha.length < 6) {
        _mostrarErro('A senha deve ter pelo menos 6 caracteres.');
        return;
      }
      if (data.length != 10) {
        _mostrarErro('Informe a data de nascimento completa.');
        return;
      }

      // Converte DD/MM/YYYY → yyyy-mm-dd para o banco
      final parts = data.split('/');
      final dataFormatada = '${parts[2]}-${parts[1]}-${parts[0]}';

      setState(() => _carregando = true);

      final ok = await _api.criarConta(
        matricula: matricula,
        senha: senha,
        dataNascimento: dataFormatada,
      );

      setState(() => _carregando = false);

      if (!ok) {
        _mostrarErro('Erro ao criar conta. Tente novamente.');
        return;
      }

      _irParaHome();
      return;
    }

    // ── Login normal ─────────────────────────────────────────────────────────
    if (_etapa == 2) {
      if (_senhaController.text.isEmpty) return;
      setState(() => _carregando = true);

      if (_ehFornecedor) {
        final fornecedor = await _api.loginFornecedor(
          matricula: matricula,
          senha: _senhaController.text,
        );
        setState(() => _carregando = false);
        if (fornecedor == null) {
          _mostrarErro('Senha incorreta.');
          return;
        }
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminMassoterapiaScreen()),
        );
        return;
      }

      final ok = await _api.validarLogin(
        matricula: matricula,
        senha: _senhaController.text,
      );

      setState(() => _carregando = false);

      if (!ok) {
        _mostrarErro('Senha incorreta.');
        return;
      }

      _irParaHome();
    }
  }

  void _irParaHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainLayout()),
    );
  }

  void _resetar() {
    _animController.reverse().then((_) {
      setState(() {
        _etapa = 0;
        _ehFornecedor = false;
        _matriculaController.clear();
        _senhaController.clear();
        _dataController.clear();
        _api.limparSessao();
      });
    });
  }

  void _mostrarErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.magenta,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colaborador = _api.colaboradorAtual;

    return Scaffold(
      body: Stack(
        children: [
          // Gradiente de fundo
          Container(
            height: 320,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientePrincipal,
            ),
          ),

          // Logo no topo
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: Column(
                  children: [
                    // Substituindo o Icon por Image.asset
                    Image.asset(
                      'assets/logo.png', // Caminho da sua imagem
                      width: 200, // Ajuste o tamanho conforme necessário
                      height: 200,
                    )
                  ],
                ),
              ),
            ),
          ),

          // Card flutuante (conforme design system do projeto)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.68,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(32, 36, 32, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x18000000),
                    blurRadius: 24,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Saudação dinâmica
                  Text(
                    _etapa == 0 ? 'Acesse sua conta' : 'Olá,',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: AppColors.cinzaTexto,
                    ),
                  ),

                  // Nome aparece após digitar matrícula
                  if (_etapa > 0 && colaborador != null)
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: Text(
                        colaborador.nome,
                        style: GoogleFonts.poppins(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                          height: 1.1,
                        ),
                      ),
                    )
                  else
                    Text(
                      'Gente Pole',
                      style: GoogleFonts.poppins(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),

                  // Setor / cargo como subtítulo
                  if (_etapa > 0 && colaborador != null)
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: Text(
                        [
                          colaborador.cargo,
                          colaborador.setor,
                        ].where((e) => e != null && e.isNotEmpty).join(' · '),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: AppColors.magenta,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                  const SizedBox(height: 28),

                  // Campo matrícula
                  TextField(
                    controller: _matriculaController,
                    keyboardType: TextInputType.number,
                    enabled: _etapa == 0,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    decoration: const InputDecoration(
                      labelText: 'Matrícula',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),

                  // Campos extras com animação
                  AnimatedSize(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOut,
                    child: _etapa > 0
                        ? Column(
                            children: [
                              const SizedBox(height: 14),
                              TextField(
                                controller: _senhaController,
                                obscureText: !_senhaVisivel,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: InputDecoration(
                                  labelText: _etapa == 1
                                      ? 'Criar senha'
                                      : 'Senha',
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _senhaVisivel
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                    onPressed: () => setState(
                                      () => _senhaVisivel = !_senhaVisivel,
                                    ),
                                  ),
                                ),
                              ),
                              if (_etapa == 1) ...[
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _dataController,
                                  inputFormatters: [_dateMask],
                                  keyboardType: TextInputType.number,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Data de nascimento (DD/MM/AAAA)',
                                    prefixIcon: Icon(Icons.cake_outlined),
                                    hintText: 'Para confirmar sua identidade',
                                  ),
                                ),
                              ],
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),

                  const Spacer(),

                  // Botão principal
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _carregando ? null : _continuar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.magenta,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: _carregando
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              _etapa == 0
                                  ? 'CONTINUAR'
                                  : _etapa == 1
                                  ? 'CRIAR CONTA'
                                  : 'ENTRAR',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                letterSpacing: 0.8,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),

                  if (_etapa > 0)
                    TextButton(
                      onPressed: _resetar,
                      child: Center(
                        child: Text(
                          'Usar outra matrícula',
                          style: GoogleFonts.poppins(
                            color: AppColors.cinzaTexto,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
