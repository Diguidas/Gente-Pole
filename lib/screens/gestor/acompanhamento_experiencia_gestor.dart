import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';

const _borda = Color(0xFFE2E8F0);

// ── Filtros compartilhados pelas duas telas (9Box e Acompanhamento) ────────

DateTime? _admissao(Map<String, dynamic> a) =>
    DateTime.tryParse('${a['data_admissao'] ?? ''}');

/// Mês (AAAA-MM) em que a pessoa completa/completou 45 dias de casa — o mesmo
/// "45 dias concluídos em" do painel do RH.
String? mesMarco45(Map<String, dynamic> a) {
  final d = _admissao(a);
  if (d == null) return null;
  final f = d.add(const Duration(days: 45));
  return '${f.year}-${f.month.toString().padLeft(2, '0')}';
}

String rotuloMesExperiencia(String m) {
  const nomes = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho',
    'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
  ];
  final p = m.split('-');
  return '${nomes[int.parse(p[1]) - 1]}/${p[0]}';
}

/// Mês, setor e líder escolhidos. Itens no formato do acompanhamento
/// (`data_admissao`, `setor`, `lideres`).
class FiltroExperiencia {
  String? mes;
  String? setor;
  int? lider;

  bool aplica(Map<String, dynamic> a, {bool comMes = true}) {
    if (comMes && mes != null && mesMarco45(a) != mes) return false;
    if (setor != null && a['setor'] != setor) return false;
    if (lider != null &&
        !((a['lideres'] as List?) ?? const []).any((l) => l['id'] == lider)) {
      return false;
    }
    return true;
  }
}

/// Barra com os filtros de mês, setor e líder. Setor e líder só aparecem
/// quando há mais de um; o líder lista você e quem está abaixo de você (um líder
/// acima de você não faz parte do que você acompanha).
class BarraFiltrosExperiencia extends StatelessWidget {
  final List<Map<String, dynamic>> itens;
  final int meuId;
  final FiltroExperiencia filtro;
  final VoidCallback onMudou;

  const BarraFiltrosExperiencia({
    super.key,
    required this.itens,
    required this.meuId,
    required this.filtro,
    required this.onMudou,
  });

  @override
  Widget build(BuildContext context) {
    final meses = ({
      for (final a in itens.where((a) => filtro.aplica(a, comMes: false)))
        mesMarco45(a)
    }.whereType<String>().toSet()
      ..add(filtro.mes ?? ''))
        .toList()
      ..remove('');
    meses.sort();

    final setores = ({
      for (final a in itens)
        if ('${a['setor'] ?? ''}'.isNotEmpty) '${a['setor']}'
    }.toList()
      ..sort());

    final timeIds = {meuId, for (final a in itens) a['id'] as int};
    final lideresMap = <int, String>{};
    for (final a in itens) {
      for (final l in ((a['lideres'] as List?) ?? const [])) {
        final id = l['id'] as int;
        if (timeIds.contains(id)) lideresMap[id] = '${l['nome']}';
      }
    }
    final lideres = lideresMap.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _dropdown<String?>(
          rotulo: '45 dias concluídos em',
          valor: filtro.mes,
          itens: [
            const DropdownMenuItem(value: null, child: Text('Todos os meses')),
            for (final m in meses)
              DropdownMenuItem(value: m, child: Text(rotuloMesExperiencia(m))),
          ],
          onChanged: (v) {
            filtro.mes = v;
            onMudou();
          },
        ),
        if (setores.length > 1)
          _dropdown<String?>(
            rotulo: 'Setor',
            valor: filtro.setor,
            itens: [
              const DropdownMenuItem(value: null, child: Text('Todos os setores')),
              for (final s in setores)
                DropdownMenuItem(
                    value: s,
                    child: SizedBox(
                        width: 220,
                        child: Text(s, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) {
              filtro.setor = v;
              onMudou();
            },
          ),
        if (lideres.length > 1)
          _dropdown<int?>(
            rotulo: 'Líder',
            valor: filtro.lider,
            itens: [
              const DropdownMenuItem(value: null, child: Text('Todos os líderes')),
              for (final l in lideres)
                DropdownMenuItem(
                    value: l.key,
                    child: SizedBox(
                        width: 220,
                        child: Text(l.key == meuId ? '${l.value} (você)' : l.value,
                            overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) {
              filtro.lider = v;
              onMudou();
            },
          ),
      ],
    );
  }

  Widget _dropdown<T>({
    required String rotulo,
    required T valor,
    required List<DropdownMenuItem<T>> itens,
    required ValueChanged<T?> onChanged,
  }) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$rotulo:',
            style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.cinzaTexto)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _borda),
          ),
          child: DropdownButton<T>(
            value: valor,
            underline: const SizedBox(),
            style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.dark),
            items: itens,
            onChanged: onChanged,
          ),
        ),
      ]);
}

// ── Tela de acompanhamento ─────────────────────────────────────────────────

/// Acompanhamento do período de experiência em toda a hierarquia do gestor:
/// quem falta responder, o setor e as lideranças (todas, se houver mais de
/// uma), e quem é o líder que avalia. Os dados e os filtros vêm da tela
/// principal; aqui ficam só as abas Pendentes/Concluídas, a busca e a lista.
class AcompanhamentoExperienciaGestor extends StatefulWidget {
  final List<Map<String, dynamic>> itens;
  final int meuId;
  final FiltroExperiencia filtro;

  const AcompanhamentoExperienciaGestor({
    super.key,
    required this.itens,
    required this.meuId,
    required this.filtro,
  });

  @override
  State<AcompanhamentoExperienciaGestor> createState() =>
      _AcompanhamentoExperienciaGestorState();
}

