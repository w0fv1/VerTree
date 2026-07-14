import 'dart:convert';

import 'package:http/http.dart' as http;

class AppAnnouncement {
  const AppAnnouncement({
    required this.uuid,
    required this.content,
    required this.expiresAt,
    this.linkUri,
  });

  final String uuid;
  final String content;
  final DateTime expiresAt;
  final Uri? linkUri;

  static AppAnnouncement? tryParse(dynamic raw) {
    if (raw is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(raw);
    final uuid = map['uuid']?.toString().trim() ?? '';
    final content = map['content']?.toString().trim() ?? '';
    final expiresAtRaw =
        map['expiresAt'] ?? map['expireAt'] ?? map['expiredAt'];
    final expiresAtText = expiresAtRaw?.toString().trim() ?? '';
    final linkUri = _tryParseLinkUri(
      map['link'] ?? map['url'] ?? map['href'] ?? map['linkUrl'],
    );

    if (uuid.isEmpty || content.isEmpty || expiresAtText.isEmpty) {
      return null;
    }

    final expiresAt = DateTime.tryParse(expiresAtText);
    if (expiresAt == null) {
      return null;
    }

    return AppAnnouncement(
      uuid: uuid,
      content: content,
      expiresAt: expiresAt.toUtc(),
      linkUri: linkUri,
    );
  }

  static Uri? _tryParseLinkUri(dynamic raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      return null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }

    return uri;
  }
}

class AppAnnouncementService {
  AppAnnouncementService({
    required this.announcementUrl,
    required this.readConfigSnapshot,
    required this.writeDismissedAnnouncementUuids,
    Future<http.Response> Function(Uri uri)? httpGet,
    DateTime Function()? now,
    void Function(String message)? onLogInfo,
    void Function(String message)? onLogError,
  }) : _httpGet = httpGet ?? http.get,
       _now = now ?? DateTime.now,
       _onLogInfo = onLogInfo,
       _onLogError = onLogError;

  static const String dismissedAnnouncementUuidsKey =
      'dismissedAnnouncementUuids';

  final String announcementUrl;
  final Map<String, dynamic> Function() readConfigSnapshot;
  final void Function(List<String> uuids) writeDismissedAnnouncementUuids;
  final Future<http.Response> Function(Uri uri) _httpGet;
  final DateTime Function() _now;
  final void Function(String message)? _onLogInfo;
  final void Function(String message)? _onLogError;

  final Set<String> _shownInSession = <String>{};

  Future<AppAnnouncement?> fetchActiveAnnouncement() async {
    try {
      _logInfo('Fetching announcement from $announcementUrl');
      final response = await _httpGet(
        Uri.parse(announcementUrl),
      ).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        _logInfo(
          'Announcement request skipped with HTTP ${response.statusCode}',
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      final announcement = AppAnnouncement.tryParse(decoded);
      if (announcement == null) {
        _logInfo('Announcement payload is missing required fields.');
        return null;
      }
      if (isExpired(announcement)) {
        _logInfo('Announcement ${announcement.uuid} is already expired.');
        return null;
      }
      if (isDismissed(announcement.uuid)) {
        _logInfo('Announcement ${announcement.uuid} was dismissed before.');
        return null;
      }
      return announcement;
    } catch (e) {
      _logError('Failed to fetch announcement: $e');
      return null;
    }
  }

  bool isExpired(AppAnnouncement announcement) {
    return !_now().toUtc().isBefore(announcement.expiresAt);
  }

  bool isDismissed(String uuid) {
    return dismissedAnnouncementUuids.contains(uuid);
  }

  bool hasShownInSession(String uuid) {
    return _shownInSession.contains(uuid);
  }

  void markShownInSession(String uuid) {
    final normalized = uuid.trim();
    if (normalized.isEmpty) {
      return;
    }
    _shownInSession.add(normalized);
  }

  void dismissAnnouncement(String uuid) {
    final normalized = uuid.trim();
    if (normalized.isEmpty) {
      return;
    }

    final values = <String>{...dismissedAnnouncementUuids, normalized}.toList()
      ..sort();
    writeDismissedAnnouncementUuids(values);
  }

  List<String> get dismissedAnnouncementUuids {
    final raw = readConfigSnapshot()[dismissedAnnouncementUuidsKey];
    if (raw is! List) {
      return const <String>[];
    }

    final values = <String>{};
    for (final item in raw) {
      final value = item?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        values.add(value);
      }
    }

    final sorted = values.toList()..sort();
    return sorted;
  }

  void _logInfo(String message) {
    _onLogInfo?.call(message);
  }

  void _logError(String message) {
    _onLogError?.call(message);
  }
}
