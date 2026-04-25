import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('android manifest declares scheduled notification receivers', () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml').readAsString();

    expect(
      manifest,
      contains('android.permission.RECEIVE_BOOT_COMPLETED'),
    );
    expect(
      manifest,
      contains('com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver'),
    );
    expect(
      manifest,
      contains('com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver'),
    );
  });
}
