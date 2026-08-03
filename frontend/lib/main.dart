import 'package:flutter/material.dart';

import 'app.dart';
import 'services/push_service.dart';

export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushService.instance.init();
  runApp(const SmartHouseApp());
}
