class SceneExecutionReport {
  const SceneExecutionReport({required this.status, required this.results});
  final String status;
  final List<SceneExecutionItem> results;

  factory SceneExecutionReport.fromJson(Map<String, dynamic> json) => SceneExecutionReport(
        status: (json['status'] ?? 'failed').toString(),
        results: (json['results'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SceneExecutionItem.fromJson)
            .toList(growable: false),
      );
}

class SceneExecutionItem {
  const SceneExecutionItem({required this.name, required this.status, required this.reason});
  final String name;
  final String status;
  final String reason;

  factory SceneExecutionItem.fromJson(Map<String, dynamic> json) => SceneExecutionItem(
        name: (json['name'] ?? json['entityId'] ?? 'Устройство').toString(),
        status: (json['status'] ?? '').toString(),
        reason: (json['reason'] ?? '').toString(),
      );
}
