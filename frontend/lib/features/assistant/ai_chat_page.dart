import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui_tokens.dart';
import '../../core/app_language.dart';
import '../../services/ai_assistant_service.dart';

class AiChatSheet extends StatefulWidget {
  const AiChatSheet({super.key});

  @override
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> {
  final controller = TextEditingController();
  final scrollController = ScrollController();
  final service = AiAssistantService();
  final speech = SpeechToText();
  final messages = <({String text, bool assistant})>[];
  String? conversationId;
  bool sending = false;
  String responseType = 'text';
  Map<String, dynamic>? responseData;
  bool actionProcessing = false;
  Timer? statusTimer;
  List<String> activeStatuses = const ['Обрабатываю запрос…'];
  int statusIndex = 0;
  Timer? recordingTimer;
  Duration recordingDuration = Duration.zero;
  bool listening = false;
  bool restartingVoice = false;
  String voicePrefix = '';
  int voiceSessionId = 0;
  double soundLevel = 0;
  bool loadingHistory = true;
  int restoredMessageCount = 0;

  bool get english => AppLanguageStore.current == AppLanguage.en;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await service.loadLatestConversation();
      if (!mounted) return;
      setState(() {
        conversationId = history?.id;
        messages
          ..clear()
          ..addAll((history?.messages ?? const [])
              .map((item) => (text: item.text, assistant: item.assistant)));
        restoredMessageCount = messages.length;
        loadingHistory = false;
      });
      scrollToBottom(immediate: true);
    } catch (_) {
      if (mounted) setState(() => loadingHistory = false);
    }
  }

  List<String> get questions => english
      ? const [
          'What is happening at home?',
          'Why is the bedroom cold?',
          'Which devices have low battery?',
          'How much energy was used today?',
        ]
      : const [
          'Что происходит дома?',
          'Почему в спальне холодно?',
          'У каких устройств низкий заряд?',
          'Сколько энергии потрачено сегодня?',
        ];

  @override
  void dispose() {
    statusTimer?.cancel();
    recordingTimer?.cancel();
    voiceSessionId += 1;
    speech.stop();
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  String get recordingTime {
    final minutes = recordingDuration.inMinutes.toString().padLeft(2, '0');
    final seconds =
        (recordingDuration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> toggleVoiceInput() async {
    if (listening) {
      await stopVoiceInput();
      return;
    }
    final available = await speech.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && listening) {
          voicePrefix = controller.text.trim();
          _listenVoiceCycle();
        }
      },
      onError: (error) {
        if (!mounted) return;
        stopVoiceInput();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(english
              ? 'Voice input is unavailable: ${error.errorMsg}'
              : 'Голосовой ввод недоступен: ${error.errorMsg}'),
        ));
      },
    );
    if (!available || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(english
              ? 'Allow microphone and speech recognition access.'
              : 'Разрешите доступ к микрофону и распознаванию речи.'),
        ));
      }
      return;
    }
    setState(() {
      voiceSessionId += 1;
      listening = true;
      recordingDuration = Duration.zero;
      soundLevel = 0;
      voicePrefix = controller.text.trim();
    });
    recordingTimer?.cancel();
    recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && listening) {
        setState(() => recordingDuration += const Duration(seconds: 1));
      }
    });
    await _listenVoiceCycle();
  }

  Future<void> _listenVoiceCycle() async {
    if (!listening || speech.isListening || restartingVoice) return;
    restartingVoice = true;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!listening) {
      restartingVoice = false;
      return;
    }
    final sessionId = voiceSessionId;
    await speech.listen(
      localeId: english ? 'en_US' : 'ru_RU',
      partialResults: true,
      listenMode: ListenMode.dictation,
      listenFor: const Duration(minutes: 10),
      pauseFor: const Duration(seconds: 30),
      cancelOnError: false,
      onSoundLevelChange: (level) {
        if (mounted && listening && sessionId == voiceSessionId) {
          setState(() => soundLevel = level);
        }
      },
      onResult: (result) {
        if (!mounted || sessionId != voiceSessionId) return;
        controller.text = [voicePrefix, result.recognizedWords]
            .where((part) => part.trim().isNotEmpty)
            .join(' ');
        controller.selection =
            TextSelection.collapsed(offset: controller.text.length);
        if (result.finalResult) voicePrefix = controller.text.trim();
        setState(() {});
      },
    );
    restartingVoice = false;
  }

  Future<void> stopVoiceInput() async {
    recordingTimer?.cancel();
    if (mounted && listening) setState(() => listening = false);
    if (speech.isListening) await speech.stop();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    voiceSessionId += 1;
    restartingVoice = false;
  }

  Future<void> sendVoiceInput() async {
    await stopVoiceInput();
    final recognizedText = controller.text.trim();
    if (recognizedText.isNotEmpty) await send(recognizedText);
  }

  void scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      if (immediate) {
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        return;
      }
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  List<String> statusesFor(String text) {
    final query = text.toLowerCase();
    if (english) {
      if (query.contains('buy') ||
          query.contains('price') ||
          query.contains('recommend') ||
          query.contains('marketplace') ||
          query.contains('shop')) {
        return const [
          'Searching for suitable devices online…',
          'Checking available marketplaces…',
          'Comparing the search results…',
          'Checking Home Assistant compatibility…',
        ];
      }
      if (query.contains('weather') || query.contains('forecast')) {
        return const [
          'Identifying the location…',
          'Getting weather-service data…',
          'Checking the latest forecast…',
        ];
      }
      return const [
        'Connecting to Smart Hub…',
        'Checking Home Assistant data…',
        'Preparing the answer…',
      ];
    }
    if (query.contains('купить') ||
        query.contains('покупк') ||
        query.contains('подбери') ||
        query.contains('посоветуй') ||
        query.contains('рекомендуй') ||
        query.contains('маркетплейс') ||
        query.contains('магазин') ||
        query.contains('цена')) {
      return const [
        'Ищу подходящие устройства в сети…',
        'Проверяю российские маркетплейсы…',
        'Сравниваю найденные предложения…',
        'Проверяю совместимость с Home Assistant…',
      ];
    }
    if (query.contains('погод') ||
        query.contains('прогноз') ||
        query.contains('температура на улице')) {
      return const [
        'Определяю город…',
        'Получаю данные метеослужбы…',
        'Проверяю актуальный прогноз…',
      ];
    }
    if (query.contains('энерг') || query.contains('электр')) {
      return const [
        'Связываюсь со Smart Hub…',
        'Ищу счётчики энергии…',
        'Анализирую энергопотребление…',
      ];
    }
    if (query.contains('почему') ||
        query.contains('истори') ||
        query.contains('происходило')) {
      return const [
        'Связываюсь со Smart Hub…',
        'Проверяю базу Smart Hub…',
        'Смотрю историю Home Assistant…',
        'Сопоставляю события…',
      ];
    }
    if (query.contains('автоматизац') || query.contains('сценар')) {
      return const [
        'Проверяю устройства и комнаты…',
        'Проверяю совместимость действий…',
        'Подготавливаю автоматизацию…',
      ];
    }
    if (query.contains('включ') ||
        query.contains('выключ') ||
        query.contains('установ') ||
        query.contains('открой') ||
        query.contains('закрой')) {
      return const [
        'Ищу устройство в Smart Hub…',
        'Проверяю доступность устройства…',
        'Подготавливаю безопасное действие…',
      ];
    }
    return const [
      'Связываюсь со Smart Hub…',
      'Проверяю данные Home Assistant…',
      'Анализирую состояние дома…',
    ];
  }

  void startStatuses(String text) {
    statusTimer?.cancel();
    activeStatuses = statusesFor(text);
    statusIndex = 0;
    statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !sending) return;
      setState(() => statusIndex = (statusIndex + 1) % activeStatuses.length);
    });
  }

  Future<void> send([String? value]) async {
    final text = (value ?? controller.text).trim();
    if (text.isEmpty || sending) return;
    controller.clear();
    startStatuses(text);
    setState(() {
      sending = true;
      messages.add((text: text, assistant: false));
    });
    scrollToBottom();
    try {
      final response =
          await service.send(message: text, conversationId: conversationId);
      if (!mounted) return;
      setState(() {
        conversationId = response.conversationId;
        responseType = response.type;
        responseData = response.data;
        messages.add((text: response.message, assistant: true));
      });
      scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() => messages.add((
            text: error.toString().replaceFirst('Exception: ', ''),
            assistant: true
          )));
      scrollToBottom();
    } finally {
      statusTimer?.cancel();
      if (mounted) setState(() => sending = false);
      scrollToBottom();
    }
  }

  Future<void> confirmAction() async {
    final id = (responseData?['id'] ?? '').toString();
    if (id.isEmpty || actionProcessing) return;
    setState(() => actionProcessing = true);
    try {
      final text = await service.confirmAction(id);
      if (!mounted) return;
      setState(() {
        responseType = 'text';
        responseData = null;
        messages.add((text: text, assistant: true));
      });
      scrollToBottom();
    } catch (error) {
      if (mounted) {
        setState(() => messages.add((
              text: error.toString().replaceFirst('Exception: ', ''),
              assistant: true,
            )));
        scrollToBottom();
      }
    } finally {
      if (mounted) setState(() => actionProcessing = false);
    }
  }

  Future<void> cancelAction() async {
    final id = (responseData?['id'] ?? '').toString();
    if (id.isEmpty || actionProcessing) return;
    setState(() => actionProcessing = true);
    try {
      await service.cancelAction(id);
      if (!mounted) return;
      setState(() {
        responseType = 'text';
        responseData = null;
        messages.add((text: 'Действие отменено.', assistant: true));
      });
      scrollToBottom();
    } catch (error) {
      if (mounted) {
        setState(() => messages.add((
              text: error.toString().replaceFirst('Exception: ', ''),
              assistant: true,
            )));
        scrollToBottom();
      }
    } finally {
      if (mounted) setState(() => actionProcessing = false);
    }
  }

  Future<void> createAutomation() async {
    final draft = responseData;
    if (draft == null || actionProcessing) return;
    setState(() => actionProcessing = true);
    try {
      final text = await service.createAutomation(draft);
      if (!mounted) return;
      setState(() {
        responseType = 'text';
        responseData = null;
        messages.add((text: text, assistant: true));
      });
      scrollToBottom();
    } catch (error) {
      if (mounted) {
        setState(() => messages.add((
              text: error.toString().replaceFirst('Exception: ', ''),
              assistant: true,
            )));
        scrollToBottom();
      }
    } finally {
      if (mounted) setState(() => actionProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sheetColor = dark ? const Color(0xFF151A22) : const Color(0xFFF4F4F5);
    final cardColor = dark ? const Color(0xFF222832) : Colors.white;
    final inputColor = dark ? const Color(0xFF252C36) : const Color(0xFFE8E8EA);
    final primaryText =
        dark ? const Color(0xFFF5F2EE) : const Color(0xFF29292D);
    final secondaryText =
        dark ? const Color(0xFFAEB4BE) : const Color(0xFF77777C);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .72,
      ),
      padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + keyboard),
      decoration: BoxDecoration(
        color: sheetColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF59616D) : const Color(0xFFC7C7C9),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 13),
        Row(children: [
          const _AssistantMark(),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SmartHouse Assistant',
                  style: TextStyle(
                      color: primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(english ? 'Ask about your home…' : 'Спросите о вашем доме…',
                  style: TextStyle(color: secondaryText, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Flexible(
          child: SingleChildScrollView(
            controller: scrollController,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: dark
                          ? const Color(0x33000000)
                          : const Color(0x17000000),
                      blurRadius: 24,
                      offset: const Offset(0, 9),
                    ),
                  ],
                ),
                child: Text(
                  english
                      ? 'I receive live data directly from your local Home Assistant. Ask what is happening at home.'
                      : 'Я получаю актуальные данные напрямую с вашего локального Home Assistant. Спросите, что сейчас происходит дома.',
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
              ),
              if (loadingHistory)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (messages.isEmpty) ...[
                const SizedBox(height: 17),
                Text(english ? 'Try asking' : 'Попробуйте спросить',
                    style: TextStyle(color: secondaryText, fontSize: 12)),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: questions
                      .map((text) => ActionChip(
                            label: Text(text),
                            labelStyle:
                                TextStyle(color: primaryText, fontSize: 12),
                            backgroundColor: cardColor,
                            side: BorderSide.none,
                            shape: const StadiumBorder(),
                            onPressed: () => send(text),
                          ))
                      .toList(),
                ),
              ] else ...[
                const SizedBox(height: 14),
                ...messages.asMap().entries.map((entry) {
                  final item = entry.value;
                  final animate = entry.key >= restoredMessageCount;
                  return TweenAnimationBuilder<double>(
                    key: ValueKey(
                        '${entry.key}_${item.assistant}_${item.text.hashCode}'),
                    tween: Tween(begin: animate ? 0 : 1, end: 1),
                    duration: animate
                        ? const Duration(milliseconds: 320)
                        : Duration.zero,
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 10 * (1 - value)),
                        child: child,
                      ),
                    ),
                    child: Align(
                      alignment: item.assistant
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: item.assistant ? cardColor : UiTokens.accent,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: item.assistant && animate
                            ? _AnimatedAssistantMarkdown(
                                data: item.text,
                                color: primaryText,
                                onProgress: () =>
                                    scrollToBottom(immediate: true),
                              )
                            : item.assistant
                                ? _AssistantMarkdown(
                                    data: item.text,
                                    color: primaryText,
                                  )
                                : Text(
                                    item.text,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                      ),
                    ),
                  );
                }),
                if (responseData != null && responseType != 'text')
                  _AiDataCard(
                    type: responseType,
                    data: responseData!,
                    processing: actionProcessing,
                    onConfirm: responseType == 'automation_draft'
                        ? createAutomation
                        : confirmAction,
                    onCancel: cancelAction,
                  ),
                if (sending)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          activeStatuses[statusIndex],
                          key: ValueKey(statusIndex),
                        ),
                      ),
                    ]),
                  ),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 13),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 5, 6, 5),
          decoration: BoxDecoration(
            color: inputColor,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Row(children: [
            if (listening) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: UiTokens.accent.withOpacity(.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: Colors.redAccent, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(recordingTime,
                      style: TextStyle(
                          color: primaryText, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: _VoiceLevel(
                level: soundLevel,
                color: UiTokens.accent,
                label: english ? 'Listening…' : 'Говорите…',
              )),
            ] else
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => send(),
                  onTap: scrollToBottom,
                  style: TextStyle(color: primaryText, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: english
                        ? 'Ask about your home…'
                        : 'Спросите о вашем доме…',
                    hintStyle: TextStyle(color: secondaryText),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    isDense: true,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(
                begin: 1,
                end: listening
                    ? 1.05 + (((soundLevel + 2) / 12).clamp(0, 1) * .18)
                    : 1,
              ),
              duration: const Duration(milliseconds: 180),
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: IconButton(
                onPressed: sending
                    ? null
                    : listening
                        ? sendVoiceInput
                        : toggleVoiceInput,
                style: IconButton.styleFrom(
                  backgroundColor: listening
                      ? Colors.redAccent
                      : UiTokens.accent.withOpacity(.12),
                  foregroundColor: listening ? Colors.white : UiTokens.accent,
                ),
                icon: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 20),
              ),
            ),
            if (!listening) const SizedBox(width: 4),
            if (!listening)
              IconButton.filled(
                onPressed: sending ? null : () => send(),
                style: IconButton.styleFrom(
                  backgroundColor: UiTokens.accent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.arrow_upward_rounded, size: 19),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _VoiceLevel extends StatelessWidget {
  const _VoiceLevel(
      {required this.level, required this.color, required this.label});
  final double level;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final strength = ((level + 2) / 12).clamp(0.08, 1.0);
    return Row(children: [
      for (var index = 0; index < 5; index++) ...[
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 3,
          height: 7 + 17 * ((strength + index * .13) % 1),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 3),
      ],
      const SizedBox(width: 5),
      Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12))),
    ]);
  }
}

