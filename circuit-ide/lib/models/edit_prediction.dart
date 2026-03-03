class EditPrediction {
  final String filePath;
  final int line;
  final String description;
  final double confidence;
  final String reasoning;
  final DateTime createdAt;

  const EditPrediction({
    required this.filePath,
    required this.line,
    required this.description,
    required this.confidence,
    required this.reasoning,
    required this.createdAt,
  });
}
