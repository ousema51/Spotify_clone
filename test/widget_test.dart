import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spotify_clone/main.dart';

void main() {
  testWidgets('App starts and shows a Scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // App should render some widget tree
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
