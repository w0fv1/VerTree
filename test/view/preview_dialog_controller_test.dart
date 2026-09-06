import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/view/module/preview_dialog_controller.dart';

class TrackedPreview extends StatefulWidget {
  const TrackedPreview(this.name, this.events, {super.key});
  final String name;
  final List<String> events;

  @override
  State<TrackedPreview> createState() => _TrackedPreviewState();
}

class _TrackedPreviewState extends State<TrackedPreview> {
  @override
  void initState() {
    super.initState();
    widget.events.add('open ${widget.name}');
  }

  @override
  void dispose() {
    widget.events.add('close ${widget.name}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(child: Text(widget.name));
}

void main() {
  late PreviewDialogController previews;
  late GlobalKey<NavigatorState> navigator;
  late BuildContext context;
  late List<String> events;

  Future<void> mount(WidgetTester tester) async {
    previews = PreviewDialogController();
    navigator = GlobalKey<NavigatorState>();
    events = [];
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold(body: Text('home'));
          },
        ),
      ),
    );
  }

  Future<void> open(String name) =>
      previews.show(context, builder: (_) => TrackedPreview(name, events));

  testWidgets(
    'replaces the previous preview and disposes it before mounting the next',
    (tester) async {
      await mount(tester);
      final first = open('first');
      await tester.pumpAndSettle();
      final second = open('second');
      await tester.pumpAndSettle();
      await first;
      expect(find.text('first', skipOffstage: false), findsNothing);
      expect(find.text('second'), findsOneWidget);
      expect(events, ['open first', 'close first', 'open second']);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await second;
      expect(find.byType(Dialog, skipOffstage: false), findsNothing);
      expect(events.last, 'close second');
      final reopened = open('third');
      await tester.pumpAndSettle();
      expect(find.text('third'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await reopened;
    },
  );

  testWidgets('rapid requests keep only the latest file', (tester) async {
    await mount(tester);
    final first = open('first');
    await tester.pumpAndSettle();
    final second = open('second');
    final third = open('third');
    await tester.pumpAndSettle();
    await Future.wait([first, second]);
    expect(find.byType(Dialog, skipOffstage: false), findsOneWidget);
    expect(find.text('third'), findsOneWidget);
    expect(events, ['open first', 'close first', 'open third']);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await third;
  });

  testWidgets('coalesces requests before the first preview frame', (tester) async {
    await mount(tester);
    final first = open('first');
    final second = open('second');
    final third = open('third');
    await tester.pumpAndSettle();
    await Future.wait([first, second]);
    expect(find.byType(Dialog, skipOffstage: false), findsOneWidget);
    expect(find.text('third'), findsOneWidget);
    expect(events, ['open third']);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await third;
  });

  testWidgets('waits for a closing preview to leave the overlay', (
    tester,
  ) async {
    await mount(tester);
    final first = open('first');
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 30));
    final second = open('second');
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        find.byType(Dialog, skipOffstage: false).evaluate().length,
        lessThanOrEqualTo(1),
      );
    }
    await first;
    expect(find.text('second'), findsOneWidget);
    expect(events, ['open first', 'close first', 'open second']);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await second;
  });

  testWidgets('removes only the preview when another dialog is on top', (
    tester,
  ) async {
    await mount(tester);
    final first = open('first');
    await tester.pumpAndSettle();
    var otherClosed = false;
    final other = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(title: Text('other')),
    ).then((_) => otherClosed = true);
    await tester.pumpAndSettle();
    final second = open('second');
    await tester.pumpAndSettle();
    await first;
    expect(otherClosed, isFalse);
    expect(find.text('first', skipOffstage: false), findsNothing);
    expect(find.text('second'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await second;
    expect(find.text('other'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await other;
  });

  testWidgets('completes when its navigator is disposed', (tester) async {
    await mount(tester);
    final first = open('first');
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await first;
    expect(events, ['open first', 'close first']);
  });
}
