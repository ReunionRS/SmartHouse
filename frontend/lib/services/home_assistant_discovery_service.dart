import 'dart:async';
import 'dart:io';

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
      return const [];
    } finally {
      client.stop();
    }

    return instances;
  }
}
