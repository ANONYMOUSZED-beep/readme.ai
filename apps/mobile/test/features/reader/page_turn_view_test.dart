import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/presentation/widgets/page_turn_view.dart';

Widget _app({bool disableAnimations = false, int initialPage = 0}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: PageTurnView(
          itemCount: 3,
          initialPage: initialPage,
          itemBuilder: (context, index) =>
              Center(child: Text('Page ${index + 1}')),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('swiping turns forward and explicit control turns back', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app());

    expect(find.text('Page 1'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Page 1 of 3',
      ),
      findsOneWidget,
    );

    final pageRect = tester.getRect(find.byType(PageTurnView));
    await tester.dragFrom(
      Offset(pageRect.right - 24, pageRect.top + 96),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('arrow keys turn pages without requiring touch input', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
  });

  testWidgets('reduced motion changes pages without a perspective transition', (
    tester,
  ) async {
    await tester.pumpWidget(_app(disableAnimations: true));

    await tester.tap(find.byTooltip('Next page'));
    await tester.pump();

    expect(find.text('Page 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('page-turn-perspective')), findsNothing);
  });

  testWidgets('reduced motion preserves edge-swipe navigation', (tester) async {
    await tester.pumpWidget(_app(disableAnimations: true));
    final rect = tester.getRect(find.byType(PageTurnView));

    await tester.dragFrom(
      Offset(rect.right - 15, rect.top + 96),
      const Offset(-500, 0),
    );
    await tester.pump();

    expect(find.text('Page 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('page-turn-perspective')), findsNothing);
  });

  testWidgets('external anchor changes synchronize the visible page', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    expect(find.text('Page 1'), findsOneWidget);

    await tester.pumpWidget(_app(initialPage: 2));
    await tester.pump();

    expect(find.text('Page 3'), findsOneWidget);
  });

  testWidgets('a text-area drag does not steal selection gestures', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    final rect = tester.getRect(find.byType(PageTurnView));

    await tester.dragFrom(rect.center, const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsOneWidget);
  });

  testWidgets('edge drag region stays inside the non-text gutter', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    final rect = tester.getRect(find.byType(PageTurnView));

    await tester.dragFrom(
      Offset(rect.right - 50, rect.top + 96),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsOneWidget);
  });

  testWidgets('edge drag regions remain disjoint in narrow layouts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(50, 200));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageTurnView(
            itemCount: 3,
            itemBuilder: (context, index) => Text('Page ${index + 1}'),
          ),
        ),
      ),
    );

    final left = tester.getRect(find.byKey(const ValueKey('page-edge-left')));
    final right = tester.getRect(find.byKey(const ValueKey('page-edge-right')));
    expect(left.right, lessThanOrEqualTo(right.left));
    expect(left.width, 25);
    expect(right.width, 25);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('a page turn survives the item count growing mid-turn', (
    tester,
  ) async {
    // The reader paginates incrementally, so `itemCount` grows while the
    // document is still being measured. A count change arriving during a turn
    // must not cancel it: on a long book that silently swallows the reader's
    // tap and the page never changes.
    final turns = <int>[];
    Widget app(int itemCount) => MaterialApp(
      home: Scaffold(
        body: PageTurnView(
          itemCount: itemCount,
          onPageChanged: turns.add,
          itemBuilder: (context, index) => Text('Page ${index + 1}'),
        ),
      ),
    );

    await tester.pumpWidget(app(3));
    await tester.tap(find.byTooltip('Next page'));
    await tester.pump(const Duration(milliseconds: 120));

    // Measurement completes another chunk while the turn is still animating.
    await tester.pumpWidget(app(9));
    await tester.pumpAndSettle();

    expect(turns, [1], reason: 'the turn was cancelled by the count change');
    expect(find.text('Page 2'), findsOneWidget);
  });

  testWidgets('growing the item count leaves the resting page alone', (
    tester,
  ) async {
    Widget app(int itemCount) => MaterialApp(
      home: Scaffold(
        body: PageTurnView(
          itemCount: itemCount,
          initialPage: 1,
          itemBuilder: (context, index) => Text('Page ${index + 1}'),
        ),
      ),
    );

    await tester.pumpWidget(app(3));
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 3'), findsOneWidget);

    await tester.pumpWidget(app(40));
    await tester.pumpAndSettle();
    expect(find.text('Page 3'), findsOneWidget);
  });

  testWidgets('a shrinking item count clamps the visible page', (tester) async {
    Widget app(int itemCount) => MaterialApp(
      home: Scaffold(
        body: PageTurnView(
          itemCount: itemCount,
          itemBuilder: (context, index) => Text('Page ${index + 1}'),
        ),
      ),
    );

    await tester.pumpWidget(app(6));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Page 3'), findsOneWidget);

    // Re-pagination can replace the measured set with a shorter one.
    await tester.pumpWidget(app(2));
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);
  });

  testWidgets('navigation is a no-op at first and last page boundaries', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);

    await tester.pumpWidget(_app(initialPage: 2));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Page 3'), findsOneWidget);
  });
}
