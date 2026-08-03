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
      icon: Icons.home_rounded,
      eyebrow: 'Дом под контролем',
      title: 'Весь дом\nв одном приложении',
      description:
          'Управляйте светом, климатом и устройствами без сложного интерфейса.',
      accents: [Color(0xFFFF8A2A), Color(0xFFFF7A18)],
    ),
    _OnboardingData(
      icon: Icons.auto_awesome_rounded,
      eyebrow: 'Умные сценарии',
      title: 'Дом понимает\nваш ритм',
      description:
          '«Я дома», «Я ушёл», «Доброе утро» и «Спокойной ночи» запускаются в одно касание.',
      accents: [Color(0xFFFF8A2A), Color(0xFFFF7A18)],
    ),
    _OnboardingData(
      icon: Icons.shield_rounded,
      eyebrow: 'Безопасность',
      title: 'Важное —\nвсегда под контролем',
      description:
          'Камеры, датчики движения, двери и протечки — с понятными статусами и уведомлениями.',
      accents: [Color(0xFFFF8A2A), Color(0xFFFF7A18)],
    ),
    _OnboardingData(
      icon: Icons.bolt_rounded,
      eyebrow: 'Контроль энергии',
      title: 'Меньше трат.\nБольше комфорта.',
      description:
          'Отслеживайте потребление, находите лишние расходы и берегите ресурсы.',
      accents: [Color(0xFFFF8A2A), Color(0xFFFF7A18)],
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
    return Scaffold(
      backgroundColor: const Color(0xFF0C0907),
      body: AnimatedContainer(
        duration: Duration(milliseconds: reduceMotion ? 1 : 350),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              data.accents.first.withValues(alpha: .35),
              const Color(0xFF17100B),
              data.accents.last.withValues(alpha: .18)
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: finish, child: const Text('Пропустить')),
              ),
              Expanded(
                child: PageView.builder(
                  controller: controller,
                  itemCount: pages.length,
                  onPageChanged: (value) => setState(() => page = value),
                  itemBuilder: (_, index) =>
                      _OnboardingPage(data: pages[index]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                child: Row(
                  children: [
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
                                          ? Colors.white
                                          : Colors.white24,
                                      borderRadius: BorderRadius.circular(9)),
                                )),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: data.accents),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: data.accents.first.withValues(alpha: .45),
                              blurRadius: 24)
                        ],
                      ),
                      child: IconButton(
                          onPressed: next,
                          icon: Icon(page == pages.length - 1
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded),
                          color: Colors.white,
                          iconSize: 27,
                          padding: const EdgeInsets.all(17)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data});
  final _OnboardingData data;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Spacer(),
          Center(child: _GlassOrb(data: data)),
          const Spacer(),
          Text(data.eyebrow.toUpperCase(),
              style: TextStyle(
                  color: data.accents.first,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3)),
          const SizedBox(height: 12),
          Text(data.title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1.08,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.8)),
          const SizedBox(height: 16),
          Text(data.description,
              style: const TextStyle(
                  color: Color(0xFFB4C2D0), fontSize: 16, height: 1.5)),
        ]),
      );
}

class _GlassOrb extends StatelessWidget {
  const _GlassOrb({required this.data});
  final _OnboardingData data;
  @override
  Widget build(BuildContext context) => Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              data.accents.first.withValues(alpha: .32),
              Colors.transparent
            ]),
            boxShadow: [
              BoxShadow(
                  color: data.accents.last.withValues(alpha: .22),
                  blurRadius: 70,
                  spreadRadius: 8)
            ]),
        alignment: Alignment.center,
        child: Container(
          width: 126,
          height: 126,
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.white.withValues(alpha: .25),
                data.accents.last.withValues(alpha: .42)
              ]),
              borderRadius: BorderRadius.circular(38),
              border: Border.all(color: Colors.white38)),
          child: Icon(data.icon, color: Colors.white, size: 61),
        ),
      );
}

class _OnboardingData {
  const _OnboardingData(
      {required this.icon,
      required this.eyebrow,
      required this.title,
      required this.description,
      required this.accents});
  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
  final List<Color> accents;
}
