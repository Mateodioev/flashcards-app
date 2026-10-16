import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The debug and profile manifests declare INTERNET so `flutter run` always
/// has network, but the release manifest does not inherit it. A release build
/// without this declaration has no network at all and the AI import fails on
/// device with a socket error, despite every test having passed — flutter_test
/// cannot see an Android permission.
void main() {
  test('the release manifest declares INTERNET', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET"'),
      reason: 'without it, release builds have no network at all',
    );
  });
}
