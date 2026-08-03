import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/home_assistant_connection.dart';
import '../../models/session_models.dart';
import '../../services/auth_service.dart';
import '../../services/home_assistant_auth_service.dart';
import '../../services/home_assistant_connection_service.dart';
import '../../services/home_assistant_discovery_service.dart';

const _orange = Color(0xFFFF7A18);
const _orangeSoft = Color(0xFFFF8A2A);
const _cream = Color(0xFFFFF7EF);
const _muted = Color(0xFFA99D93);

enum _Step { discover, servers, authorize, connecting, success }

class HomeAssistantOnboardingScreen extends StatefulWidget {
  const HomeAssistantOnboardingScreen({
    super.key,
    required this.session,
    required this.onConnected,
    required this.onSkip,
    required this.onBackToLogin,
  });

  final AppSession session;
  final VoidCallback onConnected;
  final VoidCallback onSkip;
  final VoidCallback onBackToLogin;

  @override
  State<HomeAssistantOnboardingScreen> createState() =>
      _HomeAssistantOnboardingScreenState();
}

class _HomeAssistantOnboardingScreenState
    extends State<HomeAssistantOnboardingScreen>
    with SingleTickerProviderStateMixin {
  final discovery = HomeAssistantDiscoveryService();
  final oauth = HomeAssistantAuthService();
  final storage = HomeAssistantConnectionService();
  final api = AuthService();
  late final AnimationController animation;
  _Step step = _Step.discover;
  List<HomeAssistantInstance> servers = const [];
  String? selected;
  String? error;

  @override
  void initState() {
    super.initState();
    animation = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500))
      ..repeat();
    restoreOrDiscover();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  Future<void> restoreOrDiscover() async {
    if (kIsWeb) {
      selected = await oauth.getPendingBaseUrl();
      if (Uri.base.path == '/ha-oauth-web-callback' &&
          Uri.base.queryParameters['code'] != null) {
        setState(() => step = _Step.connecting);
        await connect();
        return;
      }
    }
    await search();
  }

  Future<void> search() async {
    if (mounted) {
      setState(() {
        step = _Step.discover;
        error = null;
      });
    }
    animation.repeat();
    try {
      final result = await discovery.discoverInstances();
      if (!mounted) return;
      setState(() {
        servers = result;
        selected = result.isEmpty ? null : result.first.baseUrl;
      });
    } catch (_) {
      if (mounted) setState(() => error = 'Не удалось выполнить автопоиск');
    }
  }

  void showServers() => setState(() => step = _Step.servers);

  Future<void> manualAddress() async {
    final controller = TextEditingController(text: selected ?? 'http://');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF211711),
        title: const Text('Адрес Home Assistant'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration:
                const InputDecoration(hintText: 'http://192.168.1.10:8123')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Добавить')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || !mounted) return;
    final url = result.startsWith('http') ? result : 'http://$result';
    setState(() {
      selected = url;
      servers = [
        HomeAssistantInstance(
            name: 'Home Assistant', host: url, port: 8123, baseUrl: url),
        ...servers.where((e) => e.baseUrl != url)
      ];
    });
  }

  Future<void> connect() async {
    final url = selected;
    if (url == null) return;
    setState(() {
      step = _Step.connecting;
      error = null;
    });
    try {
      final (code, _) = await oauth.handleCallback(baseUrl: url);
      final token = await oauth.exchangeCodeForToken(baseUrl: url, code: code);
      final connection = HomeAssistantConnection(
        id: '${widget.session.id}_${DateTime.now().millisecondsSinceEpoch}',
        userId: widget.session.id,
        houseId: '',
        baseUrl: url,
        accessToken: token.accessToken,
        refreshToken: token.refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: token.expiresIn)),
        status: 'connected',
        lastCheckedAt: DateTime.now(),
      );
      await storage.saveConnection(connection);
      await api.saveHomeAssistantConnection(
          baseUrl: url,
          accessToken: token.accessToken,
          refreshToken: token.refreshToken,
          expiresAt: connection.expiresAt,
          clientId: oauth.clientId);
      await oauth.clearPendingBaseUrl();
      if (mounted) setState(() => step = _Step.success);
    } catch (exception) {
      final message = exception.toString().replaceFirst('Exception: ', '');
      if (message.toLowerCase().contains('oauth_redirect_started')) return;
      if (mounted) {
        setState(() {
          step = _Step.authorize;
          error = message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0C0907),
        body: Stack(children: [
          const Positioned(top: -140, right: -100, child: _Glow()),
          SafeArea(
              child: AnimatedSwitcher(
                  duration: Duration(
                      milliseconds:
                          MediaQuery.disableAnimationsOf(context) ? 1 : 300),
                  switchInCurve: Curves.easeOutCubic,
                  child: switch (step) {
                    _Step.discover => discoverView(),
                    _Step.servers => serversView(),
                    _Step.authorize => authorizeView(),
                    _Step.connecting => connectingView(),
                    _Step.success => successView(),
                  })),
        ]),
      );

  Widget topBar({VoidCallback? back}) => Row(children: [
        if (back != null)
          _SquareButton(icon: Icons.arrow_back_ios_new_rounded, onTap: back),
        const Spacer(),
        TextButton(
            onPressed: widget.onSkip,
            child: const Text('Пропустить', style: TextStyle(color: _muted))),
      ]);

  Widget discoverView() => Padding(
        key: const ValueKey('discover'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(children: [
          topBar(back: widget.onBackToLogin),
          const SizedBox(height: 15),
          const Text('ПОДКЛЮЧЕНИЕ', style: _kicker),
          const SizedBox(height: 9),
          const Text('Найдём ваш\nумный дом',
              textAlign: TextAlign.center, style: _title),
          const SizedBox(height: 13),
          const Text('Smart House ищет Home Assistant\nв локальной сети.',
              textAlign: TextAlign.center, style: _body),
          const Spacer(),
          AnimatedBuilder(
              animation: animation,
              builder: (_, __) => SizedBox(
                  width: 270,
                  height: 270,
                  child: CustomPaint(
                      painter: _RadarPainter(animation.value, servers.length),
                      child: const Center(child: _HomeMark())))),
          const Spacer(),
          Text(error ?? 'Поиск устройств…',
              style: TextStyle(
                  color: error == null ? _muted : const Color(0xFFFF8B8B),
                  fontSize: 12)),
          const SizedBox(height: 14),
          _SecondaryButton(
              label: servers.isEmpty
                  ? 'Указать адрес вручную'
                  : 'Показать найденные',
              onTap: servers.isEmpty ? manualAddress : showServers),
        ]),
      );

  Widget serversView() => Padding(
        key: const ValueKey('servers'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          topBar(back: () => setState(() => step = _Step.discover)),
          const SizedBox(height: 18),
          const Text('HOME ASSISTANT', style: _kicker),
          const SizedBox(height: 9),
          const Text('Выберите\nсервер', style: _title),
          const SizedBox(height: 13),
          Text(
              servers.isEmpty
                  ? 'Добавьте адрес сервера вручную.'
                  : 'Найдено ${servers.length} устройств в вашей сети.',
              style: _body),
          const SizedBox(height: 25),
          Expanded(
              child: ListView(children: [
            ...servers.map((server) => Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: _ServerCard(
                    server: server,
                    selected: selected == server.baseUrl,
                    onTap: () => setState(() => selected = server.baseUrl)))),
            _SecondaryButton(
                label: 'Добавить адрес вручную', onTap: manualAddress),
          ])),
          _PrimaryButton(
              label: 'Подключиться',
              onTap: selected == null
                  ? null
                  : () => setState(() => step = _Step.authorize)),
        ]),
      );

  Widget authorizeView() => Padding(
        key: const ValueKey('authorize'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(children: [
          topBar(back: () => setState(() => step = _Step.servers)),
          const SizedBox(height: 18),
          const Text('АВТОРИЗАЦИЯ', style: _kicker),
          const SizedBox(height: 9),
          const Text('Подключение к\nHome Assistant',
              textAlign: TextAlign.center, style: _title),
          const SizedBox(height: 13),
          const Text(
              'Вы будете перенаправлены на защищённую\nстраницу авторизации.',
              textAlign: TextAlign.center,
              style: _body),
          const Spacer(),
          const _HaMark(),
          const Spacer(),
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFFFF8B8B), fontSize: 12))),
          const _ConnectionSteps(active: 1),
          const SizedBox(height: 25),
          _PrimaryButton(label: 'Продолжить', onTap: connect),
        ]),
      );

  Widget connectingView() => Center(
      key: const ValueKey('connecting'),
      child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            RotationTransition(turns: animation, child: const _Ring()),
            const SizedBox(height: 35),
            const Text('SMART HOUSE', style: _kicker),
            const SizedBox(height: 10),
            const Text('Подключаем\nваш дом',
                textAlign: TextAlign.center, style: _title),
            const SizedBox(height: 15),
            const Text('Проверяем права доступа…', style: _body)
          ])));

  Widget successView() => Padding(
      key: const ValueKey('success'),
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 35),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Spacer(),
        const _SuccessMark(),
        const SizedBox(height: 30),
        const Text('Готово!', style: _title),
        const SizedBox(height: 15),
        const Text(
            'Ваш дом успешно подключён.\nТеперь можно управлять всеми устройствами.',
            textAlign: TextAlign.center,
            style: _body),
        const Spacer(),
        _PrimaryButton(label: 'Перейти к дому', onTap: widget.onConnected)
      ]));
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter(this.value, this.points);
  final double value;
  final int points;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _orangeSoft.withValues(alpha: .16);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(c, size.width * i / 7, ring);
    }
    final a = value * math.pi * 2;
    final beam = Paint()
      ..strokeWidth = 2
      ..color = _orangeSoft.withValues(alpha: .38);
    canvas.drawLine(
        c, c + Offset(math.cos(a), math.sin(a)) * size.width * .46, beam);
    final dot = Paint()..color = _orangeSoft;
    final count = math.max(points, 3);
    for (var i = 0; i < count; i++) {
      final da = i * 2.15 + .7;
      canvas.drawCircle(
          c +
              Offset(math.cos(da), math.sin(da)) *
                  size.width *
                  (.22 + i % 2 * .12),
          5,
          dot);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.value != value || old.points != points;
}

