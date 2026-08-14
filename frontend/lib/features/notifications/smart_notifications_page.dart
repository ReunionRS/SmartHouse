import 'package:flutter/material.dart';

import '../../core/i18n.dart';

class SmartNotificationsPage extends StatelessWidget {
  const SmartNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          ),
          title: Text(I18n.t('Уведомления', 'Иворъёс', 'Notifications')),
          actions: [
            TextButton(
              onPressed: null,
              child: Text(
                  I18n.t('Прочитать все', 'Ваньмыз лыдъяны', 'Mark all read')),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7A18).withOpacity(.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFF8A2A).withOpacity(.22),
                    ),
                  ),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: Color(0xFFFF8A2A),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  I18n.t('Уведомлений пока нет', 'Иворъёс али ӧвӧл',
                      'No notifications yet'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  I18n.t(
                    'Здесь появятся события устройств, предупреждения датчиков и важные сообщения дома.',
                    'Татын устройстваослэн иворъёссы но датчикъёслэн тодонъёссы потозы.',
                    'Device events, sensor alerts and important home messages will appear here.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}
