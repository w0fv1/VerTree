import 'package:flutter/material.dart';

import '../../component/brand_slogans.dart';

class HomeSlogan extends StatelessWidget {
  const HomeSlogan({super.key, required this.session, required this.language});

  final BrandSloganSession session;
  final String language;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 440),
    child: Text(
      session.text(language),
      key: const ValueKey('home-slogan'),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
