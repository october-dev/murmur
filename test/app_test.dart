import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:murmur/src/app.dart';

void main() {
  testWidgets('renders the empty app shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MurmurApp()));

    expect(find.text('Murmur'), findsOneWidget);
  });
}
