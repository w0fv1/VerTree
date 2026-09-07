import 'dart:async';

import 'package:flutter/material.dart';

class PreviewDialogController {
  DialogRoute<void>? _route;
  int _request = 0;

  Future<void> close() async {
    ++_request;
    final route = _route;
    if (route == null) return;
    if (route.isActive) route.navigator!.removeRoute(route);
    await route.completed;
    if (identical(_route, route)) _route = null;
  }

  Future<void> show(
    BuildContext context, {
    required WidgetBuilder builder,
  }) async {
    final request = ++_request;
    final navigator = Navigator.of(context, rootNavigator: true);
    final themes = InheritedTheme.capture(from: context, to: navigator.context);
    final previous = _route;
    if (previous != null) {
      if (previous.isActive) previous.navigator!.removeRoute(previous);
      await previous.completed;
    }
    if (request != _request || !navigator.mounted) return;

    final route = DialogRoute<void>(
      context: navigator.context,
      builder: builder,
      themes: themes,
      barrierDismissible: false,
    );
    _route = route;
    try {
      unawaited(navigator.push<void>(route));
      await route.completed;
    } finally {
      if (identical(_route, route)) _route = null;
    }
  }
}
