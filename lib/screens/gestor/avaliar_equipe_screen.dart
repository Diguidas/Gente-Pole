import 'package:gentepole/core/nome_foto.dart';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/matriz_9box_equipe_card.dart';
import '../../widgets/seletor_nota_widget.dart';
import 'avaliacao_template_picker_dialog.dart';

const _dimensoes = {'desempenho': 'Desempenho', 'potencial': 'Potencial'};
const _tiposAvaliacao = {
  'gestor': 'Só o gestor avalia',
  '180': '180 (gestor e colaborador)',
  '360': '360 (gestor, colaborador e equipe)',
};

/// "Avaliar Equipe" — o gestor avalia cada colaborador do seu setor no
/// ciclo aberto (9-box). Porta a lógica de
/// `avaliar_equipe_gestor_screen.dart` do app admin, adaptada pro shell de
/// telas do gestor no mobile.
class AvaliarEquipeScreen extends StatefulWidget {
  const AvaliarEquipeScreen({super.key});

  @override
  State<AvaliarEquipeScreen> createState() => _AvaliarEquipeScreenState();
}

class _AvaliarEquipeScreenState extends State<AvaliarEquipeScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _erro;
  String? _meuSetor;
  Map<String, dynamic>? _ciclo;
  List<Map<String, dynamic>> _avaliacoes = [];

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
      // Igual ao web: só aborta se o colaborador não existe; o setor de
      // lotação não é obrigatório (gestor pode ter setores só pela hierarquia).
      if (col == null) {
        setState(() {
          _erro = 'Perfil não encontrado.';
          _loading = false;
        });
        return;
      }
      _meuSetor = col.setor;
      // Todos os setores sob responsabilidade do gestor (próprio + atribuídos
      // + hierarquia), não só o setor em que ele está lotado.
      final setores = await _api.buscarSetoresEfetivosDoGestor();
      Map<String, dynamic>? ciclo;
      final avaliacoes = <Map<String, dynamic>>[];
      final idsVistos = <Object?>{};
      // Ciclos direcionados a colaboradores específicos têm prioridade sobre o
      // ciclo do setor; só aparecem pra quem lidera algum dos participantes.
      final ciclosPorParticipante =
          await _api.listarCiclosAbertosPorParticipantes();
      for (final setor in setores) {
        final cicloDoSetor = await _api.buscarCicloAbertoParaSetor(setor);
        if (cicloDoSetor != null) ciclo ??= cicloDoSetor;
        for (final cicloSetor in [
          ...ciclosPorParticipante,
          if (cicloDoSetor != null) cicloDoSetor,
        ]) {
          final doSetor = await _api.listarAvaliacoesEquipeGestor(
            cicloId: cicloSetor['id'] as int,
            setor: setor,
            tipoAvaliacao: cicloSetor['tipo_avaliacao'] as String?,
          );
          if (doSetor.isNotEmpty) ciclo ??= cicloSetor;
          for (final a in doSetor) {
            if (idsVistos.add(a['id'])) avaliacoes.add(a);
          }
        }
      }
      if (!mounted) return;
      if (ciclo == null) {
        setState(() {
          _ciclo = null;
          _avaliacoes = [];
          _loading = false;
        });
        return;
      }
      setState(() {
        _ciclo = ciclo;
        _avaliacoes = avaliacoes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar: $e';
        _loading = false;
      });
    }
  }

  Future<void> _abrirCicloDoSetor() async {
    final setor = _meuSetor;
    if (setor == null) return;
    final nomeCtrl = TextEditingController(text: 'Avaliação — $setor');
    String tipoAvaliacao = 'gestor';
    final criar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setStateDialog) {
        return AlertDialog(
          title: Text('Abrir ciclo para o meu setor',
              style: AppTextStyles.tituloPequeno),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nomeCtrl,
                  decoration: const InputDecoration(hintText: 'Nome do ciclo'),
                ),
                const SizedBox(height: 14),
                Text('Tipo de avaliação',
                    style: AppTextStyles.corpoMinimo
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: _tiposAvaliacao.entries.map((e) {
                    final sel = tipoAvaliacao == e.key;
                    return ChoiceChip(
                      label: Text(e.value, style: AppTextStyles.corpoMinimo),
                      selected: sel,
                      selectedColor: AppColors.laranja.withOpacity(0.15),
                      onSelected: (_) =>
                          setStateDialog(() => tipoAvaliacao = e.key),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.laranja),
              child: const Text('Abrir', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
    if (criar == true && nomeCtrl.text.trim().isNotEmpty) {
      try {
        await _api.criarCicloAvaliacao(
          nome: nomeCtrl.text.trim(),
          setor: setor,
          criadoPor: _api.colaboradorAtual?.id.toString(),
          tipoAvaliacao: tipoAvaliacao,
          // Gestor não escolhe pesos: usa o padrão do tipo.
          pesoGestor:
              tipoAvaliacao == '360' ? 50 : tipoAvaliacao == '180' ? 70 : 100,
          pesoColaborador:
              tipoAvaliacao == '360' ? 30 : tipoAvaliacao == '180' ? 30 : 0,
          pesoEquipe: tipoAvaliacao == '360' ? 20 : 0,
        );
        _carregar();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao abrir ciclo: $e'),
          backgroundColor: AppColors.erro,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _fecharCicloDoSetor() async {
    if (_ciclo == null) return;
    try {
      await _api.alterarStatusCiclo(_ciclo!['id'] as int, 'fechado');
      _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao fechar ciclo: $e'),
        backgroundColor: AppColors.erro,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Cabeçalho do ciclo efetivo com os botões de abrir/fechar o ciclo do
  /// próprio setor (porta de `_cabecalhoCiclo` do web).
  Widget _cabecalhoCiclo() {
    final ehCicloDoMeuSetor = _ciclo != null && _ciclo!['setor'] == _meuSetor;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _ciclo == null
                ? 'Nenhum ciclo aberto para o seu setor'
                : 'Ciclo: ${_ciclo!['nome']}',
            style: AppTextStyles.corpoMenor.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            _ciclo == null
                ? 'Abra um ciclo para o seu setor ou aguarde o RH abrir um ciclo geral.'
                : ehCicloDoMeuSetor
                    ? 'Ciclo aberto por você, exclusivo para o setor $_meuSetor.'
                    : 'Ciclo geral, aberto pelo RH.',
            style: AppTextStyles.corpoMinimo,
          ),
          if (_ciclo != null) _textoPrazoCiclo(),
          const SizedBox(height: 10),
          if (_ciclo == null)
            ElevatedButton.icon(
              onPressed: _abrirCicloDoSetor,
              icon: const Icon(Icons.lock_open_rounded, size: 15),
              label: Text('Abrir ciclo do meu setor',
                  style: AppTextStyles.corpoMinimo),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.laranja,
                  foregroundColor: Colors.white,
                  elevation: 0),
            )
          else if (ehCicloDoMeuSetor)
            OutlinedButton.icon(
              onPressed: _fecharCicloDoSetor,
              icon: const Icon(Icons.lock_outline_rounded, size: 15),
              label: Text('Fechar ciclo', style: AppTextStyles.corpoMinimo),
            )
          else
            OutlinedButton.icon(
              onPressed: _abrirCicloDoSetor,
              icon: const Icon(Icons.add_rounded, size: 15),
              label: Text('Abrir ciclo só do meu setor',
                  style: AppTextStyles.corpoMinimo),
            ),
        ],
      ),
    );
  }

  /// Prazo do ciclo (`data_fim`) com contagem regressiva, em destaque quando
  /// faltam poucos dias ou já venceu.
  Widget _textoPrazoCiclo() {
    final fim = DateTime.tryParse(_ciclo?['data_fim'] as String? ?? '');
    if (fim == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Prazo para avaliar: não definido pelo RH',
            style: AppTextStyles.corpoMinimo),
      );
    }
    final hoje = DateTime.now();
    final dias = DateTime(fim.year, fim.month, fim.day)
        .difference(DateTime(hoje.year, hoje.month, hoje.day))
        .inDays;
    final data =
        '${fim.day.toString().padLeft(2, '0')}/${fim.month.toString().padLeft(2, '0')}/${fim.year}';
    final String texto;
    if (dias < 0) {
      texto = 'Prazo encerrado em $data (há ${-dias} ${-dias == 1 ? 'dia' : 'dias'})';
    } else if (dias == 0) {
      texto = 'Prazo termina hoje ($data)';
    } else {
      texto = 'Prazo para avaliar: $data (faltam $dias ${dias == 1 ? 'dia' : 'dias'})';
    }
    final urgente = dias <= 7;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(texto,
          style: AppTextStyles.corpoMinimo.copyWith(
              fontWeight: urgente ? FontWeight.w600 : FontWeight.w400,
              color: urgente ? Colors.red : null)),
    );
  }

  Future<void> _abrirAvaliacao(Map<String, dynamic> avaliacao) async {
    // Avaliação concluída não pode ser refeita: só um novo ciclo libera outra.
    if (avaliacao['status'] == 'concluida') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Esta avaliação já foi concluída e não pode ser alterada.'),
      ));
      return;
    }
    final colab = avaliacao['colaboradores'] as Map?;
    final funcao = colab?['cargo'] as String? ?? '';
    final setorColab = colab?['setor'] as String?;
    final avaliacaoId = avaliacao['id'] as int;
    final perguntasJaLiberadas = avaliacao['perguntas_liberadas'] as bool? ?? false;
    var templateId = avaliacao['template_id'] as int?;

    List<Map<String, dynamic>> perguntas = [];
    if (perguntasJaLiberadas) {
      // O gestor já decidiu antes (template ou padrão) — reabre com
      // exatamente o mesmo conjunto, sem perguntar de novo.
      perguntas = await _api.perguntasDaAvaliacao(avaliacao,
          funcao: funcao, setor: setorColab);
    }
    // Sem template e sem perguntas padrão (ex.: liberada com "padrão" numa
    // função que só tem templates): deixa o gestor escolher um template.
    if (!perguntasJaLiberadas || (templateId == null && perguntas.isEmpty)) {
      // O gestor precisa escolher um template (função + setor). Fechar sem
      // escolher não avança — só depois disso o colaborador e os colegas
      // ficam liberados a responder.
      final escolha = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => AvaliacaoTemplatePickerDialog(
            setorColaborador: setorColab, funcaoColaborador: funcao),
      );
      if (!mounted || escolha == null) return;

      templateId = escolha['id'] as int;
      await _api.definirTemplateDaAvaliacao(avaliacaoId, templateId);
      perguntas = await _api.listarPerguntasDoTemplate(templateId);
    }
    if (!mounted) return;
    if (perguntas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(templateId != null
            ? 'Esse template ainda não tem perguntas cadastradas.'
            : 'Nenhuma pergunta cadastrada para a função "$funcao".'),
      ));
      return;
    }

    final respostasAtuais = await _api.listarRespostasAvaliacao(avaliacao['id'] as int);
    if (!mounted) return;
    final respostasColab = {
      for (final r in respostasAtuais.where((r) => r['origem'] == 'colaborador'))
        r['pergunta_id'] as int: r
    };
    final respostasGestor = {
      for (final r in respostasAtuais.where((r) => r['origem'] == 'gestor'))
        r['pergunta_id'] as int: r
    };

    final notas = <int, int?>{};
    final comentarioCtrls = <int, TextEditingController>{};
    for (final p in perguntas) {
      final pid = p['id'] as int;
      // Sem nota pré-selecionada: o gestor precisa escolher de propósito.
      final notaSalva = respostasGestor[pid]?['nota'] as int?;
      notas[pid] = notaSalva?.clamp(1, 5);
      comentarioCtrls[pid] =
          TextEditingController(text: respostasGestor[pid]?['comentario'] as String? ?? '');
    }

    final autoDesempenho = avaliacao['autoavaliacao_desempenho'];
    final autoPotencial = avaliacao['autoavaliacao_potencial'];
    String? erroDialog;

    final salvou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setStateDialog) {
        return AlertDialog(
          title: Text('Avaliar ${colab?['nome'] as String? ?? ''}', style: AppTextStyles.tituloPequeno),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (autoDesempenho != null || autoPotencial != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.cinzaClaro,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Autoavaliação: Desempenho ${labelNota1a5(autoDesempenho as int?)}, '
                        'Potencial ${labelNota1a5(autoPotencial as int?)}',
                        style: AppTextStyles.corpoMinimo,
                      ),
                    ),
                  ],
                  ...perguntas.map((p) {
                    final pid = p['id'] as int;
                    final dimensao = p['dimensao'] as String? ?? 'desempenho';
                    final respColab = respostasColab[pid];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(p['pergunta'] as String? ?? '',
                                    style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w600)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.laranja.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(_dimensoes[dimensao] ?? dimensao,
                                    style: AppTextStyles.corpoMinimo.copyWith(
                                        fontWeight: FontWeight.w600, color: AppColors.laranja)),
                              ),
                            ],
                          ),
                          if (respColab != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.cinzaClaro,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'Autoavaliação: ${labelNota1a5(respColab['nota'] as int?)}',
                                      style: AppTextStyles.corpoMinimo.copyWith(
                                          fontWeight: FontWeight.w600)),
                                  if ((respColab['comentario'] as String? ?? '')
                                      .isNotEmpty)
                                    Text(respColab['comentario'] as String,
                                        style: AppTextStyles.corpoMinimo),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          SeletorNota1a5(
                              valor: notas[pid],
                              onChanged: (v) => setStateDialog(() => notas[pid] = v),
                              legendaBaixa: p['legenda_nota_1'] as String?,
                              legendaAlta: p['legenda_nota_5'] as String?,
                      legendaMeio: [p['legenda_nota_2'] as String?, p['legenda_nota_3'] as String?, p['legenda_nota_4'] as String?]),
                          const SizedBox(height: 6),
                          TextField(
                            controller: comentarioCtrls[pid],
                            maxLines: 2,
                            decoration: const InputDecoration(hintText: 'Comentário (obrigatório)'),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (erroDialog != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(erroDialog!,
                          style: AppTextStyles.corpoMinimo.copyWith(color: AppColors.erro)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (perguntas.any((p) => notas[p['id'] as int] == null)) {
                  setStateDialog(() =>
                      erroDialog = 'Escolha uma nota de 1 a 5 em todas as perguntas.');
                  return;
                }
                final semComentario = perguntas
                    .any((p) => comentarioCtrls[p['id'] as int]!.text.trim().isEmpty);
                if (semComentario) {
                  setStateDialog(
                      () => erroDialog = 'Preencha o comentário de todas as perguntas.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.laranja),
              child: const Text('Salvar', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );

    if (salvou == true) {
      final col = _api.colaboradorAtual;
      if (col == null) return;
      final respostasParaSalvar = perguntas
          .map((p) => {
                'perguntaId': p['id'],
                'dimensao': p['dimensao'],
                'nota': notas[p['id'] as int],
                'comentario': comentarioCtrls[p['id'] as int]!.text.trim().isEmpty
                    ? null
                    : comentarioCtrls[p['id'] as int]!.text.trim(),
              })
          .toList();
      try {
        await _api.salvarRespostasAvaliacao(
          avaliacaoId: avaliacao['id'] as int,
          origem: 'gestor',
          respostas: respostasParaSalvar,
          avaliadorId: col.id,
          gestorId: col.id,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Avaliação salva!'),
          backgroundColor: AppColors.sucesso,
          behavior: SnackBarBehavior.floating,
        ));
        _carregar();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao salvar: $e'),
          backgroundColor: AppColors.erro,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 200,
            decoration: const BoxDecoration(gradient: AppColors.gradientePrincipal),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Avaliar Equipe',
                              style: AppTextStyles.tituloGrande.copyWith(color: Colors.white)),
                          Text('Avaliação 9-box do seu time',
                              style: AppTextStyles.corpoBranco.copyWith(color: AppColors.brancoOp80)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.laranja));
    }
    if (_erro != null) {
      return Center(child: Text(_erro!, style: AppTextStyles.corpoCinza));
    }
    if (_ciclo == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          _cabecalhoCiclo(),
          const Matriz9BoxEquipeCard(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Nenhum ciclo de avaliação ativo no momento.',
                textAlign: TextAlign.center, style: AppTextStyles.corpoCinza),
          ),
        ],
      );
    }
    if (_avaliacoes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          _cabecalhoCiclo(),
          const Matriz9BoxEquipeCard(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Nenhum colaborador no seu setor.',
                textAlign: TextAlign.center, style: AppTextStyles.corpoCinza),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _carregar,
      color: AppColors.laranja,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          _cabecalhoCiclo(),
          const Matriz9BoxEquipeCard(),
          ..._avaliacoesPorSetor().map((avaliacao) {
            final colab = avaliacao['colaboradores'] as Map?;
            final concluida = avaliacao['status'] == 'concluida';
            final card = Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.laranja.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  onTap: () => _abrirAvaliacao(avaliacao),
                  leading: FotoClicavel(url: colab?['foto_url'] as String?, nome: colab?['nome'] as String?, child: CircleAvatar(
                    backgroundColor: AppColors.laranja.withOpacity(0.12),
                    backgroundImage: (colab?['foto_url'] as String?)?.isNotEmpty == true
                        ? NetworkImage(colab!['foto_url'] as String)
                        : null,
                    child: (colab?['foto_url'] as String?)?.isNotEmpty != true
                        ? Text(
                            ((colab?['nome'] as String?)?.isNotEmpty == true)
                                ? colab!['nome'].toString()[0]
                                : '?',
                            style: const TextStyle(color: AppColors.laranja))
                        : null,
                  )),
                  title: Text(colab?['nome'] as String? ?? '',
                      style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(colab?['cargo'] as String? ?? '', style: AppTextStyles.corpoMinimo),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (concluida ? AppColors.sucesso : AppColors.laranja).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(concluida ? 'Concluída' : 'Avaliar',
                        style: AppTextStyles.corpoMinimo.copyWith(
                            fontWeight: FontWeight.w600,
                            color: concluida ? AppColors.sucesso : AppColors.laranja)),
                  ),
                ),
              ),
            );
            return _comCabecalhoSetor(avaliacao, card);
          }),
        ],
      ),
    );
  }

  String _setorDe(Map<String, dynamic> a) {
    final s = ((a['colaboradores'] as Map?)?['setor'] as String? ?? '').trim();
    return s.isEmpty ? 'Sem setor' : s;
  }

  /// Ordenada por setor (e nome) só quando o líder tem mais de um setor.
  List<Map<String, dynamic>> _avaliacoesPorSetor() {
    if (_avaliacoes.map(_setorDe).toSet().length <= 1) return _avaliacoes;
    final lista = [..._avaliacoes];
    lista.sort((a, b) {
      final s = _setorDe(a).compareTo(_setorDe(b));
      if (s != 0) return s;
      final na = ((a['colaboradores'] as Map?)?['nome'] as String? ?? '').toLowerCase();
      final nb = ((b['colaboradores'] as Map?)?['nome'] as String? ?? '').toLowerCase();
      return na.compareTo(nb);
    });
    return lista;
  }

  /// Título do setor antes do primeiro liderado de cada setor.
  Widget _comCabecalhoSetor(Map<String, dynamic> a, Widget card) {
    final lista = _avaliacoesPorSetor();
    if (identical(lista, _avaliacoes)) return card;
    final i = lista.indexOf(a);
    final setor = _setorDe(a);
    if (i > 0 && _setorDe(lista[i - 1]) == setor) return card;
    final qtd = lista.where((x) => _setorDe(x) == setor).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 10, bottom: 8),
          child: Row(children: [
            const Icon(Icons.business_outlined, size: 15, color: AppColors.cinzaTexto),
            const SizedBox(width: 6),
            Expanded(
              child: Text(setor,
                  style: AppTextStyles.corpoMedio.copyWith(fontWeight: FontWeight.w700)),
            ),
            Text('$qtd', style: AppTextStyles.corpoMinimo),
          ]),
        ),
        card,
      ],
    );
  }
}
