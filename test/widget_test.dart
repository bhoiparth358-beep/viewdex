import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:viewdex/app/app.dart';

void main() {
  testWidgets('App should render with bottom navigation and home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ViewdexApp()));
    await tester.pumpAndSettle();

    // Verify NavigationBar exists
    expect(find.byType(NavigationBar), findsOneWidget);

    // Verify bottom navigation tabs exist
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Files'), findsWidgets);
    expect(find.text('Search'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
  });
}
