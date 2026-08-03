class HomeAssistantConnection {
  const HomeAssistantConnection({
    required this.id,
    required this.userId,
    required this.houseId,
    required this.baseUrl,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.status,
    required this.lastCheckedAt,
  });

  final String id;
  final String userId;
  final String houseId;
  final String baseUrl;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String status;
  final DateTime? lastCheckedAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'houseId': houseId,
      'baseUrl': baseUrl,
      'expiresAt': expiresAt.toIso8601String(),
      'status': status,
      'lastCheckedAt': lastCheckedAt?.toIso8601String(),
    };
  }

  factory HomeAssistantConnection.fromJson(
    Map<String, dynamic> json, {
    required String accessToken,
    required String refreshToken,
  }) {
    return HomeAssistantConnection(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      houseId: (json['houseId'] ?? '').toString(),
      baseUrl: (json['baseUrl'] ?? '').toString(),
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.tryParse((json['expiresAt'] ?? '').toString()) ??
          DateTime.now().add(const Duration(minutes: 5)),
      status: (json['status'] ?? 'connected').toString(),
      lastCheckedAt:
          DateTime.tryParse((json['lastCheckedAt'] ?? '').toString()),
    );
  }
}

class HomeAssistantInstance {
  const HomeAssistantInstance({
    required this.name,
    required this.host,
    required this.port,
    required this.baseUrl,
  });

  final String name;
  final String host;
  final int port;
  final String baseUrl;
}

class HomeAssistantTokenPayload {
  const HomeAssistantTokenPayload({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
}
