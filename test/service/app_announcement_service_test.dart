import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:vertree/service/app_announcement_service.dart';

void main() {
  group('AppAnnouncementService', () {
    test('returns an active announcement when payload is valid', () async {
      final config = <String, dynamic>{};
      final service = AppAnnouncementService(
        announcementUrl: 'https://example.com/announcement.json',
        readConfigSnapshot: () => config,
        writeDismissedAnnouncementUuids: (uuids) {
          config[AppAnnouncementService.dismissedAnnouncementUuidsKey] = uuids;
        },
        httpGet: (_) async => http.Response(
          '{"uuid":"hello-1","content":"Hello Vertree","expiresAt":"2099-01-01T00:00:00Z","link":"https://example.com/releases/v0.11.0"}',
          200,
        ),
        now: () => DateTime.utc(2026, 3, 25),
      );

      final announcement = await service.fetchActiveAnnouncement();

      expect(announcement, isNotNull);
      expect(announcement?.uuid, 'hello-1');
      expect(announcement?.content, 'Hello Vertree');
      expect(
        announcement?.linkUri?.toString(),
        'https://example.com/releases/v0.11.0',
      );
    });

    test('ignores expired announcements', () async {
      final service = AppAnnouncementService(
        announcementUrl: 'https://example.com/announcement.json',
        readConfigSnapshot: () => const <String, dynamic>{},
        writeDismissedAnnouncementUuids: (_) {},
        httpGet: (_) async => http.Response(
          '{"uuid":"old-1","content":"Old notice","expiresAt":"2025-01-01T00:00:00Z"}',
          200,
        ),
        now: () => DateTime.utc(2026, 3, 25),
      );

      final announcement = await service.fetchActiveAnnouncement();

      expect(announcement, isNull);
    });

    test('ignores dismissed announcements', () async {
      final service = AppAnnouncementService(
        announcementUrl: 'https://example.com/announcement.json',
        readConfigSnapshot: () => <String, dynamic>{
          AppAnnouncementService.dismissedAnnouncementUuidsKey: <String>[
            'hello-1',
          ],
        },
        writeDismissedAnnouncementUuids: (_) {},
        httpGet: (_) async => http.Response(
          '{"uuid":"hello-1","content":"Hello Vertree","expiresAt":"2099-01-01T00:00:00Z"}',
          200,
        ),
        now: () => DateTime.utc(2026, 3, 25),
      );

      final announcement = await service.fetchActiveAnnouncement();

      expect(announcement, isNull);
    });

    test('stores dismissed announcement uuids without duplicates', () {
      final config = <String, dynamic>{
        AppAnnouncementService.dismissedAnnouncementUuidsKey: <String>['a-1'],
      };
      final service = AppAnnouncementService(
        announcementUrl: 'https://example.com/announcement.json',
        readConfigSnapshot: () => config,
        writeDismissedAnnouncementUuids: (uuids) {
          config[AppAnnouncementService.dismissedAnnouncementUuidsKey] = uuids;
        },
      );

      service.dismissAnnouncement('a-1');
      service.dismissAnnouncement('b-2');

      expect(
        config[AppAnnouncementService.dismissedAnnouncementUuidsKey],
        <String>['a-1', 'b-2'],
      );
    });

    test('ignores invalid announcement link values', () async {
      final service = AppAnnouncementService(
        announcementUrl: 'https://example.com/announcement.json',
        readConfigSnapshot: () => const <String, dynamic>{},
        writeDismissedAnnouncementUuids: (_) {},
        httpGet: (_) async => http.Response(
          '{"uuid":"hello-2","content":"Hello Vertree","expiresAt":"2099-01-01T00:00:00Z","link":"javascript:alert(1)"}',
          200,
        ),
        now: () => DateTime.utc(2026, 3, 25),
      );

      final announcement = await service.fetchActiveAnnouncement();

      expect(announcement, isNotNull);
      expect(announcement?.linkUri, isNull);
    });
  });
}