class _AnimatedAssistantMarkdown extends StatefulWidget {
  const _AnimatedAssistantMarkdown({
    required this.data,
    required this.color,
    required this.onProgress,
  });

  final String data;
  final Color color;
  final VoidCallback onProgress;

  @override
  State<_AnimatedAssistantMarkdown> createState() =>
      _AnimatedAssistantMarkdownState();
}

class _AnimatedAssistantMarkdownState
    extends State<_AnimatedAssistantMarkdown> {
  Timer? timer;
  int visibleCharacters = 0;
  int ticks = 0;

  int get charactersPerTick => (widget.data.length / 110).ceil().clamp(1, 14);

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 18), (_) {
      if (!mounted) return;
      final next = (visibleCharacters + charactersPerTick)
          .clamp(0, widget.data.length)
          .toInt();
      setState(() => visibleCharacters = next);
      ticks++;
      if (ticks % 4 == 0 || next == widget.data.length) {
        widget.onProgress();
      }
      if (next == widget.data.length) timer?.cancel();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AssistantMarkdown(
        data: widget.data.substring(0, visibleCharacters),
        color: widget.color,
      );
}

class _AssistantMarkdown extends StatelessWidget {
  const _AssistantMarkdown({required this.data, required this.color});

  final String data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final codeBackground = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF20262F)
        : const Color(0xFFF0F1F3);
    final safeData = data.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
      (match) => match.group(1)?.trim().isNotEmpty == true
          ? '_${match.group(1)}_'
          : '_Изображение_',
    );

    return MarkdownBody(
      data: safeData,
      selectable: true,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: color, fontSize: 13, height: 1.42),
        strong: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        em: TextStyle(
          color: color,
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
        h1: TextStyle(color: color, fontSize: 19, fontWeight: FontWeight.w800),
        h2: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800),
        h3: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700),
        listBullet: const TextStyle(color: UiTokens.accent, fontSize: 14),
        a: const TextStyle(
          color: UiTokens.accent,
          decoration: TextDecoration.underline,
          decorationColor: UiTokens.accent,
        ),
        blockquote: TextStyle(color: secondary, fontSize: 13, height: 1.4),
        blockquoteDecoration: BoxDecoration(
          color: UiTokens.accent.withOpacity(.08),
          border:
              const Border(left: BorderSide(color: UiTokens.accent, width: 3)),
          borderRadius: BorderRadius.circular(6),
        ),
        code: TextStyle(
          color: color,
          fontSize: 12,
          fontFamily: 'monospace',
          backgroundColor: codeBackground,
        ),
        codeblockDecoration: BoxDecoration(
          color: codeBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        codeblockPadding: const EdgeInsets.all(10),
        horizontalRuleDecoration: BoxDecoration(
          border:
              Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
      ),
      onTapLink: (_, href, __) async {
        final uri = Uri.tryParse(href ?? '');
        if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) {
          return;
        }
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }
}

