import 'package:test/test.dart';
import 'package:vertree/component/app_version_info.dart';

void main() {
  test('creates the displayed version from the package version', () {
    final info = AppVersionInfo.fromPackageVersion(
      packageVersion: '1.2.3-beta',
      releaseApiUrl: 'https://example.com/releases',
    );

    expect(info.currentVersion, 'V1.2.3-beta');
  });

  group('AppVersionInfo.compareVersions', () {
    test('compares stable versions numerically', () {
      expect(
        AppVersionInfo.compareVersions('V0.11.0', '0.10.9'),
        greaterThan(0),
      );
      expect(AppVersionInfo.compareVersions('0.11.0', '0.11.0'), 0);
    });

    test('treats stable versions as newer than prereleases', () {
      expect(
        AppVersionInfo.compareVersions('0.11.0', '0.11.0-alpha1'),
        greaterThan(0),
      );
    });

    test('orders prereleases by suffix number', () {
      expect(
        AppVersionInfo.compareVersions('0.11.0-alpha2', '0.11.0-alpha1'),
        greaterThan(0),
      );
      expect(
        AppVersionInfo.compareVersions('0.11.0-beta1', '0.11.0-alpha9'),
        greaterThan(0),
      );
    });
  });

  group('AppVersionInfo.selectPreferredAsset', () {
    final release = <String, dynamic>{
      'assets': [
        {
          'name': 'vertree-linux-x64-0.11.0-alpha1.tar.gz',
          'browser_download_url': 'https://example.com/linux.tar.gz',
        },
        {
          'name': 'vertree-0.11.0-alpha1-1.x86_64.rpm',
          'browser_download_url': 'https://example.com/linux.rpm',
        },
        {
          'name': 'vertree-linux-x64-0.11.0-alpha1.deb',
          'browser_download_url': 'https://example.com/linux.deb',
        },
        {
          'name': 'vertree-macos-arm64-0.11.0-alpha1.dmg',
          'browser_download_url': 'https://example.com/macos.dmg',
        },
        {
          'name': 'vertree-macos-arm64-0.11.0-alpha1.zip',
          'browser_download_url': 'https://example.com/macos.zip',
        },
        {
          'name': 'vertree-macos-arm64-0.11.0-alpha1-symbols.zip',
          'browser_download_url': 'https://example.com/macos-symbols.zip',
        },
        {
          'name': 'vertree-windows-x64-0.11.0-alpha1-setup.exe',
          'browser_download_url': 'https://example.com/windows.exe',
        },
        {
          'name': 'vertree-windows-x64-0.11.0-alpha1.zip',
          'browser_download_url': 'https://example.com/windows.zip',
        },
        {
          'name': 'vertree-windows-x64-0.11.0-alpha1-symbols.zip',
          'browser_download_url': 'https://example.com/windows-symbols.zip',
        },
      ],
    };

    test('prefers setup exe on Windows', () {
      final asset = AppVersionInfo.selectPreferredAsset(
        release,
        platformOverride: 'windows',
      );

      expect(asset?.name, 'vertree-windows-x64-0.11.0-alpha1-setup.exe');
    });

    test('prefers dmg on macOS', () {
      final asset = AppVersionInfo.selectPreferredAsset(
        release,
        platformOverride: 'macos',
      );

      expect(asset?.name, 'vertree-macos-arm64-0.11.0-alpha1.dmg');
    });

    test(
      'prefers deb for deb distros, tarball for generic Linux and rpm for rpm distros',
      () {
        final genericAsset = AppVersionInfo.selectPreferredAsset(
          release,
          platformOverride: 'linux',
        );
        final debAsset = AppVersionInfo.selectPreferredAsset(
          release,
          platformOverride: 'linux',
          linuxOsReleaseOverride: 'NAME=Ubuntu\nID=ubuntu\nID_LIKE=debian',
        );
        final rpmAsset = AppVersionInfo.selectPreferredAsset(
          release,
          platformOverride: 'linux',
          linuxOsReleaseOverride:
              'NAME=Fedora\nID=fedora\nID_LIKE="fedora rhel"',
        );

        expect(genericAsset?.name, 'vertree-linux-x64-0.11.0-alpha1.tar.gz');
        expect(debAsset?.name, 'vertree-linux-x64-0.11.0-alpha1.deb');
        expect(rpmAsset?.name, 'vertree-0.11.0-alpha1-1.x86_64.rpm');
      },
    );
  });
}
