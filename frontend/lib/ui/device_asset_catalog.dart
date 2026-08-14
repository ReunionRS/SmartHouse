abstract final class DeviceAssetCatalog {
  static const light = 'assets/images/devices/light.webp';
  static const lightCool = 'assets/images/devices/light_cool.png';
  static const lightWarm = 'assets/images/devices/light_warm.png';
  static const camera = 'assets/images/devices/camera.webp';
  static const socket = 'assets/images/devices/socket.webp';
  static const thermostat = 'assets/images/devices/thermostat.webp';
  static const motionSensor = 'assets/images/devices/motion_sensor.webp';
  static const smokeSensor = 'assets/images/devices/smoke_sensor.webp';
  static const leakSensor = 'assets/images/devices/leak_sensor.webp';
  static const airConditioner = 'assets/images/devices/air_conditioner.webp';
  static const smartLock = 'assets/images/devices/smart_lock.webp';
  static const hub = 'assets/images/devices/hub.webp';
  static const temperatureHumidity =
      'assets/images/devices/temperature_humidity.png';
  static const rgbStrip = 'assets/images/devices/rgb_strip.png';

  static const byType = <String, String>{
    'light': light,
    'rgb_light': light,
    'rgb_strip': rgbStrip,
    'camera': camera,
    'socket': socket,
    'switch': socket,
    'thermostat': thermostat,
    'climate': thermostat,
    'motion_sensor': motionSensor,
    'contact_sensor': smartLock,
    'opening_sensor': smartLock,
    'temperature_sensor': temperatureHumidity,
    'temperature_humidity_sensor': temperatureHumidity,
    'smoke_sensor': smokeSensor,
    'leak_sensor': leakSensor,
    'air_conditioner': airConditioner,
    'lock': smartLock,
    'hub': hub,
  };

  static String? forType(String type) => byType[type.toLowerCase()];

  static String lightForMode(String mode) => switch (mode) {
        'cool' => lightCool,
        'warm' => lightWarm,
        _ => light,
      };
}
