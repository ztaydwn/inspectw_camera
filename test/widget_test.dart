import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspectw/main.dart';
import 'package:inspectw/services/metadata_service.dart';

void main() {
  testWidgets('HomeScreen shows no projects message initially',
      (WidgetTester tester) async {
    // Initialize the metadata service
    final metadataService = MetadataService();
    await metadataService.init();

    // Build our app and trigger a frame.
    await tester.pumpWidget(InspectWApp(meta: metadataService));

    // Verify that the title is correct.
    expect(find.text('InspectW – Proyectos'), findsOneWidget);

    // Verify that the "no projects" message is shown.
    expect(find.text('Sin proyectos. Crea el primero.'), findsOneWidget);

    // Verify that the FloatingActionButton is present.
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('HomeScreen creates a project', (WidgetTester tester) async {
    // Initialize the metadata service
    final metadataService = MetadataService();
    await metadataService.init();

    // Build our app and trigger a frame.
    await tester.pumpWidget(InspectWApp(meta: metadataService));

    // Tap the '+' icon to open the dialog.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // Enter a project name in the TextField.
    await tester.enterText(find.byType(TextField), 'Test Project');

    // Tap the 'Crear' button.
    await tester.tap(find.text('Crear'));
    await tester.pump();

    // Verify that the new project is listed.
    expect(find.text('Test Project'), findsOneWidget);
  });
}
