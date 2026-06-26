import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

const _amarelo = Color(0xFFFFB800);
const _amareloClaro = Color(0xFFFFF8E1);

class PlantaoPsicologicoScreen extends StatelessWidget {
  const PlantaoPsicologicoScreen({super.key});

  Future<void> _abrirLink() async {
    final uri = Uri.parse('https://www-amarelosaudemental-com-br.rds.land/lp-pole-alimentos');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _amarelo),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Plantão Psicológico',
            style: GoogleFonts.poppins(
                color: _amarelo, fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_amarelo, Color(0xFFFFD000)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.psychology_outlined,
                        size: 36, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Text('Plantão Psicológico',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18)),
                  const SizedBox(height: 4),
                  Text('Apoio emocional e saúde mental para você',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          color: Colors.white.withOpacity(0.85), fontSize: 13)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Conteúdo
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Secao(titulo: 'O que é o Plantão Psicológico?'),
                  _Texto(
                    'O Plantão Psicológico é um espaço de escuta e apoio emocional '
                    'disponibilizado pela Pole Alimentos em parceria com a Amar.elo — '
                    'plataforma especializada em saúde mental.',
                  ),
                  const SizedBox(height: 16),
                  _Secao(titulo: 'Como funciona?'),
                  _Texto(
                    'Você tem acesso a sessões de até 50 minutos com psicólogos '
                    'devidamente habilitados, de forma online e completamente confidencial. '
                    'O atendimento acontece por videochamada, de onde você estiver.',
                  ),
                  const SizedBox(height: 16),
                  _Secao(titulo: 'Para quem é?'),
                  _Texto(
                    'Este benefício é para todos os colaboradores da Pole Alimentos '
                    'que estejam passando por momentos difíceis, sentindo ansiedade, '
                    'estresse, dificuldades no trabalho ou na vida pessoal — ou que '
                    'simplesmente queiram cuidar da sua saúde mental.',
                  ),
                  const SizedBox(height: 16),
                  _Secao(titulo: 'É sigiloso?'),
                  _Texto(
                    'Sim. Todo o atendimento é sigiloso, seguindo o Código de Ética '
                    'dos Psicólogos. A empresa não tem acesso ao conteúdo das sessões.',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Contatos
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Secao(titulo: 'Contatos e suporte'),
                  _ContatoItem(
                    icone: Icons.business_outlined,
                    label: 'RH Pole',
                    valor: '(85) 9 9660-0062',
                  ),
                  const SizedBox(height: 10),
                  _ContatoItem(
                    icone: Icons.support_agent_outlined,
                    label: 'Time da Amar.elo',
                    valor: '(85) 8204-3858',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Botão CTA
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _abrirLink,
                icon: const Icon(Icons.open_in_new, size: 18, color: Colors.white),
                label: Text(
                  'Acessar o Plantão Psicológico',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _amarelo,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Ao clicar, você será redirecionado para o site da Amar.elo.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 11, color: Colors.grey.shade500),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _amareloClaro,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _amarelo.withOpacity(0.3)),
      ),
      child: child,
    );
  }
}

class _Secao extends StatelessWidget {
  final String titulo;
  const _Secao({required this.titulo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(titulo,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: _amarelo)),
    );
  }
}

class _Texto extends StatelessWidget {
  final String texto;
  const _Texto(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(texto,
        style: GoogleFonts.poppins(
            fontSize: 13, color: Colors.grey.shade700, height: 1.6));
  }
}

class _ContatoItem extends StatelessWidget {
  final IconData icone;
  final String label;
  final String valor;
  const _ContatoItem({required this.icone, required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, color: _amarelo, size: 20),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            Text(valor,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: _amarelo, fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }
}
