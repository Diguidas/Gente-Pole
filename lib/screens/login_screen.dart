import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../core/app_theme.dart';
import '../models/colaborador_model.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'main_layout.dart';
import 'massoterapia/admin_massoterapia_screen.dart';
import 'nutricionista/admin_nutricionista_screen.dart';

const _kLaranjaPrimario = Color(0xFFFF8000);
const _kFillColor = Color(0xCCFFFFFF); // branco com leve transparência
const _kBorderRadius = 12.0;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();

  final _cpfController = TextEditingController();
  final _senhaController = TextEditingController();
  final _dataController = TextEditingController();

  final _dateMask = MaskTextInputFormatter(
    mask: '##/##/####',
    filter: {'#': RegExp(r'[0-9]')},
  );
  final _cpfMask = MaskTextInputFormatter(
    mask: '###.###.###-##',
    filter: {'#': RegExp(r'[0-9]')},
  );

  // 0 = só CPF | 1 = primeiro acesso | 2 = login normal
  int _etapa = 0;
  bool _carregando = false;
  bool _senhaVisivel = false;
  bool _ehFornecedor = false;
  ColaboradorModel? _colaboradorEncontrado;

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
    _cpfController.dispose();
    _senhaController.dispose();
    _dataController.dispose();
    super.dispose();
  }

  Future<void> _continuar() async {
    final cpf = _cpfController.text.trim();

    if (_etapa == 0) {
      if (cpf.isEmpty) return;
      setState(() => _carregando = true);

      final resultado = await _api.verificarCpf(cpf);

      setState(() => _carregando = false);

      switch (resultado.status) {
        case 'NAO_ENCONTRADO':
          _mostrarErro('CPF não encontrado.');
        case 'FORNECEDOR':
          setState(() {
            _etapa = 2;
            _ehFornecedor = true;
          });
          _animController.forward(from: 0);
        case 'PRIMEIRO_ACESSO':
          setState(() {
            _etapa = 1;
            _colaboradorEncontrado = resultado.colaborador;
          });
          _animController.forward(from: 0);
        case 'CADASTRADO':
          setState(() {
            _etapa = 2;
            _colaboradorEncontrado = resultado.colaborador;
          });
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
        matricula: _colaboradorEncontrado!.matricula,
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
          matricula: cpf,
          senha: _senhaController.text,
        );
        setState(() => _carregando = false);
        if (fornecedor == null) {
          _mostrarErro('Senha incorreta.');
          return;
        }
        if (!mounted) return;
        final tipo = fornecedor['tipo'] as String?;
        final Widget telaFornecedor = tipo == 'nutricionista'
            ? const AdminNutricionistaScreen()
            : const AdminMassoterapiaScreen();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => telaFornecedor),
        );
        return;
      }

      final ok = await _api.validarLogin(
        matricula: _colaboradorEncontrado!.matricula,
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
    await _api.salvarSessao(_colaboradorEncontrado!.matricula);
    await NotificationService.init();
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
        _colaboradorEncontrado = null;
        _cpfController.clear();
        _senhaController.clear();
        _dataController.clear();
      });
    });
  }

  void _mostrarErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: AppColors.erro,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kBorderRadius),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colaborador = _api.colaboradorAtual;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Fundo full-screen
          Positioned.fill(
            child: Image.asset('assets/fundo.png', fit: BoxFit.cover),
          ),

          // Botão voltar
          if (_etapa > 0)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Color(0xFF5C3A1E), size: 20),
                  onPressed: _resetar,
                ),
              ),
            ),

          // Conteúdo principal — scroll para suportar teclado
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 56),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Topo ──────────────────────────────────────────
                          const SizedBox(height: 24),
                          Center(
                            child: Image.asset(
                              'assets/logo1.png',
                              width: 140,
                              height: 140,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _etapa == 0 ? 'Boas-vindas!' : 'Olá,',
                            style: GoogleFonts.poppins(
                              fontSize: _etapa == 0 ? 28 : 16,
                              fontWeight: _etapa == 0 ? FontWeight.w800 : FontWeight.w400,
                              color: const Color(0xFF3D2000),
                            ),
                          ),
                          if (_etapa == 0)
                            Text(
                              'Faça login para acessar\nsua conta.',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: const Color(0xFF7A5230),
                                height: 1.5,
                              ),
                            ),
                          if (_etapa > 0 && colaborador != null) ...[
                            FadeTransition(
                              opacity: _fadeAnim,
                              child: Text(
                                colaborador.nome,
                                style: GoogleFonts.poppins(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF3D2000),
                                  height: 1.1,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            FadeTransition(
                              opacity: _fadeAnim,
                              child: Text(
                                [colaborador.cargo, colaborador.setor]
                                    .where((e) => e != null && e.isNotEmpty)
                                    .join(' • '),
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: _kLaranjaPrimario,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ] else if (_etapa > 0)
                            FadeTransition(
                              opacity: _fadeAnim,
                              child: Text(
                                'Gente Pole',
                                style: GoogleFonts.poppins(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF3D2000),
                                ),
                              ),
                            ),

                          SizedBox(height: constraints.maxHeight * 0.22),

                          // ── Fundo ─────────────────────────────────────────
                          _campo(
                            controller: _cpfController,
                            label: 'CPF',
                            icon: Icons.person_outline,
                            keyboardType: TextInputType.number,
                            inputFormatters: [_cpfMask],
                            enabled: _etapa == 0,
                          ),

                          AnimatedSize(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeInOut,
                            child: _etapa > 0
                                ? Column(
                                    children: [
                                      const SizedBox(height: 14),
                                      _campoSenha(
                                        label: _etapa == 1 ? 'Criar senha' : 'Sua senha',
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

                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _carregando ? null : _continuar,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kLaranjaPrimario,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _carregando
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2.5),
                                    )
                                  : Text(
                                      _etapa == 0
                                          ? 'Continuar'
                                          : _etapa == 1
                                              ? 'Criar conta'
                                              : 'Entrar',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
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
                                  'Usar outro CPF',
                                  style: GoogleFonts.poppins(
                                    color: const Color(0xFF7A5230),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),

                          const SizedBox(height: 24),
                          Center(
                            child: Text(
                              'Acesso restrito a colaboradores autorizados',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: const Color(0xFF7A5230),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

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
        labelStyle:
            GoogleFonts.poppins(fontSize: 13, color: AppColors.cinzaTexto),
        hintStyle:
            GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto),
        prefixIcon: Icon(icon, color: _kLaranjaPrimario, size: 20),
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
        prefixIcon: const Icon(Icons.lock_outline_rounded,
            color: _kLaranjaPrimario, size: 20),
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
}
