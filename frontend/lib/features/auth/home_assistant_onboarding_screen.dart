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
  _Step renderedStep = _Step.discover;
  int slideDirection = 1;
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
      // handle web OAuth callback
      if (Uri.base.path == '/ha-oauth-web-callback' &&
          Uri.base.queryParameters['code'] != null) {
        setState(() => step = _Step.connecting);
        await connect();
        return;
      }
      // handle one-time login deep link for web
      if (Uri.base.path == '/one-time-login' &&
          Uri.base.queryParameters['token'] != null) {
        setState(() => step = _Step.connecting);
        try {
          await api.oneTimeLogin(Uri.base.queryParameters['token']!);
          if (!mounted) return;
          widget.onConnected();
          return;
        } catch (e) {
          // fall through to prepare web UI with error
          if (!mounted) return;
          setState(() => error = e.toString());
        }
      }
      await _prepareWeb();
      return;
    }
    await search();
  }

  Future<void> _prepareWeb() async {
    if (!mounted) return;
    setState(() {
      step = _Step.servers;
      error = 'Автопоиск Home Assistant недоступен в браузере';
      servers = const [];
      selected = null;
    });
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
        if (result.isNotEmpty) step = _Step.servers;
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Не удалось выполнить автопоиск');
      }
    }
  }

  void showServers() => setState(() => step = _Step.servers);

  Future<void> manualAddress() async {
    final controller = TextEditingController(text: selected ?? 'http://');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
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
      final hub = await oauth.detectSmartHouseHub(url);
      late final HomeAssistantTokenPayload token;
      late final String connectionClientId;

      if (hub != null) {
        final (hubId, pairingProof) = hub;
        final (pairingToken, _) = await api.createHomeAssistantPairingSession(
          hubId: hubId,
          pairingProof: pairingProof,
        );
        token = await oauth.exchangePairingToken(
          baseUrl: url,
          pairingToken: pairingToken,
        );
        connectionClientId = oauth.pairingClientIdFor(url);
      } else {
        connectionClientId = oauth.clientId;
        final (code, _) = await oauth.handleCallback(baseUrl: url);
        token = await oauth.exchangeCodeForToken(baseUrl: url, code: code);
      }
      final connection = HomeAssistantConnection(
        id: '${widget.session.id}_${DateTime.now().millisecondsSinceEpoch}',
        userId: widget.session.id,
        houseId: '',
        baseUrl: url,
        clientId: connectionClientId,
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
          clientId: connectionClientId);
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
  Widget build(BuildContext context) {
    if (step != renderedStep) {
      slideDirection = step.index > renderedStep.index ? 1 : -1;
      renderedStep = step;
    }
    final currentChild = switch (step) {
      _Step.discover => discoverView(),
      _Step.servers => serversView(),
      _Step.authorize => authorizeView(),
      _Step.connecting => connectingView(),
      _Step.success => successView(),
    };
    final currentKey = currentChild.key;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(children: [
        const Positioned(top: -140, right: -100, child: _Glow()),
        SafeArea(
            child: ClipRect(
          child: AnimatedSwitcher(
              duration: Duration(
                  milliseconds:
                      MediaQuery.disableAnimationsOf(context) ? 1 : 360),
              switchInCurve: Curves.easeInOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              transitionBuilder: (child, animation) {
                final isIncoming = child.key == currentKey;
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(
                      isIncoming
                          ? slideDirection.toDouble()
                          : -slideDirection.toDouble(),
                      0,
                    ),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                );
              },
              child: currentChild),
        )),
      ]),
    );
  }

  Widget topBar({VoidCallback? back}) => Row(children: [
        if (back != null)
          _SquareButton(icon: Icons.arrow_back_ios_new_rounded, onTap: back),
        const Spacer(),
        TextButton(
            onPressed: widget.onSkip,
            child: Text('Пропустить',
                style: TextStyle(color: _secondaryText(context)))),
      ]);

  Widget discoverView() => Padding(
        key: const ValueKey('discover'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(children: [
          topBar(back: widget.onBackToLogin),
          const SizedBox(height: 15),
          const Text('ПОДКЛЮЧЕНИЕ', style: _kicker),
          const SizedBox(height: 9),
          Text('Найдём ваш\nумный дом',
              textAlign: TextAlign.center, style: _titleStyle(context)),
          const SizedBox(height: 13),
          Text('Smart House ищет Home Assistant\nв локальной сети.',
              textAlign: TextAlign.center, style: _bodyStyle(context)),
          const Spacer(),
          AnimatedBuilder(
              animation: animation,
              builder: (_, __) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return RepaintBoundary(
                  child: SizedBox(
                    width: 292,
                    height: 292,
                    child: CustomPaint(
                      painter: _RadarPainter(
                        animation.value,
                        servers.length,
                        isDark: isDark,
                      ),
                      child: const Center(child: _AppLogoMark()),
                    ),
                  ),
                );
              }),
          const Spacer(),
          Text(error ?? 'Поиск устройств…',
              style: TextStyle(
                  color: error == null
                      ? _secondaryText(context)
                      : const Color(0xFFD83B52),
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
          Text('Выберите\nсервер', style: _titleStyle(context)),
          const SizedBox(height: 13),
          Text(
              servers.isEmpty
                  ? 'Добавьте адрес сервера вручную.'
                  : 'Найдено ${servers.length} устройств в вашей сети.',
              style: _bodyStyle(context)),
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
          Text('Подключение к\nSmart House Hub',
              textAlign: TextAlign.center, style: _titleStyle(context)),
          const SizedBox(height: 13),
          Text(
              'Аккаунт Smart House будет безопасно связан\nс локальным хабом. Второй вход не потребуется.',
              textAlign: TextAlign.center,
              style: _bodyStyle(context)),
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
          const SizedBox(height: 16),
          Text(
            'После нажатия «Продолжить» откроется браузер для входа в Home Assistant. После успешного завершения вы вернётесь в приложение.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _secondaryText(context), fontSize: 14),
          ),
          const SizedBox(height: 24),
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
            Text('Подключаем\nваш дом',
                textAlign: TextAlign.center, style: _titleStyle(context)),
            const SizedBox(height: 15),
            Text('Проверяем права доступа…', style: _bodyStyle(context))
          ])));

  Widget successView() => Padding(
      key: const ValueKey('success'),
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 35),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Spacer(),
        const _SuccessMark(),
        const SizedBox(height: 30),
        Text('Готово!', style: _titleStyle(context)),
        const SizedBox(height: 15),
        Text(
            'Ваш дом успешно подключён.\nТеперь можно управлять всеми устройствами.',
            textAlign: TextAlign.center,
            style: _bodyStyle(context)),
        const Spacer(),
        _PrimaryButton(label: 'Перейти к дому', onTap: widget.onConnected)
      ]));
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter(this.value, this.points, {required this.isDark});
  final double value;
  final int points;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .46;
    final radarRect = Rect.fromCircle(center: center, radius: radius);

    final background = Paint()
      ..shader = RadialGradient(
        colors: isDark
            ? const [Color(0x293E2518), Color(0x12150E0A), Colors.transparent]
            : const [Color(0xFFFFF7F0), Color(0x70FFE9D8), Colors.transparent],
        stops: const [0, .68, 1],
      ).createShader(radarRect);
    canvas.drawCircle(center, radius, background);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isDark ? 1.2 : 1.35;
    for (var i = 1; i <= 3; i++) {
      ring.color =
          _orange.withOpacity(isDark ? .22 - i * .025 : .30 - i * .035);
      canvas.drawCircle(center, radius * i / 3, ring);
    }

    final pulse = (value * 3) % 1;
    canvas.drawCircle(
      center,
      radius * (.34 + pulse * .66),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 - pulse
        ..color = _orange.withOpacity((1 - pulse) * (isDark ? .28 : .38)),
    );

    final angle = value * math.pi * 2 - math.pi / 2;
    final sweep = Paint()
      ..style = PaintingStyle.fill
      ..shader = SweepGradient(
        startAngle: angle - .72,
        endAngle: angle,
        colors: [Colors.transparent, _orange.withOpacity(isDark ? .24 : .31)],
      ).createShader(radarRect);
    canvas.drawArc(radarRect, angle - .72, .72, true, sweep);

    final beamEnd = center + Offset(math.cos(angle), math.sin(angle)) * radius;
    canvas.drawLine(
      center,
      beamEnd,
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = _orange.withOpacity(isDark ? .72 : .82),
    );
    canvas.drawCircle(
      beamEnd,
      3.5,
      Paint()..color = _orange,
    );

    final count = points.clamp(0, 8);
    for (var i = 0; i < count; i++) {
      final pointAngle = i * 2.15 + .7;
      final pointCenter = center +
          Offset(math.cos(pointAngle), math.sin(pointAngle)) *
              radius *
              (.48 + i % 2 * .22);
      canvas.drawCircle(
          pointCenter, 11, Paint()..color = _orange.withOpacity(.13));
      canvas.drawCircle(
          pointCenter,
          5.5,
          Paint()
            ..color = _orange
            ..style = PaintingStyle.fill);
      canvas.drawCircle(
          pointCenter,
          7.5,
          Paint()
            ..color = isDark ? const Color(0xFF17120F) : Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.value != value || old.points != points || old.isDark != isDark;
}

class _AppLogoMark extends StatelessWidget {
  const _AppLogoMark();
  @override
  Widget build(BuildContext context) => Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(.92),
          border: Border.all(color: _orange.withOpacity(.72), width: 2),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
                color: _orange.withOpacity(.25),
                blurRadius: 32,
                spreadRadius: 7),
            BoxShadow(
                color: Colors.black.withOpacity(.08),
                blurRadius: 18,
                offset: const Offset(0, 8)),
          ]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Transform.scale(
          scale: 1.65,
          child: Image.asset('Logo.png', fit: BoxFit.contain),
        ),
      ));
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
                color: const Color(0xFF1469B1).withOpacity(.3), blurRadius: 45)
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
            BoxShadow(color: _orange.withOpacity(.2), blurRadius: 35)
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
            BoxShadow(color: _orange.withOpacity(.34), blurRadius: 50)
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
                    color: _orange.withOpacity(.13),
                    borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.wifi_rounded, color: _orangeSoft)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Home Assistant',
                      style: TextStyle(
                          color: _primaryText(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  const SizedBox(height: 5),
                  Text(server.baseUrl,
                      style: TextStyle(
                          color: _secondaryText(context), fontSize: 10))
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
        _step(context, 0, 'Сервер найден'),
        _step(context, 1, 'Авторизация'),
        _step(context, 2, 'Завершение')
      ]);
  Widget _step(BuildContext context, int i, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: i < active
                    ? const Color(0xFF66D99A).withOpacity(.14)
                    : i == active
                        ? _orange.withOpacity(.15)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                    color: i == active
                        ? _orangeSoft.withOpacity(.34)
                        : Theme.of(context).colorScheme.outlineVariant)),
            alignment: Alignment.center,
            child: i < active
                ? const Icon(Icons.check_rounded,
                    color: Color(0xFF66D99A), size: 17)
                : Text('${i + 1}',
                    style: TextStyle(
                        color: i == active
                            ? _orangeSoft
                            : _secondaryText(context)))),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
                color: i == active
                    ? _primaryText(context)
                    : _secondaryText(context),
                fontSize: 12))
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
              disabledBackgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
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
              foregroundColor: _primaryText(context),
              side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant),
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
          width: 40,
          height: 40,
          child: Icon(icon, color: _primaryText(context), size: 18)));
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
                        ? _orange.withOpacity(.14)
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(.75),
                    Theme.of(context).colorScheme.surface.withOpacity(.55)
                  ]),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                      color: highlighted
                          ? _orangeSoft.withOpacity(.4)
                          : Theme.of(context).colorScheme.outlineVariant)),
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
            _orange.withOpacity(.2),
            _orange.withOpacity(0),
          ]),
          shape: BoxShape.circle));
}

const _kicker = TextStyle(
    color: _orangeSoft,
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.8);
bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _primaryText(BuildContext context) =>
    _isDark(context) ? const Color(0xFFFFF7EF) : const Color(0xFF17191E);

Color _secondaryText(BuildContext context) =>
    _isDark(context) ? const Color(0xFFA99D93) : const Color(0xFF6C7078);

TextStyle _titleStyle(BuildContext context) => TextStyle(
    color: _primaryText(context),
    fontSize: 34,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2);

TextStyle _bodyStyle(BuildContext context) =>
    TextStyle(color: _secondaryText(context), fontSize: 14, height: 1.55);
