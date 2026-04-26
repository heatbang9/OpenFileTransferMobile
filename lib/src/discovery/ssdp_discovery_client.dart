import 'dart:async';
import 'dart:convert';
import 'dart:io';

const openFileTransferServiceType = 'urn:openfiletransfer:service:file-transfer:1';
const _ssdpHost = '239.255.255.250';
const _ssdpPort = 1900;

class DiscoveredServer {
  const DiscoveredServer({
    required this.deviceId,
    required this.deviceName,
    required this.address,
    required this.grpcHost,
    required this.grpcPort,
    required this.location,
    required this.serviceType,
    required this.capabilities,
    required this.ssdpFrom,
  });

  final String deviceId;
  final String deviceName;
  final String address;
  final String grpcHost;
  final int grpcPort;
  final String location;
  final String serviceType;
  final List<String> capabilities;
  final String ssdpFrom;
}

class SsdpDiscoveryClient {
  Future<List<DiscoveredServer>> discover({
    Duration timeout = const Duration(milliseconds: 2600),
  }) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: false,
    );
    final found = <String, DiscoveredServer>{};
    final pending = <Future<void>>[];
    final done = Completer<List<DiscoveredServer>>();
    Timer? timer;

    void finish() {
      if (done.isCompleted) {
        return;
      }
      timer?.cancel();
      socket.close();
      Future.wait(pending).whenComplete(() {
        done.complete(found.values.toList(growable: false));
      });
    }

    socket.broadcastEnabled = true;
    socket.multicastHops = 2;
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          final pendingDescriptor = _handleDatagram(datagram!, found);
          if (pendingDescriptor != null) {
            pending.add(pendingDescriptor);
          }
        }
      }
    }, onError: (_) => finish());

    final search = [
      'M-SEARCH * HTTP/1.1',
      'HOST: $_ssdpHost:$_ssdpPort',
      'MAN: "ssdp:discover"',
      'MX: 1',
      'ST: $openFileTransferServiceType',
      '',
      '',
    ].join('\r\n');
    socket.send(utf8.encode(search), InternetAddress(_ssdpHost), _ssdpPort);
    timer = Timer(timeout, finish);
    return done.future;
  }

  Future<void>? _handleDatagram(
    Datagram datagram,
    Map<String, DiscoveredServer> found,
  ) {
    final message = utf8.decode(datagram.data, allowMalformed: true);
    final headers = _parseHeaders(message);
    final serviceType = headers['st'] ?? headers['nt'];
    final location = headers['location'];
    if (serviceType != openFileTransferServiceType || location == null) {
      return null;
    }

    return _readDescriptor(
      location: location,
      ssdpFrom: datagram.address.address,
    ).then((server) {
      found[server.deviceId] = server;
    }).catchError((_) {
      final key = headers['usn'] ?? location;
      found[key] = DiscoveredServer(
        deviceId: key,
        deviceName: 'OpenFileTransfer 서버',
        address: '${datagram.address.address}:39091',
        grpcHost: datagram.address.address,
        grpcPort: 39091,
        location: location,
        serviceType: openFileTransferServiceType,
        capabilities: const <String>[],
        ssdpFrom: datagram.address.address,
      );
    });
  }

  Future<DiscoveredServer> _readDescriptor({
    required String location,
    required String ssdpFrom,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(milliseconds: 1200);
    try {
      final request = await client.getUrl(Uri.parse(location));
      final response = await request.close().timeout(const Duration(milliseconds: 1600));
      final body = await utf8.decodeStream(response).timeout(const Duration(milliseconds: 1600));
      final json = jsonDecode(body) as Map<String, Object?>;
      final grpcHost = json['grpcHost']?.toString() ?? ssdpFrom;
      final grpcPort = int.tryParse(json['grpcPort']?.toString() ?? '') ?? 39091;
      final deviceId = json['deviceId']?.toString() ?? '$grpcHost:$grpcPort';
      final deviceName = json['deviceName']?.toString() ?? 'OpenFileTransfer 서버';
      final capabilities = (json['capabilities'] as List<dynamic>?)
              ?.map((value) => value.toString())
              .toList(growable: false) ??
          const <String>[];

      return DiscoveredServer(
        deviceId: deviceId,
        deviceName: deviceName,
        address: '$grpcHost:$grpcPort',
        grpcHost: grpcHost,
        grpcPort: grpcPort,
        location: location,
        serviceType: json['serviceType']?.toString() ?? openFileTransferServiceType,
        capabilities: capabilities,
        ssdpFrom: ssdpFrom,
      );
    } finally {
      client.close(force: true);
    }
  }

  Map<String, String> _parseHeaders(String message) {
    final headers = <String, String>{};
    final lines = const LineSplitter().convert(message);
    for (final line in lines.skip(1)) {
      final separator = line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      headers[line.substring(0, separator).trim().toLowerCase()] =
          line.substring(separator + 1).trim();
    }
    return headers;
  }
}
