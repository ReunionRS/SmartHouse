class AppSession {
  const AppSession({
    required this.id,
    required this.token,
    required this.email,
    required this.fio,
    required this.avatarUrl,
  });

  final String id;
  final String token;
  final String email;
  final String fio;
  final String avatarUrl;
}

class UnauthorizedException implements Exception {
  const UnauthorizedException();
}

class ClientOption {
  const ClientOption({
    required this.id,
    required this.fio,
    required this.email,
  });

  final String id;
  final String fio;
  final String email;
}
