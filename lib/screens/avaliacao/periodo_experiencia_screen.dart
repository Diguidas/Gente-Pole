import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../widgets/app_bar_gradiente.dart';
import '../../services/api_service.dart';
import '../pesquisa/pesquisa_resposta_screen.dart';

/// Lado do colaborador no Período de Experiência: não é mais autoavaliação
/// com nota (isso agora é só do gestor) — é a pesquisa "Período de
/// Experiência", sem nota, que dispara pela data de admissão. Esta tela só
/// localiza a pesquisa pendente e redireciona pra ela; sem pesquisa, explica
/// o motivo.
class PeriodoExperienciaScreen extends StatefulWidget {
  const PeriodoExperienciaScreen({super.key});

  @override
  State<PeriodoExperienciaScreen> createState() =>
      _PeriodoExperienciaScreenState();
}

class _PeriodoExperienciaScreenState extends State<PeriodoExperienciaScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _erro;
  String _motivo =
      'Nenhuma pesquisa de período de experiência disponível no momento.';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final col = _api.colaboradorAtual;
      if (col == null) {
        setState(() {
          _erro = 'Perfil não encontrado.';
          _loading = false;
        });
        return;
      }
      final pesquisa = await _api.buscarPesquisaPeriodoExperienciaPendente(col);
      if (!mounted) return;
      if (pesquisa == null) {
        final motivo = await _api.motivoSemPesquisaPeriodoExperiencia(col);
        if (!mounted) return;
        setState(() {
          _motivo = motivo;
          _loading = false;
        });
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PesquisaRespostaScreen(
          pesquisaId: pesquisa['id'] as int,
          titulo: pesquisa['titulo'] as String? ?? 'Período de Experiência',
          anonima: pesquisa['anonima'] as bool? ?? false,
          pedirOptIn: pesquisa['pedir_opt_in'] as bool? ?? false,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: const AppBarGradiente(titulo: 'Período de Experiência'),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.magenta))
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_erro ?? _motivo,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.corpoNormal),
              ),
            ),
    );
  }
}
