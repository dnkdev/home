import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:home/log.dart';
import 'package:home/models.dart';



String formatTemplate(String template, TemplateData c) {
  if (c == null) return template;
  Map<String,dynamic> context = c;
  final buffer = StringBuffer();
  final length = template.length;

  int i = 0;
  while (i < length) {
    if (template[i] == '{' && i + 1 < length && template[i + 1] == '{') {
      i += 2; // Skip '{{'
      final keyBuffer = StringBuffer();
      
      // Collect key inside {{ }}
      while (i < length && !(template[i] == '}' && i + 1 < length && template[i + 1] == '}')) {
        Log.debug(()=> 'template[i]: ${template[i]}');
        keyBuffer.write(template[i]);
        i++;
      }

      i += 2; // Skip '}}'

      final rawKey = keyBuffer.toString().trim();
      final value = context[rawKey] ?? '';
      buffer.write(value);
    } else {
      buffer.write(template[i]);
      i++;
    }
  }

  return buffer.toString();
}

String generateNonce({int length = 16}) {
  final rand = Random.secure();
  final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
  return base64.encode(bytes);
}

/// sha256 - base64
String generateHash(String scriptContent){
  final bytes = utf8.encode(scriptContent);
  final digest = sha256.convert(bytes);
  final base64Hash = base64.encode(digest.bytes);

  Log.debug(()=>"sha256-$base64Hash");
  return "sha256-$base64Hash";
}

String generateHmac(String secretKey, String payload) {
  final key = utf8.encode(secretKey);
  final bytes = utf8.encode(payload);
  final hmacSha256 = Hmac(sha256, key);
  final digest = hmacSha256.convert(bytes);
  return base64.encode(digest.bytes); 
}

String normalizeUrlPath(String path) {
  if (path.isEmpty) return '/';

  final segments = <String>[];
  final parts = path.split('/');

  for (final part in parts) {
    if (part.isEmpty || part == '.') {
      // Skip empty segments and current dir markers
      continue;
    } else if (part == '..') {
      // Pop the last valid segment unless at root
      if (segments.isNotEmpty) {
        segments.removeLast();
      }
    } else {
      segments.add(part);
    }
  }

  final normalized = '/' + segments.join('/');

  // Remove trailing slash unless it's root
  return normalized.length > 1 && normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}

/// allowedDir is receive Directory.current.path by default.
Future<String> normalizeDirPath(String path, {String? allowedDir, bool symbolicLinks = true}) async {
  allowedDir = allowedDir ?? Directory.current.path;
  final inputPath = Uri.decodeComponent(path);
  final requestedFile = File(p.join(allowedDir, inputPath));
  final resolvedPath = symbolicLinks == true ? await requestedFile.resolveSymbolicLinks() : requestedFile.path; // TODO: should be synchronized with other IO reads, writes
  final normalizedPath = p.normalize(
    resolvedPath,
  ); // 

  if (!p.isWithin(allowedDir, normalizedPath) &&
      // allowedDir != null && //
      normalizedPath != allowedDir) {
    throw Exception(
      'Access denied: path traversal detected [$allowedDir] [$normalizedPath]',
    );
  }
  return normalizedPath;
}

String removeWhitespace(String input) {
  final buffer = StringBuffer();
  for (var char in input.runes) {
    if (char != 0x20 && char != 0x0A && char != 0x0D && char != 0x09) {
      // 0x20 = space, 0x0A = \n, 0x0D = \r, 0x09 = \t
      buffer.writeCharCode(char);
    }
  }
  return buffer.toString();
}

Future<void> printNetworkInterfaces() async {
  var interfaces = await NetworkInterface.list(
    includeLoopback: true,
    includeLinkLocal: true,
    type: InternetAddressType.any,
  );

  for (var interface in interfaces) {
    print('Interface: ${interface.name}');
    for (var addr in interface.addresses) {
      print('  Address: ${addr.address}');
      print('  Type: ${addr.type}');
      print('  Raw bytes: ${addr.rawAddress}');
    }
  }
}
Future<void> printLocalIPs() async {
  var interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );

  for (var interface in interfaces) {
    for (var addr in interface.addresses) {
      print('Local IP: ${addr.address}');
    }
  }
}