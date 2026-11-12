import 'package:flutter_test/flutter_test.dart';
import 'package:termiai_nexus/app/termiai_app.dart';
import 'package:termiai_nexus/core/services/project_store.dart';

void main() {
  testWidgets('shows the TermiAI-Nexus home screen and navigation', (WidgetTester tester) async {
    await tester.pumpWidget(TermiaiApp(projectStore: ProjectStore()));

    expect(find.text('TermiAI-Nexus'), findsOneWidget);
    expect(find.text('ما الذي تريد بناءه؟'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
  });

  test('stores a project request as a local draft', () {
    final ProjectStore store = ProjectStore();
    final draft = store.addDraft('Build a task management app with login');

    expect(store.projects, hasLength(1));
    expect(draft.request, 'Build a task management app with login');
    expect(draft.title, 'Build a task management app with login');
  });
}
