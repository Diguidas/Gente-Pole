import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import 'main_layout.dart';
import 'massoterapia/admin_massoterapia_screen.dart';

// ─── Tokens visuais alinhados ao web ────────────────────────────────────────
// Mesmos valores usados no login_screen.dart do sistema web.
const _kLaranjaPrimario = Color(0xFFFF8000);
const _kGradiente = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  stops: [0.0, 0.55, 1.0],
  colors: [
    Color(0xFFFFD000), // amarelo vibrante
    Color(0xFFFF8000), // laranja médio
    Color(0xFFE84E00), // laranja queimado
  ],
);
const _kFillColor = Color(0xFFF8F9FC);
const _kBorderRadius = 12.0;

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

  // ─── Lógica (inalterada) ──────────────────────────────────────────────────

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

  Future<void> _irParaHome() async {
    await _api.salvarSessao(_matriculaController.text.trim());
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainLayout()),
    );
  }

  void _resetar() {
    _animController.reverse().then((_) async {
      await _api.limparSessao();
      if (!mounted) return;
      setState(() {
        _etapa = 0;
        _ehFornecedor = false;
        _matriculaController.clear();
        _senhaController.clear();
        _dataController.clear();
      });
    });
  }

  void _mostrarErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: AppColors.erro, // mesmo token do web
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kBorderRadius),
        ),
      ),
    );
  }

  // ─── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colaborador = _api.colaboradorAtual;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── Banner com gradiente (mesmo do web) ───────────────────────────
          Container(
            height: 300,
            decoration: const BoxDecoration(gradient: _kGradiente),
            child: Stack(
              children: [
                // Bolhas decorativas — mesma linguagem visual do web
                Positioned(
                  top: -60,
                  right: -60,
                  child: _bolha(220, Colors.white, 0.06),
                ),
                Positioned(
                  bottom: 20,
                  left: -40,
                  child: _bolha(160, Colors.white, 0.06),
                ),
                Positioned(
                  top: 80,
                  right: 40,
                  child: _bolha(70, Colors.white, 0.08),
                ),

                // Logo centralizada no banner
                SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Image.asset(
                        'assets/logo.png',
                        width: 300,
                        height: 300,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Card branco flutuante ─────────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.65,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(32, 36, 32, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                  // ── Saudação ───────────────────────────────────────────
                  Text(
                    _etapa == 0 ? 'Boas-vindas!' : 'Olá,',
                    style: GoogleFonts.poppins(
                      fontSize: _etapa == 0 ? 26 : 15,
                      fontWeight: _etapa == 0
                          ? FontWeight.w800
                          : FontWeight.w400,
                      color: _etapa == 0
                          ? AppColors.dark
                          : AppColors.cinzaTexto,
                      letterSpacing: _etapa == 0 ? -0.5 : 0,
                    ),
                  ),

                  if (_etapa == 0)
                    Text(
                      'Faça login para acessar',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.cinzaTexto,
                      ),
                    ),

                  // Nome do colaborador com fade
                  if (_etapa > 0 && colaborador != null) ...[
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: Text(
                        colaborador.nome,
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.dark,
                          height: 1.1,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: Text(
                        [colaborador.cargo, colaborador.setor]
                            .where((e) => e != null && e.isNotEmpty)
                            .join(' · '),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: _kLaranjaPrimario, // laranja em vez de magenta
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ] else if (_etapa > 0)
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: Text(
                        'Gente Pole',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.dark,
                        ),
                      ),
                    ),

                  const SizedBox(height: 28),

                  // ── Campo matrícula ─────────────────────────────────────
                  _campo(
                    controller: _matriculaController,
                    label: 'Matrícula',
                    icon: Icons.badge_outlined,
                    keyboardType: TextInputType.number,
                    enabled: _etapa == 0,
                  ),

                  // ── Campos extras animados ──────────────────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOut,
                    child: _etapa > 0
                        ? Column(
                            children: [
                              const SizedBox(height: 14),
                              _campoSenha(
                                label: _etapa == 1 ? 'Criar senha' : 'Senha',
                              ),
                              if (_etapa == 1) ...[
                                const SizedBox(height: 14),
                                _campo(
                                  controller: _dataController,
                                  label: 'Data de nascimento (DD/MM/AAAA)',
                                  icon: Icons.cake_outlined,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [_dateMask],
                                  hintText: 'Para confirmar sua identidade',
                                ),
                              ],
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),

                  const Spacer(),

                  // ── Botão principal ─────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _carregando ? null : _continuar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kLaranjaPrimario, // laranja do web
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_kBorderRadius),
                        ),
                      ),
                      child: _carregando
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _etapa == 0
                                  ? 'Continuar'
                                  : _etapa == 1
                                      ? 'Criar conta'
                                      : 'Entrar',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),

                  if (_etapa > 0)
                    Center(
                      child: TextButton(
                        onPressed: _resetar,
                        child: Text(
                          'Usar outra matrícula',
                          style: GoogleFonts.poppins(
                            color: AppColors.cinzaTexto,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),

                  // ── Rodapé ──────────────────────────────────────────────
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Acesso restrito a colaboradores autorizados',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppColors.cinzaTexto,
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

  // ─── Helpers de campo com estilo alinhado ao web ──────────────────────────

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
    List<TextInputFormatter>? inputFormatters,
    String? hintText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled,
      inputFormatters: inputFormatters,
      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.dark),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        labelStyle: GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto),
        hintStyle: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto),
        prefixIcon: Icon(icon, color: AppColors.cinzaTexto, size: 20),
        filled: true,
        fillColor: _kFillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_kBorderRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_kBorderRadius),
          borderSide: const BorderSide(color: _kLaranjaPrimario, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_kBorderRadius),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _campoSenha({required String label}) {
    return TextField(
      controller: _senhaController,
      obscureText: !_senhaVisivel,
      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.dark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto),
        prefixIcon: const Icon(Icons.lock_outlined,
            color: AppColors.cinzaTexto, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            _senhaVisivel
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: AppColors.cinzaTexto,
            size: 20,
          ),
          onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
        ),
        filled: true,
        fillColor: _kFillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_kBorderRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_kBorderRadius),
          borderSide: const BorderSide(color: _kLaranjaPrimario, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _bolha(double size, Color cor, double opacidade) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cor.withOpacity(opacidade),
      ),
    );
  }
}