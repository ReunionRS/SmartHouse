import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';

import '../models/home_assistant_connection.dart';

class HomeAssistantDiscoveryService {
  Future<List<HomeAssistantInstance>> discoverInstances() async {
    final client = MDnsClient();
    final instances = <HomeAssistantInstance>[];
    final seen = <String>{};

    try {
      await client.start();

      await for (final PtrResourceRecord ptr in client
          .lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_home-assistant._tcp.local'),
      )
          .timeout(const Duration(seconds: 4), onTimeout: (sink) {
        sink.close();
      })) {
        final target = ptr.domainName;

        await for (final SrvResourceRecord srv in client
            .lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(target),
        )
            .timeout(const Duration(seconds: 2), onTimeout: (sink) {
          sink.close();
        })) {
          final host = srv.target;
          final port = srv.port;
          String? address;

          await for (final IPAddressResourceRecord ip in client
              .lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(host),
          )
              .timeout(const Duration(seconds: 2), onTimeout: (sink) {
            sink.close();
          })) {
            address = ip.address.address;
            break;
          }

          address ??= host.replaceAll(RegExp(r'\.$'), '');
          final normalizedHost = address.replaceAll(RegExp(r'\.$'), '');
          final key = '$normalizedHost:$port';
          if (seen.contains(key)) continue;
          seen.add(key);

          final baseUrl = 'http://$normalizedHost:$port';
          instances.add(
            HomeAssistantInstance(
              name:
                  ptr.domainName.replaceAll('._home-assistant._tcp.local', ''),
              host: normalizedHost,
              port: port,
              baseUrl: baseUrl,
            ),
          );
        }
      }
    } on SocketException {
      // If multicast DNS is unavailable on this device, continue with fallback probes.
    } finally {
      client.stop();
    }

    if (instances.isEmpty) {
      final fallbackUrls = <String>{
        'http://localhost:8123',
        'http://127.0.0.1:8123',
      };
      if (Platform.isAndroid) {
        fallbackUrls.add('http://10.0.2.2:8123');
      }
      if (Platform.isIOS) {
        fallbackUrls.add('http://host.docker.internal:8123');
      }
      if (Platform.isMacOS) {
        fallbackUrls.add('http://host.docker.internal:8123');
      }
      for (final baseUrl in fallbackUrls) {
        final instance = await _probeHomeAssistant(baseUrl);
        if (instance != null && !instances.any((item) => item.baseUrl == instance.baseUrl)) {
          instances.add(instance);
        }
      }
    }

    return instances;
  }

  Future<HomeAssistantInstance?> _probeHomeAssistant(String baseUrl) async {
    try {
      final uri = Uri.parse('$baseUrl/api/smart_house/info');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['product'] != 'Smart House Hub') {
        return null;
      }
      final parsed = Uri.parse(baseUrl);
      return HomeAssistantInstance(
        name: 'Home Assistant',
        host: parsed.host,
        port: parsed.port == 0 ? 8123 : parsed.port,
        baseUrl: baseUrl,
      );
    } catch (_) {
      return null;
    }
  }
}
