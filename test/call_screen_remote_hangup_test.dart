// Regression: when the remote party ends the call (manager status -> ended),
// the call screen must close instead of sitting on "Connecting...". Local
// hangup must close it exactly once (never popping the screen underneath).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ozone/core/webrtc/webrtc_call_manager.dart';
import 'package:ozone/features/call/call_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<WebRtcCallManager> _pushCall(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final manager = WebRtcCallManager();
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Column(children: [
          const Text('UNDERLYING_SCREEN'),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
              builder: (_) => CallScreen(callManager: manager),
            )),
            child: const Text('open'),
          ),
        ]),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await _settle(tester);
  expect(find.byType(CallScreen), findsOneWidget);
  return manager;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('remote hangup (status ended) closes the call screen', (tester) async {
    final manager = await _pushCall(tester);
    await manager.endCall(); // what the call-doc listener does on remote end
    await _settle(tester);
    expect(find.byType(CallScreen), findsNothing);
    expect(find.text('UNDERLYING_SCREEN'), findsOneWidget);
    manager.dispose();
  });

  testWidgets('local hangup closes the call screen exactly once', (tester) async {
    final manager = await _pushCall(tester);
    await tester.tap(find.byIcon(Icons.call_end_rounded).first);
    await _settle(tester);
    expect(find.byType(CallScreen), findsNothing);
    expect(find.text('UNDERLYING_SCREEN'), findsOneWidget,
        reason: 'must not pop the route beneath the call screen');
    manager.dispose();
  });
}