class _HomeMark extends StatelessWidget {
  const _HomeMark();
  @override
  Widget build(BuildContext context) => Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_orangeSoft, _orange]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: _orange.withValues(alpha: .35), blurRadius: 36)
          ]),
      child:
          const Icon(Icons.home_rounded, color: Color(0xFF351405), size: 38));
}

class _HaMark extends StatelessWidget {
  const _HaMark();
  @override
  Widget build(BuildContext context) => Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF42A5F5), Color(0xFF1469B1)]),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF1469B1).withValues(alpha: .3),
                blurRadius: 45)
          ]),
      child: const Icon(Icons.home_rounded, color: Colors.white, size: 58));
}

class _Ring extends StatelessWidget {
  const _Ring();
  @override
  Widget build(BuildContext context) => Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _orange, width: 3),
          boxShadow: [
            BoxShadow(color: _orange.withValues(alpha: .2), blurRadius: 35)
          ]),
      child: const Icon(Icons.home_rounded, color: _orangeSoft, size: 38));
}

class _SuccessMark extends StatelessWidget {
  const _SuccessMark();
  @override
  Widget build(BuildContext context) => Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_orangeSoft, _orange]),
          borderRadius: BorderRadius.circular(38),
          boxShadow: [
            BoxShadow(color: _orange.withValues(alpha: .34), blurRadius: 50)
          ]),
      child:
          const Icon(Icons.check_rounded, color: Color(0xFF321505), size: 58));
}