class _AcompanhamentoExperienciaGestorState
    extends State<AcompanhamentoExperienciaGestor> {
  bool _verConcluidas = false;
  // 0 = todos, 1 = colaborador não respondeu, 2 = colaborador respondeu
  int _quemFez = 0;
  String _busca = '';

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  bool _concluida(Map<String, dynamic> a) => a['status'] == 'concluida';

  @override
  Widget build(BuildContext context) {
    final filtrados = widget.itens.where((a) => widget.filtro.aplica(a)).toList();
    final pendentes = filtrados.where((a) => !_concluida(a)).length;
    final concluidas = filtrados.length - pendentes;

    final busca = _busca.trim().toLowerCase();
    final lista = filtrados.where((a) {
      if (_concluida(a) != _verConcluidas) return false;
      if (busca.isNotEmpty && !'${a['nome'] ?? ''}'.toLowerCase().contains(busca)) {
        return false;
      }
      if (!_verConcluidas && _quemFez != 0) {
        final resp = a['colab_respondeu'] == true;
        if (_quemFez == 1 && resp) return false;
        if (_quemFez == 2 && !resp) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) =>
          (_adm(a) ?? DateTime(2100)).compareTo(_adm(b) ?? DateTime(2100)));

    final semIniciar = lista.where((a) => a['status'] == 'nao_iniciada').length;
    final emAndamento = lista.where((a) => a['status'] == 'andamento').length;
    final colabFalta = lista.where((a) => a['colab_respondeu'] != true).length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Acompanhamento da experiência',
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.dark)),
          Text('Toda a hierarquia abaixo de você: quem falta responder, setor, liderança e quem avalia',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: Text('Pendentes ($pendentes)'),
              selected: !_verConcluidas,
              onSelected: (_) => setState(() => _verConcluidas = false),
            ),
            ChoiceChip(
              label: Text('Concluídas ($concluidas)'),
              selected: _verConcluidas,
              onSelected: (_) => setState(() => _verConcluidas = true),
            ),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: 260,
            child: TextField(
              onChanged: (v) => setState(() => _busca = v),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Buscar por nome',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (!_verConcluidas) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: const Text('Todos'),
                  selected: _quemFez == 0,
                  onSelected: (_) => setState(() => _quemFez = 0)),
              ChoiceChip(
                  label: const Text('Colaborador não respondeu'),
                  selected: _quemFez == 1,
                  onSelected: (_) => setState(() => _quemFez = 1)),
              ChoiceChip(
                  label: const Text('Colaborador já respondeu'),
                  selected: _quemFez == 2,
                  onSelected: (_) => setState(() => _quemFez = 2)),
            ]),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 8, children: [
            _resumo('Na lista', '${lista.length}', AppColors.dark),
            if (!_verConcluidas) ...[
              _resumo('Líder não iniciou', '$semIniciar', AppColors.cinzaTexto),
              _resumo('Líder avaliando', '$emAndamento', const Color(0xFFD97706)),
            ],
            _resumo('Colaborador sem pesquisa', '$colabFalta', AppColors.erro),
          ]),
          const SizedBox(height: 12),
          if (lista.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Ninguém nesta seleção.',
                  style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.cinzaTexto)),
            )
          else
            for (final a in lista) _linha(a),
        ],
      ),
    );
  }

  DateTime? _adm(Map<String, dynamic> a) => _admissao(a);

  Widget _resumo(String rotulo, String valor, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(valor,
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w700, color: cor)),
          Text(rotulo,
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.cinzaTexto)),
        ]),
      );

  Widget _chip(String t, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(t,
            style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w600, color: cor)),
      );

  Widget _linha(Map<String, dynamic> a) {
    final adm = _adm(a);
    final dias = adm == null ? null : DateTime.now().difference(adm).inDays;
    final marco = adm?.add(const Duration(days: 45));
    final lideres = [for (final l in (a['lideres'] as List)) '${l['nome']}'];
    final direto = a['lider_direto'] as Map?;
    final status = a['status'] as String;
    final corLider = status == 'concluida'
        ? AppColors.sucesso
        : status == 'andamento'
            ? const Color(0xFFD97706)
            : AppColors.cinzaTexto;
    final txtLider = status == 'concluida'
        ? 'Líder concluiu'
        : status == 'andamento'
            ? 'Líder avaliando'
            : 'Líder não iniciou';
    final colabOk = a['colab_respondeu'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borda),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${a['nome'] ?? '—'}',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
          if (dias != null)
            Text('$dias dias de casa',
                style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.cinzaTexto)),
        ]),
        Text(
            [
              if ('${a['cargo'] ?? ''}'.isNotEmpty) '${a['cargo']}',
              if ('${a['setor'] ?? ''}'.isNotEmpty) '${a['setor']}',
            ].join(' · '),
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.cinzaTexto)),
        if (marco != null)
          Text('45 dias em ${_fmt(marco)}',
              style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.cinzaTexto)),
        const SizedBox(height: 4),
        Text.rich(TextSpan(
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.dark),
            children: [
              const TextSpan(text: 'Quem avalia: '),
              TextSpan(
                  text: direto == null
                      ? 'sem líder definido'
                      : '${direto['nome']} (${'${direto['nivel']}'.replaceAll('_', ' ')})'
                          '${direto['id'] == widget.meuId ? ' · você' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ])),
        Text(
            lideres.isEmpty
                ? 'Sem liderança cadastrada'
                : '${lideres.length > 1 ? 'Lideranças' : 'Liderança'}: ${lideres.join(', ')}',
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.dark)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _chip(txtLider, corLider),
          _chip(colabOk ? 'Colaborador respondeu' : 'Colaborador não respondeu',
              colabOk ? AppColors.sucesso : AppColors.erro),
        ]),
      ]),
    );
  }
}
