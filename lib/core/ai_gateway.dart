import 'dart:convert';
import 'package:http/http.dart' as http;
import 'memory_store.dart';
import 'secure_vault.dart';
import '../models/domain.dart';

class AiGatewayException implements Exception {
  AiGatewayException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiGateway {
  AiGateway({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final SecureVault _vault = SecureVault.instance;

  Future<String> get baseUrl => _vault.read('ai.base_url');
  Future<String> get model => _vault.read('ai.model');

  Future<String> chat({required String system, required String user, String? agentId, double temperature = 0.2}) async {
    final endpoint = (await baseUrl).trim();
    final selectedModel = (await model).trim();
    final masterKey = await _vault.read('ai.owner_key');
    final agentKey = agentId == null ? '' : await _vault.read('ai.agent.$agentId.key');
    final key = agentKey.trim().isNotEmpty ? agentKey.trim() : masterKey.trim();
    if (endpoint.isEmpty) throw AiGatewayException('أدخل عنوان بوابة الذكاء الاصطناعي في الإعدادات أولاً.');
    if (selectedModel.isEmpty) throw AiGatewayException('أدخل اسم النموذج في الإعدادات أولاً.');
    if (key.isEmpty) throw AiGatewayException('لا يوجد مفتاح API للمالك أو لهذا الوكيل.');

    final uri = _completionUri(endpoint);
    http.Response response;
    try {
      response = await _client.post(uri,
        headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'model': selectedModel,
          'temperature': temperature,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
        }),
      ).timeout(const Duration(seconds: 120));
    } catch (e) {
      throw AiGatewayException('تعذر الاتصال ببوابة الذكاء الاصطناعي: $e');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiGatewayException('استجابة API غير ناجحة (${response.statusCode}): ${_trim(response.body, 600)}');
    }
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = payload['choices'] as List?;
      final message = choices?.isNotEmpty == true ? (choices!.first as Map)['message'] : null;
      final content = message is Map ? message['content'] : null;
      if (content is String && content.trim().isNotEmpty) return content.trim();
      if (content is List) {
        final text = content.whereType<Map>().map((e) => e['text']?.toString() ?? '').join('\n').trim();
        if (text.isNotEmpty) return text;
      }
      throw const FormatException('Missing choices[0].message.content');
    } catch (e) {
      throw AiGatewayException('صيغة استجابة API غير متوافقة مع OpenAI Chat Completions: $e');
    }
  }

  Uri _completionUri(String base) {
    final uri = Uri.parse(base);
    if (uri.path.endsWith('/chat/completions')) return uri;
    final normalized = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: '$normalized/chat/completions');
  }

  Future<List<PlanTask>> createPlan(String request, String projectId, MemoryStore memory) async {
    final teamMemory = await memory.contextFor(agentId: 'manager', projectId: projectId);
    final result = await chat(
      agentId: 'manager', temperature: 0.15,
      system: 'أنت المدير الرئيسي في TermiAI-Nexus. حلل طلب تطوير برمجي وحوله إلى خطة عملية متسلسلة. أعد JSON فقط بالشكل {"tasks":[{"id":"t1","title":"...","description":"...","agentId":"architect|developer|qa|security","risk":"low|medium|high"}]}. لا تدّع تنفيذ أي شيء. لا تضع أوامر خطرة. استخدم 3 إلى 8 مهام. السياق:\n$teamMemory',
      user: request,
    );
    final decoded = _decodeJson(result);
    final items = (decoded['tasks'] as List?) ?? const [];
    final tasks = items.whereType<Map>().map((e) => PlanTask.fromJson(Map<String, dynamic>.from(e))).take(8).map((task) {
      const allowedAgents = {'architect', 'developer', 'qa', 'security'};
      const allowedRisks = {'low', 'medium', 'high'};
      return PlanTask(
        id: task.id,
        title: task.title,
        description: task.description,
        agentId: allowedAgents.contains(task.agentId) ? task.agentId : 'developer',
        risk: allowedRisks.contains(task.risk) ? task.risk : 'medium',
      );
    }).toList();
    if (tasks.isEmpty) throw AiGatewayException('لم أتمكن من استخراج مهام صالحة من خطة النموذج.');
    return tasks;
  }

  Future<String> executeTask({required String agentId, required String taskTitle, required String taskDescription, required String projectId, required String workspaceContext, required MemoryStore memory}) async {
    final context = await memory.contextFor(agentId: agentId, projectId: projectId);
    return chat(
      agentId: agentId,
      system: 'أنت وكيل متخصص في فريق TermiAI-Nexus. أخرج JSON فقط بالشكل {"summary":"...","files":[{"path":"relative/path","content":"full file content"}],"verification":["..."],"risks":[]}. الملفات نصوص كاملة وليست diff. لا تستخدم مسارات مطلقة ولا .. ولا تنفذ أوامر. إذا لم تكن هناك ملفات مطلوبة أعد files مصفوفة فارغة. لا تختلق نتائج اختبار. السياق:\n$context',
      user: 'المهمة: $taskTitle\nالتفاصيل: $taskDescription\nأنت تعمل داخل مساحة مشروع معزولة. قدّم ملفات كاملة صغيرة ومتماسكة فقط عند الحاجة.\n\n$workspaceContext',
      temperature: 0.15,
    );
  }

  Map<String, dynamic> parseAgentOutput(String raw) => _decodeJson(raw);

  Map<String, dynamic> _decodeJson(String raw) {
    var value = raw.trim();
    final fenced = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$', caseSensitive: false).firstMatch(value);
    if (fenced != null) value = fenced.group(1)!.trim();
    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start >= 0 && end > start) value = value.substring(start, end + 1);
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) throw const FormatException('JSON root must be an object');
    return decoded;
  }

  String _trim(String value, int length) => value.length <= length ? value : '${value.substring(0, length)}…';
  void dispose() => _client.close();
}
