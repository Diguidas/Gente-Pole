import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../core/app_theme.dart';

class HumorWidget extends StatefulWidget {
  const HumorWidget({super.key});

  @override
  State<HumorWidget> createState() => _HumorWidgetState();
}

class _HumorWidgetState extends State<HumorWidget> {
  final _api = ApiService();
  Map<String, dynamic>? _registroHoje;
  Map<String, dynamic>? _banner;
  bool _loading = true;
  bool _erro = false;

  static const _emojis = ['😢', '😟', '😐', '😊', '😄'];
  static const _labels = ['Muito ruim', 'Ruim', 'Neutro', 'Bom', 'Ótimo'];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) setState(() { _loading = true; _erro = false; });
    try {
      final reg = await _api.buscarHumorHoje();
      Map<String, dynamic>? banner;
      if (reg != null) {
        banner = await _api.buscarBannerHumor((reg['nivel'] as num).toInt());
      }
      if (mounted) {
        setState(() {
          _registroHoje = reg;
          _banner = banner;
          _loading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('❌ HumorWidget erro: $e\n$stack');
      if (mounted) setState(() { _loading = false; _erro = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_erro) {
      return _ErroCard(onRetry: _carregar);
    }

    if (_registroHoje != null) return _bannerRegistrado();
    return _seletorHumor();
  }

  Widget _seletorHumor() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEFEFEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Como você está hoje?', style: AppTextStyles.labelSecao),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(5, (i) => GestureDetector(
              onTap: () => _abrirBottomSheet(i + 1),
              child: Column(
                children: [
                  Text(_emojis[i], style: const TextStyle(fontSize: 28)),
                  const SizedBox(height: 3),
                  Text(
                    _labels[i],
                    style: AppTextStyles.corpoMinimo.copyWith(fontSize: 9),
                  ),
                ],
              ),
            )),
          ),
        ],
      ),
    );
  }

  void _abrirBottomSheet(int nivel) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '${_emojis[nivel - 1]}  ${_labels[nivel - 1]}',
                style: AppTextStyles.tituloMedio,
              ),
              const SizedBox(height: 8),
              Text('Quer contar o que está sentindo? (opcional)', style: AppTextStyles.corpoCinza),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                maxLines: 3,
                maxLength: 300,
                style: AppTextStyles.corpoNormal,
                decoration: const InputDecoration(
                  hintText: 'Por que estou me sentindo assim...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: _BotaoRegistrar(
                  onConfirm: () => _api.registrarHumor(
                    nivel: nivel,
                    motivo: ctrl.text.trim(),
                  ),
                  onSucesso: () {
                    Navigator.pop(ctx);
                    if (mounted) _carregar();
                  },
                  onErro: () {
                    Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text('Erro ao registrar. Tente novamente.'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ));
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bannerRegistrado() {
    final nivel = (_registroHoje!['nivel'] as num).toInt();
    final imgUrl = _banner?['imagem_url'] as String?;
    final textoPrincipal = _banner?['texto_principal'] as String? ?? _labels[nivel - 1];
    final textoApoio = _banner?['texto_apoio'] as String?;

    return Container(
      constraints: const BoxConstraints(minHeight: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFB347), Color(0xFFFF8C42)],
        ),
        image: imgUrl != null
            ? DecorationImage(
                image: NetworkImage(imgUrl),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.32), BlendMode.darken),
              )
            : null,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '${_emojis[nivel - 1]}  $textoPrincipal',
            style: AppTextStyles.tituloBranco.copyWith(fontSize: 17),
          ),
          if (textoApoio != null)
            Text(textoApoio, style: AppTextStyles.corpoBrancoOpaco),
        ],
      ),
    );
  }
}

class _ErroCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErroCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEFEFEF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xFFBBBBBB), size: 20),
          const SizedBox(height: 6),
          Text(
            'Não foi possível carregar o humor.',
            style: AppTextStyles.corpoCinza,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onRetry,
            child: Text(
              'Tentar novamente',
              style: AppTextStyles.corpoCinza.copyWith(
                color: AppColors.magenta,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BotaoRegistrar extends StatefulWidget {
  final Future<bool> Function() onConfirm;
  final VoidCallback onSucesso;
  final VoidCallback onErro;

  const _BotaoRegistrar({
    required this.onConfirm,
    required this.onSucesso,
    required this.onErro,
  });

  @override
  State<_BotaoRegistrar> createState() => _BotaoRegistrarState();
}

class _BotaoRegistrarState extends State<_BotaoRegistrar> {
  bool _salvando = false;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _salvando ? null : () async {
        setState(() => _salvando = true);
        final ok = await widget.onConfirm();
        if (ok) {
          widget.onSucesso();
        } else {
          if (mounted) setState(() => _salvando = false);
          widget.onErro();
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.magenta,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: _salvando
          ? const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : Text('Registrar humor', style: AppTextStyles.botaoPrimario),
    );
  }
}