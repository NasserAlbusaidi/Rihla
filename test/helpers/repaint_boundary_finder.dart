import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asserts that every widget matched by [finder] has a [RepaintBoundary] as its
/// **immediate** parent element.
///
/// Checking the immediate parent (not any ancestor) is deliberate: the framework
/// inserts its own `RepaintBoundary`s high in the tree (Navigator, Overlay,
/// scroll viewports), so a plain `find.ancestor(..., matching: RepaintBoundary)`
/// would false-pass even when the widget under test is not wrapped. Pins the
/// #626 compositing boundaries (CoverArt headers, JourneyTicketCard strip).
void expectWrappedInRepaintBoundary(Finder finder, {String? reason}) {
  final elements = finder.evaluate().toList();
  expect(elements, isNotEmpty, reason: 'finder matched no widgets');
  for (final element in elements) {
    Element? parent;
    element.visitAncestorElements((ancestor) {
      parent = ancestor;
      return false; // stop at the immediate parent
    });
    expect(
      parent?.widget,
      isA<RepaintBoundary>(),
      reason: reason ??
          '${element.widget.runtimeType} is not directly wrapped in a '
              'RepaintBoundary (its immediate parent is '
              '${parent?.widget.runtimeType})',
    );
  }
}
