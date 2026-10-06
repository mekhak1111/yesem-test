import 'package:flutter_test/flutter_test.dart';
import 'package:yesem/mobile/mobile_app.dart';

void main() {
  testWidgets('mobile placeholder shows its title', (tester) async {
    await tester.pumpWidget(const MobileApp());
    expect(find.text('YesEm Mobile'), findsOneWidget);
  });
}
