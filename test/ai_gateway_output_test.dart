import 'package:flutter_test/flutter_test.dart';
import 'package:termiai_nexus/core/ai_gateway.dart';

void main() {
  late AiGateway gateway;

  setUp(() {
    gateway = AiGateway();
  });

  tearDown(() {
    gateway.dispose();
  });

  test('accepts a valid execution response and a JSON code fence', () {
    final output = gateway.parseAgentOutput('''
```json
{"summary":"Updated the project","files":[{"path":"lib/example.dart","content":"class Example {}"}],"verification":[]}
```
''');

    expect(output['summary'], 'Updated the project');
    expect(output['files'], hasLength(1));
  });

  test('rejects empty, non-JSON and prose-wrapped JSON responses', () {
    expect(() => gateway.parseAgentOutput('  '), throwsFormatException);
    expect(() => gateway.parseAgentOutput('not json'), throwsFormatException);
    expect(
      () => gateway.parseAgentOutput('Here is the result: {"summary":"x","files":[{"path":"a.txt","content":"x"}],"verification":[]}'),
      throwsFormatException,
    );
  });

  test('rejects empty patches and missing or malformed required fields', () {
    expect(
      () => gateway.parseAgentOutput('{"summary":"done","files":[],"verification":[]}'),
      throwsFormatException,
    );
    expect(
      () => gateway.parseAgentOutput('{"summary":" ","files":[{"path":"a.txt","content":"x"}],"verification":[]}'),
      throwsFormatException,
    );
    expect(
      () => gateway.parseAgentOutput('{"summary":"done","files":[{"path":"a.txt"}],"verification":[]}'),
      throwsFormatException,
    );
    expect(
      () => gateway.parseAgentOutput('{"summary":"done","files":[{"path":"a.txt","content":"x"}]}'),
      throwsFormatException,
    );
  });
}
