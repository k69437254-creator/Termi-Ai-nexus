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

  test('accepts a project classification response', () {
    final output = gateway.parseManagerResponse(
      '{"type":"project","request":"Build a maps app"}',
    );

    expect(output['type'], 'project');
    expect(output['request'], 'Build a maps app');
  });

  test('accepts a chat classification response and a JSON code fence', () {
    final output = gateway.parseManagerResponse(
      '```json\n{"type":"chat","reply":"Hello"}\n```',
    );

    expect(output['type'], 'chat');
    expect(output['reply'], 'Hello');
  });

  test('rejects malformed manager classification responses', () {
    expect(
      () => gateway.parseManagerResponse(
        '{"type":"project","request":" "}',
      ),
      throwsFormatException,
    );

    expect(
      () => gateway.parseManagerResponse(
        '{"type":"chat","reply":""}',
      ),
      throwsFormatException,
    );

    expect(
      () => gateway.parseManagerResponse('{"type":"unknown"}'),
      throwsFormatException,
    );
  });

  test('accepts a valid three-task project plan and a JSON code fence', () {
    final tasks = gateway.parseProjectPlanResponse('''
```json
{"tasks":[
 {"id":"t1","title":"تحليل الطلب","description":"حدد المتطلبات والهيكل وأنشئ وثيقة التصميم.","agentId":"architect","risk":"low"},
 {"id":"t2","title":"تنفيذ التطبيق","description":"أنشئ ملفات التطبيق المطلوبة وفق التصميم.","agentId":"developer","risk":"medium"},
 {"id":"t3","title":"التحقق","description":"أضف الاختبارات وراجع الملفات الناتجة.","agentId":"qa","risk":"low"}
]}
```
''');

    expect(tasks, hasLength(3));
    expect(tasks.first.agentId, 'architect');
    expect(tasks.last.risk, 'low');
  });

  test('rejects project plans with invalid count, duplicate IDs or invalid agents', () {
    expect(
      () => gateway.parseProjectPlanResponse(
        '{"tasks":[{"id":"t1","title":"A","description":"A","agentId":"developer","risk":"low"}]}',
      ),
      throwsFormatException,
    );

    expect(
      () => gateway.parseProjectPlanResponse('''
{"tasks":[
 {"id":"same","title":"A","description":"A","agentId":"developer","risk":"low"},
 {"id":"same","title":"B","description":"B","agentId":"qa","risk":"low"},
 {"id":"t3","title":"C","description":"C","agentId":"architect","risk":"low"}
]}
'''),
      throwsFormatException,
    );

    expect(
      () => gateway.parseProjectPlanResponse('''
{"tasks":[
 {"id":"t1","title":"A","description":"A","agentId":"manager","risk":"low"},
 {"id":"t2","title":"B","description":"B","agentId":"qa","risk":"low"},
 {"id":"t3","title":"C","description":"C","agentId":"architect","risk":"low"}
]}
'''),
      throwsFormatException,
    );
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