class _AiDataCard extends StatelessWidget {
  const _AiDataCard({
    required this.type,
    required this.data,
    required this.processing,
    required this.onConfirm,
    required this.onCancel,
  });

  final String type;
  final Map<String, dynamic> data;
  final bool processing;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (type == 'confirmation') {
      return _card(
        context,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Требуется подтверждение',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 6),
          Text(_actionTitle((data['action'] ?? '').toString())),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: processing ? null : onCancel,
                child: const Text('Отмена'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: processing ? null : onConfirm,
                child: processing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Подтвердить'),
              ),
            ),
          ]),
        ]),
      );
    }
    if (type == 'automation_draft') {
      return _card(
        context,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Черновик автоматизации',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 7),
          Text((data['name'] ?? 'Без названия').toString()),
          const SizedBox(height: 4),
          Text((data['description'] ?? '').toString(),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: processing ? null : onConfirm,
              icon: processing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_task_rounded),
              label: const Text('Создать в Home Assistant'),
            ),
          ),
        ]),
      );
    }
    if (type == 'home_summary') {
      final temperature = data['temperature'];
      final humidity = data['humidity'];
      final lights = data['lights'];
      final openings = data['openings'];
      return _card(
        context,
        Wrap(spacing: 8, runSpacing: 8, children: [
          _metric(
              context,
              Icons.thermostat_rounded,
              temperature is Map
                  ? '${temperature['average']} °C'
                  : 'Нет данных'),
          _metric(context, Icons.water_drop_outlined,
              humidity is Map ? '${humidity['average']}%' : 'Нет данных'),
          _metric(
              context,
              Icons.lightbulb_outline_rounded,
              lights is Map
                  ? '${lights['on']} из ${lights['total']}'
                  : 'Нет данных'),
          _metric(
              context,
              Icons.sensor_door_outlined,
              openings is Map && openings['open'] is List
                  ? 'Открыто: ${(openings['open'] as List).length}'
                  : 'Нет данных'),
          _metric(context, Icons.warning_amber_rounded,
              'Недоступно: ${data['unavailable_devices'] ?? 0}'),
        ]),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _card(BuildContext context, Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF222832)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: child,
      );

  Widget _metric(BuildContext context, IconData icon, String value) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF2B333E)
              : const Color(0xFFF1F1F3),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: UiTokens.accent),
          const SizedBox(width: 5),
          Text(value, style: const TextStyle(fontSize: 12)),
        ]),
      );

  String _actionTitle(String action) => switch (action) {
        'set_climate_temperature' => 'Изменить температуру',
        'open_cover' => 'Открыть шторы',
        'close_cover' => 'Закрыть шторы',
        _ => 'Выполнить действие',
      };
}

class _AssistantMark extends StatelessWidget {
  const _AssistantMark();

  @override
  Widget build(BuildContext context) => Container(
        width: 45,
        height: 45,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: UiTokens.accent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
              color: UiTokens.accent.withOpacity(.28),
              blurRadius: 15,
            ),
          ],
        ),
        child: Image.asset(
          'assets/images/icons/ai_assistant.png',
          color: Colors.white,
        ),
      );
}
