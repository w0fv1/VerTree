import 'dart:async';
import 'dart:io';
import 'package:vertree/component/configer.dart';
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

    test('stores dismissed announcement uuids without duplicates', () async {
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

      await service.dismissAnnouncement('a-1');
      await service.dismissAnnouncement('b-2');

      expect(
        config[AppAnnouncementService.dismissedAnnouncementUuidsKey],
        <String>['a-1', 'b-2'],
      );
    });

    test(
      'concurrent visibility callbacks can claim an announcement only once',
      () async {
        final service = AppAnnouncementService(
          announcementUrl: 'https://example.com/announcement.json',
          readConfigSnapshot: () => {},
          writeDismissedAnnouncementUuids: (_) {},
        );
        final announcement = AppAnnouncement(
          uuid: 'race',
          content: 'Notice',
          expiresAt: DateTime.utc(2099),
        );
        final visibility = Completer<bool>();
        Future<bool> show() async {
          await visibility.future;
          return service.tryClaim(announcement);
        }

        final results = [show(), show(), show()];
        visibility.complete(true);
        expect(
          (await Future.wait(results)).where((claimed) => claimed),
          hasLength(1),
        );
      },
    );

    test(
      'acknowledgement survives a settings reload and allows a new UUID',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'vertree-announcement-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final config = Configer(directoryResolver: () async => dir);
        await config.init();
        final service = AppAnnouncementService(
          announcementUrl: 'https://example.com/announcement.json',
          readConfigSnapshot: config.toJson,
          writeDismissedAnnouncementUuids: (ids) async {
            config.set(
              AppAnnouncementService.dismissedAnnouncementUuidsKey,
              ids,
            );
            await config.flush();
          },
        );
        await service.dismissAnnouncement('read');
        await config.dispose();
        final reloaded = Configer(directoryResolver: () async => dir);
        await reloaded.init();
        final restarted = AppAnnouncementService(
          announcementUrl: 'https://example.com/announcement.json',
          readConfigSnapshot: reloaded.toJson,
          writeDismissedAnnouncementUuids: (_) {},
        );
        expect(
          restarted.tryClaim(
            AppAnnouncement(
              uuid: 'read',
              content: 'Old',
              expiresAt: DateTime.utc(2099),
            ),
          ),
          isFalse,
        );
        expect(
          restarted.tryClaim(
            AppAnnouncement(
              uuid: 'new',
              content: 'New',
              expiresAt: DateTime.utc(2099),
            ),
          ),
          isTrue,
        );
        await reloaded.dispose();
      },
    );

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
