import 'dart:io';

import 'package:drama_tracker/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('drama_tracker_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<Map>('watchlist');
  });

  tearDownAll(() async {
    await Hive.box<Map>('watchlist').close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('App starts and shows login page', (WidgetTester tester) async {
    await tester.pumpWidget(const DramaTrackerApp());
    await tester.pumpAndSettle();
    expect(find.text('欢迎回来'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}
