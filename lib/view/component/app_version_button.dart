import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AppVersionDisplay extends StatefulWidget {
  final String appVersion;
  final String defaultLink;
  final Future<bool> Function() checkNewVersion;
  final Future<String?> Function() getNewVersionDownloadUrl;

  const AppVersionDisplay({
    super.key,
    required this.appVersion,
    required this.defaultLink,
    required this.checkNewVersion,
    required this.getNewVersionDownloadUrl,
  });

  @override
  State<AppVersionDisplay> createState() => _AppVersionDisplayState();
}

class _AppVersionDisplayState extends State<AppVersionDisplay> {
  bool _hasNewVersion = false;
  String? _newVersionDownloadUrl;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        final hasNewVersion = await widget.checkNewVersion();
        if (hasNewVersion) {
          final downloadUrl = await widget.getNewVersionDownloadUrl();
          if (!mounted || downloadUrl == null || downloadUrl.isEmpty) {
            return;
          }

          setState(() {
            _hasNewVersion = true;
            _newVersionDownloadUrl = downloadUrl;
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _openLink() async {
    final url = _hasNewVersion && _newVersionDownloadUrl != null
        ? _newVersionDownloadUrl!
        : widget.defaultLink;
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: _openLink,
      icon: Badge(
        isLabelVisible: _hasNewVersion,
        alignment: Alignment.topRight,
        child: const Icon(Icons.update_rounded, size: 20),
      ),
      label: Text(
        widget.appVersion,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