class _ServerCard extends StatelessWidget {
  const _ServerCard(
      {required this.server, required this.selected, required this.onTap});
  final HomeAssistantInstance server;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Glass(
      highlighted: selected,
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: _orange.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.wifi_rounded, color: _orangeSoft)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Home Assistant',
                      style: TextStyle(
                          color: _cream,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  const SizedBox(height: 5),
                  Text(server.baseUrl,
                      style: const TextStyle(color: _muted, fontSize: 10))
                ])),
            AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: selected
                    ? const Icon(Icons.check_circle_rounded,
                        key: ValueKey(1), color: _orangeSoft)
                    : const SizedBox(key: ValueKey(0), width: 24))
          ])));
}

class _ConnectionSteps extends StatelessWidget {
  const _ConnectionSteps({required this.active});
  final int active;
  @override
  Widget build(BuildContext context) => Column(children: [
        _step(0, 'Сервер найден'),
        _step(1, 'Авторизация'),
        _step(2, 'Завершение')
      ]);
  Widget _step(int i, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: i < active
                    ? const Color(0xFF66D99A).withValues(alpha: .14)
                    : i == active
                        ? _orange.withValues(alpha: .15)
                        : Colors.white.withValues(alpha: .04),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                    color: i == active
                        ? _orangeSoft.withValues(alpha: .34)
                        : Colors.white12)),
            alignment: Alignment.center,
            child: i < active
                ? const Icon(Icons.check_rounded,
                    color: Color(0xFF66D99A), size: 17)
                : Text('${i + 1}',
                    style:
                        TextStyle(color: i == active ? _orangeSoft : _muted))),
        const SizedBox(width: 12),
        Text(label,
            style:
                TextStyle(color: i == active ? _cream : _muted, fontSize: 12))
      ]));
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: const Color(0xFF321507),
              disabledBackgroundColor: Colors.white10,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18))),
          child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w700))));
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
              foregroundColor: _cream,
              side: const BorderSide(color: Colors.white12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18))),
          child: Text(label)));
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Glass(
      onTap: onTap,
      child: SizedBox(
          width: 40, height: 40, child: Icon(icon, color: _cream, size: 18)));
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.onTap, this.highlighted = false});
  final Widget child;
  final VoidCallback? onTap;
  final bool highlighted;
  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    highlighted
                        ? _orange.withValues(alpha: .14)
                        : Colors.white.withValues(alpha: .08),
                    Colors.white.withValues(alpha: .03)
                  ]),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                      color: highlighted
                          ? _orangeSoft.withValues(alpha: .4)
                          : Colors.white12)),
              child: child)));
}

class _Glow extends StatelessWidget {
  const _Glow();
  @override
  Widget build(BuildContext context) => Container(
      width: 340,
      height: 340,
      decoration: BoxDecoration(
          gradient: RadialGradient(colors: [
            _orange.withValues(alpha: .2),
            _orange.withValues(alpha: 0),
          ]),
          shape: BoxShape.circle));
}

const _kicker = TextStyle(
    color: _orangeSoft,
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.8);
const _title = TextStyle(
    color: _cream,
    fontSize: 34,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2);
const _body = TextStyle(color: _muted, fontSize: 14, height: 1.55);
