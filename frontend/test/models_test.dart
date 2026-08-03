import 'package:flutter_test/flutter_test.dart';
import 'package:smart_house/models/local_room_device.dart';
import 'package:smart_house/models/smart_scene.dart';

void main() {
  test('SmartScene survives JSON persistence', () {
    const scene = SmartScene(
      id: 'scene-1',
      name: 'Ночной свет',
      triggerType: 'time',
      triggerTime: '22:30',
      triggerDeviceId: '',
      triggerCondition: 'active',
      triggerValue: 25,
      triggerDays: [0, 1, 2, 3, 4],
      actionDeviceId: 'light-1',
      actionType: 'turn_on',
    );

    final restored = SmartScene.fromJson(scene.toJson());
    expect(restored.name, scene.name);
    expect(restored.triggerDays, scene.triggerDays);
    expect(restored.actionType, 'turn_on');
  });

  test('LocalRoomDevice copy keeps identity and updates state', () {
    const device = LocalRoomDevice(
      id: 'light-1',
      roomId: 'living-room',
      name: 'Лампа',
      type: 'light',
      isOn: false,
    );

    final enabled = device.copyWith(isOn: true, brightness: 72);
    expect(enabled.id, device.id);
    expect(enabled.roomId, device.roomId);
    expect(enabled.isOn, isTrue);
    expect(enabled.brightness, 72);
  });
}
