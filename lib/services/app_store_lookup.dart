import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'update_check.dart';

const kAppStoreBundleId = 'com.infyter.app';

/// Where "Update" takes the person on iPhone. Fixed in the app, never taken from a store answer.
const kAppStoreUrl = 'https://apps.apple.com/app/id6820268450';

/// Answers larger than this are not a lookup answer (the real one is about 10 KB).
const _maxBody = 1024 * 1024;

/// The version check on iPhone: Apple's public lookup for Infyter's bundle in the App Store of [country]. It sends
/// only the bundle id and the country.
class AppStoreLookup {
  AppStoreLookup({this.base = 'https://itunes.apple.com', this.timeout = const Duration(seconds: 8)});

  final String base;
  final Duration timeout;

  Uri uriFor(String country) =>
      Uri.parse('$base/lookup').replace(queryParameters: {'bundleId': kAppStoreBundleId, 'country': country});

  Future<UpdateCheck> check({
    required String installed,
    required String? country,
    required String osVersion,
    required DateTime now,
  }) async {
    if (country == null) return const UpdateCheck(UpdateReason.noRegion);
    final client = HttpClient()..connectionTimeout = timeout;
    final String body;
    try {
      body = await _get(client, uriFor(country)).timeout(timeout);
    } on TimeoutException {
      return const UpdateCheck(UpdateReason.timeout);
    } on _HttpStatus {
      return const UpdateCheck(UpdateReason.http);
    } on FormatException {
      return const UpdateCheck(UpdateReason.badJson);
    } catch (_) {
      return const UpdateCheck(UpdateReason.network);
    } finally {
      // Also aborts a request that is still waiting after the timeout.
      client.close(force: true);
    }
    return evaluateLookup(body, installed: installed, osVersion: osVersion, now: now);
  }

  Future<String> _get(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) throw _HttpStatus(response.statusCode);
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBody) throw const FormatException('Lookup answer too large');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

class _HttpStatus implements Exception {
  const _HttpStatus(this.code);
  final int code;
}

/// Decides from a lookup answer. Pure: the tests feed it recorded answers.
UpdateCheck evaluateLookup(
  String body, {
  required String installed,
  required String osVersion,
  required DateTime now,
}) {
  try {
    compareVersions(installed, installed);
  } on FormatException {
    return const UpdateCheck(UpdateReason.noVersion);
  }

  final Object? data;
  try {
    data = jsonDecode(body);
  } on FormatException {
    return const UpdateCheck(UpdateReason.badJson);
  }
  if (data is! Map) return const UpdateCheck(UpdateReason.badJson);
  final results = data['results'];
  if (results is! List) return const UpdateCheck(UpdateReason.badJson);
  if (results.isEmpty) return const UpdateCheck(UpdateReason.noResults);
  final app = results.first;
  if (app is! Map) return const UpdateCheck(UpdateReason.badJson);
  if (app['bundleId'] != kAppStoreBundleId) return const UpdateCheck(UpdateReason.otherApp);
  final version = app['version'];
  if (version is! String) return const UpdateCheck(UpdateReason.badJson);

  final int order;
  try {
    order = compareVersions(version, installed);
  } on FormatException {
    return const UpdateCheck(UpdateReason.badJson);
  }
  if (order == 0) return UpdateCheck(UpdateReason.equal, storeVersion: version);
  if (order < 0) return UpdateCheck(UpdateReason.older, storeVersion: version);

  final released = DateTime.tryParse('${app['currentVersionReleaseDate'] ?? ''}');
  if (released == null || now.difference(released) < kUpdateGrace) {
    return UpdateCheck(UpdateReason.grace, storeVersion: version);
  }
  final minimum = app['minimumOsVersion'];
  if (minimum is String && minimum.isNotEmpty && !_runsOn(minimum, osVersion)) {
    return UpdateCheck(UpdateReason.minOs, storeVersion: version);
  }
  return UpdateCheck(UpdateReason.newer, storeVersion: version);
}

final RegExp _osNumber = RegExp(r'\d+(\.\d+)*');

// Whether a device with [osVersion] ("Version 17.5.1 (Build 21F90)") can install a version that needs [minimum].
bool _runsOn(String minimum, String osVersion) {
  final device = _osNumber.firstMatch(osVersion)?.group(0);
  if (device == null) return false;
  try {
    return compareVersions(minimum, device) <= 0;
  } on FormatException {
    return false;
  }
}

final RegExp _region = RegExp(r'^[A-Za-z]{2}$');

// A region set apart from the language: "en_US@rg=arzzzz" (Unicode locale keyword "rg").
final RegExp _regionKeyword = RegExp(r'[@;]rg=([A-Za-z]{2})');

/// The 2-letter region of a locale name ("es_AR" → "ar", "en_US@rg=arzzzz" → "ar"), or null when it has none.
String? regionOf(String localeName) {
  final keyword = _regionKeyword.firstMatch(localeName);
  if (keyword != null) return keyword.group(1)!.toLowerCase();
  final parts = localeName.split(RegExp('[.@]')).first.split(RegExp('[-_]'));
  for (final part in parts.skip(1).toList().reversed) {
    if (_region.hasMatch(part)) return part.toLowerCase();
  }
  return null;
}
