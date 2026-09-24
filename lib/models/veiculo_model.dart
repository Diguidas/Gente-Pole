const tiposVeiculo = {
  'carro': 'Carro',
  'moto': 'Moto',
  'outro': 'Outro',
};

/// Veículo do colaborador — mesma tabela `veiculos` usada pela Portaria no
/// painel web (o RH/portaria vê todos; aqui o colaborador só vê os seus).
class VeiculoModel {
  final int id;
  final String placa;
  final String tipo; // 'carro' | 'moto' | 'outro'
  final String? tipoOutro;
  final String? modelo;
  final String? cor;
  final int colaboradorId;

  VeiculoModel({
    required this.id,
    required this.placa,
    this.tipo = 'carro',
    this.tipoOutro,
    this.modelo,
    this.cor,
    required this.colaboradorId,
  });

  String get tipoLabel => tipo == 'outro'
      ? (tipoOutro?.isNotEmpty == true ? tipoOutro! : 'Outro')
      : (tiposVeiculo[tipo] ?? tipo);

  factory VeiculoModel.fromJson(Map<String, dynamic> json) {
    return VeiculoModel(
      id: json['id'] as int,
      placa: json['placa'] as String,
      tipo: json['tipo'] as String? ?? 'carro',
      tipoOutro: json['tipo_outro'] as String?,
      modelo: json['modelo'] as String?,
      cor: json['cor'] as String?,
      colaboradorId: json['colaborador_id'] as int,
    );
  }
}
