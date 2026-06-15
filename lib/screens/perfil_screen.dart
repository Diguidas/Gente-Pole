import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/app_theme.dart';
import '../models/colaborador_model.dart';
import '../services/api_service.dart';
import '../widgets/avatar_colaborador.dart';

class PessoasScreen extends StatefulWidget {
  const PessoasScreen({super.key});

  @override
  State<PessoasScreen> createState() => _PessoasScreenState();
}

class _PessoasScreenState extends State<PessoasScreen> {
  final _api = ApiService();
  final _picker = ImagePicker();
  ColaboradorModel? _supervisor;
  bool _loadingSupervisor = false;
  bool _uploadandoFoto = false;

  @override
  void initState() {
    super.initState();
    _carregarSupervisor();
  }

  Future<void> _carregarSupervisor() async {
    final supId = _api.colaboradorAtual?.supervisorId;
    if (supId == null) return;
    setState(() => _loadingSupervisor = true);
    final sup = await _api.buscarSupervisor(supId);
    if (mounted)
      setState(() {
        _supervisor = sup;
        _loadingSupervisor = false;
      });
  }

  Future<void> _escolherFoto() async {
    final origem = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cinzaTextoOp30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Alterar foto de perfil', style: AppTextStyles.tituloMedio),
            const SizedBox(height: 20),
            _opcaoFoto(
              Icons.camera_alt_outlined,
              'Tirar foto',
              () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 12),
            _opcaoFoto(
              Icons.photo_library_outlined,
              'Escolher da galeria',
              () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (origem == null) return;

    final arquivo = await _picker.pickImage(
      source: origem,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (arquivo == null) return;

    final bytes = await arquivo.readAsBytes();

    setState(() => _uploadandoFoto = true);
    final url = await _api.uploadFotoPerfil(bytes);
    if (mounted) {
      setState(() => _uploadandoFoto = false);
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao salvar foto. Tente novamente.',
              style: AppTextStyles.corpoNormal.copyWith(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _opcaoFoto(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.laranjaOp08,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.laranja, size: 22),
            const SizedBox(width: 14),
            Text(label, style: AppTextStyles.corpoNormal),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _api.colaboradorAtual;
    if (c == null) {
      return const Center(child: Text('Sem dados de colaborador.'));
    }

    return Scaffold(
      body: Stack(
        children: [
          // Fundo gradiente
          Container(
            height: 220,
            decoration: const BoxDecoration(
              color: AppColors.laranja,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // ── Header ──────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Meu Perfil',
                            style: AppTextStyles.tituloGrande.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Card principal ───────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          const BoxShadow(
                            color: AppColors.pretoOp08,
                            blurRadius: 20,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Avatar + nome + cargo
                          const SizedBox(height: 28),
                          _avatarEditavel(c),
                          const SizedBox(height: 14),
                          Text(
                            c.nome,
                            style: AppTextStyles.tituloMedio.copyWith(
                              fontSize: 17,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                          if (c.cargo != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                c.cargo!,
                                style: AppTextStyles.corpoCinza,
                              ),
                            ),
                          const SizedBox(height: 20),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),

                          // Dados em lista
                          _itemInfo(
                            Icons.badge_outlined,
                            'Matrícula',
                            c.matricula,
                          ),
                          if (c.setor != null)
                            _itemInfo(
                              Icons.business_outlined,
                              'Setor',
                              c.setor!,
                            ),
                          if (c.dataAdmissaoFormatada != null)
                            _itemInfo(
                              Icons.calendar_today_outlined,
                              'Admissão',
                              c.dataAdmissaoFormatada!,
                            ),
                          if (c.cpf != null)
                            _itemInfo(
                              Icons.fingerprint_outlined,
                              'CPF',
                              _mascaraCpf(c.cpf!),
                            ),

                          // Supervisor
                          if (_loadingSupervisor)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                color: AppColors.laranja,
                                strokeWidth: 2,
                              ),
                            )
                          else if (_supervisor != null)
                            _itemInfoWidget(
                              Icons.person_outline,
                              'Supervisor',
                              Row(
                                children: [
                                  _avatar(_supervisor!, raio: 12),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _supervisor!.nome,
                                      style: AppTextStyles.corpoMedio,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(ColaboradorModel c, {double raio = 22}) {
    return AvatarColaborador(fotoUrl: c.fotoUrl, nome: c.nome, raio: raio);
  }

  Widget _avatarEditavel(ColaboradorModel c) {
    return Stack(
      alignment: Alignment.center,
      children: [
        _uploadandoFoto
            ? Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: AppColors.laranjaOp15,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.laranja,
                    strokeWidth: 2,
                  ),
                ),
              )
            : AvatarColaborador(fotoUrl: c.fotoUrl, nome: c.nome, raio: 40),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _uploadandoFoto ? null : _escolherFoto,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.laranja,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _itemInfo(IconData icon, String label, String valor) =>
      _itemInfoWidget(
        icon,
        label,
        Text(valor, style: AppTextStyles.corpoMedio),
      );

  Widget _itemInfoWidget(IconData icon, String label, Widget valor) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.laranjaOp08,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.laranja),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.corpoMinimo),
              const SizedBox(height: 2),
              valor,
            ],
          ),
        ),
      ],
    ),
  );

  String _iniciais(String nome) {
    final p = nome.trim().split(' ');
    return p.length >= 2
        ? '${p.first[0]}${p.last[0]}'.toUpperCase()
        : nome.isNotEmpty
        ? nome[0].toUpperCase()
        : '?';
  }

  String _mascaraCpf(String cpf) {
    if (cpf.length != 11) return cpf;
    return '${cpf.substring(0, 3)}.${cpf.substring(3, 6)}.${cpf.substring(6, 9)}-${cpf.substring(9)}';
  }
}
