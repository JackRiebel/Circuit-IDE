class CostInfo {
  final double totalCost;
  final double sessionCost;

  const CostInfo({this.totalCost = 0.0, this.sessionCost = 0.0});

  CostInfo add(double cost) {
    return CostInfo(
      totalCost: totalCost + cost,
      sessionCost: sessionCost + cost,
    );
  }

  String get formatted {
    if (sessionCost < 0.01) {
      return '<\$0.01';
    }
    return '\$${sessionCost.toStringAsFixed(2)}';
  }
}
