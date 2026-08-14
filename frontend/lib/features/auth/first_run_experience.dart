import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirstRunExperience extends StatefulWidget {
  const FirstRunExperience({super.key, required this.onFinished});

  static const completionKey = 'smart_home_orange_prototype_v3_completed';
  final VoidCallback onFinished;

  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(completionKey) ?? false;
  }

  @override
  State<FirstRunExperience> createState() => _FirstRunExperienceState();
}

class _FirstRunExperienceState extends State<FirstRunExperience> {
  final controller = PageController();
  int page = 0;

  static const pages = <_OnboardingData>[
    _OnboardingData(
      background: 'home',
      eyebrow: 'Дом под контролем',
      title: 'Весь дом\nв одном приложении',
      description:
          'Управляйте светом, климатом и устройствами без сложного интерфейса.',
    ),
    _OnboardingData(
      background: 'scenes',
      eyebrow: 'Умные сценарии',
      title: 'Дом понимает\nваш ритм',
      description:
          '«Я дома», «Я ушёл», «Доброе утро» и «Спокойной ночи» запускаются в одно касание.',
    ),
    _OnboardingData(
      background: 'security',
      eyebrow: 'Безопасность',
      title: 'Важное —\nвсегда под контролем',
      description:
          'Камеры, датчики движения, двери и протечки — с понятными статусами и уведомлениями.',
    ),
    _OnboardingData(
      background: 'energy',
      eyebrow: 'Контроль энергии',
      title: 'Меньше трат.\nБольше комфорта.',
      description:
          'Отслеживайте потребление, находите лишние расходы и берегите ресурсы.',
    ),
  ];

  Future<void> finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(FirstRunExperience.completionKey, true);
    if (mounted) widget.onFinished();
  }

  void next() {
    if (page == pages.length - 1) {
      finish();
      return;
    }
    controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = pages[page];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF17120E);
    final secondary =
        isDark ? const Color(0xFFD0D5DB) : const Color(0xFF5F5A55);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0C0907) : const Color(0xFFF6F0E9),
      body: Stack(fit: StackFit.expand, children: [
        AnimatedSwitcher(
          duration: Duration(milliseconds: reduceMotion ? 1 : 420),
          child: ClipRect(
            key: ValueKey('${data.background}_$isDark'),
            child: Transform.translate(
              offset: Offset(0, isDark ? 0 : -110),
              child: Transform.scale(
                scale: isDark ? 1.04 : 1.25,
                alignment:
                    isDark ? Alignment.bottomCenter : Alignment.center,
                child: Image.asset(
                  'assets/images/onboarding/${data.background}_${isDark ? 'dark' : 'light'}.png',
                  fit: BoxFit.cover,
                  alignment:
                      isDark ? Alignment.center : const Alignment(-0.45, 0),
                ),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [
                      Color(0x22000000),
                      Color(0x33000000),
                      Color(0xF20A0806),
                    ]
                  : const [
                      Color(0x11FFFFFF),
                      Color(0x44FFFFFF),
                      Color(0xF7F6F0E9),
                    ],
              stops: const [0, .48, .76],
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: finish,
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF7A18)),
                child: const Text('Пропустить'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: controller,
                itemCount: pages.length,
                onPageChanged: (value) => setState(() => page = value),
                itemBuilder: (_, index) => _OnboardingPage(
                  data: pages[index],
                  foreground: foreground,
                  secondary: secondary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
              child: Row(children: [
                Expanded(
                  child: Row(
                    children: List.generate(
                      pages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        margin: const EdgeInsets.only(right: 7),
                        width: page == index ? 24 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: page == index
                              ? foreground
                              : foreground.withOpacity(.24),
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7A18),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF7A18).withOpacity(.38),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: IconButton(
                    onPressed: next,
                    icon: Icon(page == pages.length - 1
                        ? Icons.check_rounded
                        : Icons.arrow_forward_rounded),
                    color: Colors.white,
                    iconSize: 27,
                    padding: const EdgeInsets.all(17),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.data,
    required this.foreground,
    required this.secondary,
  });

  final _OnboardingData data;
  final Color foreground;
  final Color secondary;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Spacer(),
          Text(
            data.eyebrow.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFFF8A2A),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            data.title,
            style: TextStyle(
              color: foreground,
              fontSize: 34,
              height: 1.08,
              fontWeight: FontWeight.w700,
              letterSpacing: -.8,
            ),
          ),
          const SizedBox(height: 16),
          Text(data.description,
              style: TextStyle(color: secondary, fontSize: 16, height: 1.5)),
        ]),
      );
}

class _OnboardingData {
  const _OnboardingData({
    required this.background,
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  final String background;
  final String eyebrow;
  final String title;
  final String description;
}
