import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
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
  static const MethodChannel _embeddedEngine = MethodChannel('termai/aram-engine');

  Future<String> get baseUrl => _vault.read('ai.base_url');
  Future<String> get model => _vault.read('ai.model');

  Future<String> chat({required String system, required String user, String? agentId, double temperature = 0.2, bool localEngineOnly = false, String? requestId}) async {
    final endpoint = (await baseUrl).trim();
    final selectedModel = (await model).trim();

    // Use the in-process Android engine for blank/loopback endpoints. This avoids
    // the previously observed localhost HTTP stall between TermiAI and Aram AI.
    if (localEngineOnly || _shouldUseEmbeddedEngine(endpoint)) {
      try {
        final answer = await _embeddedEngine.invokeMethod<String>('generate', {
          'system': system,
          'user': user,
          'agentId': agentId,
          'temperature': temperature,
          'maxTokens': 512,
          'requestId': requestId ?? const Uuid().v4(),
        });
        if (answer == null || answer.trim().isEmpty) {
          throw AiGatewayException('أعاد محرك Aram AI إجابة فارغة.');
        }
        return answer.trim();
      } on PlatformException catch (error) {
        throw AiGatewayException(error.message ?? 'تعذر تشغيل محرك Aram AI الداخلي (${error.code}).');
      } catch (error) {
        throw AiGatewayException('تعذر الاتصال بمحرك Aram AI الداخلي: $error');
      }
    }

    // Preserve support for a user-configured remote OpenAI-compatible gateway.
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
    } catch (error) {
      throw AiGatewayException('تعذر الاتصال ببوابة الذكاء الاصطناعي: $error');
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
    } catch (error) {
      throw AiGatewayException('صيغة استجابة API غير متوافقة مع OpenAI Chat Completions: $error');
    }
  }

  bool _shouldUseEmbeddedEngine(String endpoint) {
    if (endpoint.trim().isEmpty) return true;
    final uri = Uri.tryParse(endpoint);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    final isLoopback = host == '127.0.0.1' || host == 'localhost' || host == '::1';
    // Do not hijack other local developer gateways (for example localhost:8000).
    return isLoopback && (uri.port == 8765 || uri.port == 8766);
  }

  Uri _completionUri(String base) {
    final uri = Uri.parse(base);
    if (uri.path.endsWith('/chat/completions')) return uri;
    final normalized = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: '$normalized/chat/completions');
  }

  Future<bool> cancelGeneration(String requestId) async {
    try {
      return await _embeddedEngine.invokeMethod<bool>(
            'cancelGeneration',
            {'requestId': requestId},
          ) ?? false;
    } on PlatformException catch (error) {
      throw AiGatewayException(
        error.message ?? 'تعذر إلغاء طلب Spark (${error.code}).',
      );
    }
  }

  Future<String> acquireProjectExecutionLease() async {
    try {
      final leaseId = await _embeddedEngine.invokeMethod<String>(
        'acquireExecutionLease',
      );
      if (leaseId == null || leaseId.trim().isEmpty) {
        throw AiGatewayException('لم يُرجع محرك Spark معرف حجز صالحاً.');
      }
      return leaseId;
    } on PlatformException catch (error) {
      throw AiGatewayException(
        error.message ?? 'تعذر حجز محرك Spark (${error.code}).',
      );
    }
  }

  Future<void> releaseProjectExecutionLease(String leaseId) async {
    try {
      await _embeddedEngine.invokeMethod<bool>(
        'releaseExecutionLease',
        {'leaseId': leaseId},
      );
    } on PlatformException catch (error) {
      throw AiGatewayException(
        error.message ?? 'تعذر تحرير حجز محرك Spark (${error.code}).',
      );
    }
  }

  Future<List<PlanTask>> createPlan(String request, String projectId, MemoryStore memory) async {
    final teamMemory = await memory.contextFor(agentId: 'manager', projectId: projectId);
    final result = await chat(
      agentId: 'manager', temperature: 0.15,
      localEngineOnly: true,
      system: 'أنت المدير الرئيسي في TermiAI-Nexus. حلل طلب تطوير برمجي وحوله إلى خطة عملية متسلسلة. أعد JSON فقط بالشكل {"tasks":[{"id":"t1","title":"...","description":"...","agentId":"architect|developer|qa|security","risk":"low|medium|high"}]}. لا تدّع تنفيذ أي شيء. لا تضع أوامر خطرة. استخدم 3 إلى 8 مهام. السياق:\n$teamMemory',
      user: request,
    );
    final decoded = _decodeJson(result);
    final items = decoded['tasks'];
    if (items is! List || items.length < 3 || items.length > 8) {
      throw AiGatewayException('يجب أن تتضمن الخطة من ثلاث إلى ثماني مهام صالحة.');
    }
    final tasks = <PlanTask>[];
    final seenIds = <String>{};
    for (final item in items) {
      if (item is! Map) throw AiGatewayException('تحتوي الخطة على مهمة ليست كائن JSON صالحاً.');
      final data = Map<String, dynamic>.from(item);
      for (final field in const ['id', 'title', 'description', 'agentId', 'risk']) {
        final value = data[field];
        if (value is! String || value.trim().isEmpty) {
          throw AiGatewayException('حقل $field مفقود أو فارغ في إحدى مهام الخطة.');
        }
      }
      const allowedAgents = {'architect', 'developer', 'qa', 'security'};
      const allowedRisks = {'low', 'medium', 'high'};
      if (!allowedAgents.contains(data['agentId'])) {
        throw AiGatewayException('معرّف الوكيل غير صالح في إحدى مهام الخطة.');
      }
      if (!allowedRisks.contains(data['risk'])) {
        throw AiGatewayException('مستوى المخاطر غير صالح في إحدى مهام الخطة.');
      }
      final task = PlanTask.fromJson(data);
      if (!seenIds.add(task.id)) throw AiGatewayException('تحتوي الخطة على معرفات مهام مكررة: ${task.id}');
      tasks.add(PlanTask(
        id: task.id,
        title: task.title,
        description: task.description,
        agentId: task.agentId,
        risk: task.risk,
      ));
    }
    return tasks;
  }

  Future<String> executeTask({required String agentId, required String taskTitle, required String taskDescription, required String projectId, required String workspaceContext, required MemoryStore memory}) async {
    final context = await memory.contextFor(agentId: agentId, projectId: projectId);
    return chat(
      agentId: agentId,
      localEngineOnly: true,
      system: 'أنت وكيل متخصص في فريق TermiAI-Nexus. أخرج JSON فقط بالشكل {"summary":"...","files":[{"path":"relative/path","content":"full file content"}],"verification":["..."],"risks":[]}. الملفات نصوص كاملة وليست diff. لا تستخدم مسارات مطلقة ولا .. ولا تنفذ أوامر. يجب أن تتضمن files ملفاً واحداً على الأقل بتغيير فعلي؛ لا تُعد مصفوفة فارغة أو محتوى مطابقاً لملف قائم. إذا تعذر إجراء تغيير فعلي، اشرح العائق في summary ولا تدّع النجاح. لا تختلق نتائج اختبار. السياق:\n$context',
      user: 'المهمة: $taskTitle\nالتفاصيل: $taskDescription\nأنت تعمل داخل مساحة مشروع معزولة. قدّم ملفات كاملة صغيرة ومتماسكة فقط عند الحاجة.\n\n$workspaceContext',
      temperature: 0.15,
    );
  }

  Map<String, dynamic> parseAgentOutput(String raw) {
    final decoded = _decodeJson(raw);
    final summary = decoded['summary'];
    if (summary is! String || summary.trim().isEmpty) {
      throw const FormatException('Agent output must contain a non-empty summary.');
    }
    final files = decoded['files'];
    if (files is! List || files.isEmpty) {
      throw const FormatException('Agent output must contain at least one file patch.');
    }
    for (final item in files) {
      if (item is! Map) throw const FormatException('Every file patch must be a JSON object.');
      final path = item['path'];
      final content = item['content'];
      if (path is! String || path.trim().isEmpty) {
        throw const FormatException('Every file patch must contain a non-empty path.');
      }
      if (content is! String) {
        throw const FormatException('Every file patch must contain text content.');
      }
    }
    final verification = decoded['verification'];
    if (verification is! List || verification.any((item) => item is! String || item.trim().isEmpty)) {
      throw const FormatException('Agent verification must be a list of non-empty strings.');
    }
    return decoded;
  }

  Map<String, dynamic> _decodeJson(String raw) {
    var value = raw.trim();
    if (value.isEmpty) throw const FormatException('AI response is empty.');
    final fenced = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$', caseSensitive: false).firstMatch(value);
    if (fenced != null) value = fenced.group(1)!.trim();
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) throw const FormatException('JSON root must be an object.');
    return decoded;
  }

  String _trim(String value, int length) => value.length <= length ? value : '${value.substring(0, length)}…';
  void dispose() => _client.close();
}
