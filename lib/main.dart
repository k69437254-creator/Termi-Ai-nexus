import 'package:flutter/material.dart';

import 'app/termiai_app.dart';
import 'core/services/project_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TermiaiApp(projectStore: ProjectStore()));
}
