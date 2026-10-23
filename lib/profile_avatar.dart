import 'dart:convert';

import 'package:flutter/material.dart';

ImageProvider<Object>? profileImageProvider(String value) {
  final dataMatch = RegExp(
    r'^data:image/(?:png|jpeg|webp|gif);base64,([a-z0-9+/]+=*)$',
    caseSensitive: false,
  ).firstMatch(value);
  if (dataMatch != null) {
    try {
      return MemoryImage(base64Decode(dataMatch.group(1)!));
    } on FormatException {
      return null;
    }
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty) {
    return null;
  }
  return NetworkImage(value);
}
