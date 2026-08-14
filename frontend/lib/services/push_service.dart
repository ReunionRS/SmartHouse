import '../models/session_models.dart';
import 'local_push_service.dart';

/// Local-only notification bootstrap.
///
/// SmartHouse intentionally does not register Firebase/APNs tokens: account
/// and hub metadata must remain inside the customer's hub. Live hub events are
/// delivered by the local connection layer, while this service only presents
/// notifications generated on the device.
class PushService {
  PushService._();

  static final PushService instance = PushService._();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await LocalPushService.instance.init();
    _initialized = true;
  }

  Future<void> registerToken(AppSession session) async {
    await init();
  }

  Future<void> unregisterToken(AppSession session) async {}
}
