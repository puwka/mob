import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

Future<Uint8List> readLocalFileBytes(String path) async {
  return File(path).readAsBytes();
}

Future<Uint8List> readBlobUrlBytes(String url) async {
  final res = await http.get(Uri.parse(url));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    return Uint8List(0);
  }
  return res.bodyBytes;
}
