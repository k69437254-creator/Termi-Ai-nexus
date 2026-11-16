// TERMAI_GITHUB_AUTOMATION_UPDATE_20261116_V1
import 'dart:convert';
import 'agent_tool_runtime.dart';
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

  Future<String> chat({required String system, required String user, String? agentId, double temperature = 0.2, bool localEngineOnly = false, int maxTokens = 512, String? requestId}) async {
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
          'maxTokens': maxTokens,
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

  Future<String> describeImage({
    required String base64,
    required String mimeType,
    required String prompt,
    String? agentId,
  }) async {
    if (base64.isEmpty || base64.length > 12 * 1024 * 1024) {
      throw AiGatewayException('حجم الصورة فارغ أو يتجاوز الحد المسموح.');
    }
    if (!const {
      'image/jpeg', 'image/png', 'image/webp', 'image/gif'
    }.contains(mimeType)) {
      throw AiGatewayException('صيغة الصورة غير مدعومة: $mimeType');
    }
    final endpoint = (await baseUrl).trim();
    final selectedModel = (await model).trim();
    if (endpoint.isEmpty || _shouldUseEmbeddedEngine(endpoint)) {
      throw AiGatewayException(
        'فهم الصور يحتاج بوابة خارجية ونموذجاً متعدد الوسائط. محرك Spark المحلي الحالي نصّي فقط.',
      );
    }
    if (selectedModel.isEmpty) throw AiGatewayException('أدخل اسم نموذج Vision في الإعدادات.');
    final masterKey = await _vault.read('ai.owner_key');
    final agentKey = agentId == null ? '' : await _vault.read('ai.agent.$agentId.key');
    final key = agentKey.trim().isNotEmpty ? agentKey.trim() : masterKey.trim();
    if (key.isEmpty) throw AiGatewayException('لا يوجد مفتاح API للبوابة الخارجية.');

    http.Response response;
    try {
      response = await _client.post(
        _completionUri(endpoint),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'model': selectedModel,
          'temperature': 0.1,
          'messages': [
            {'role': 'system', 'content': 'حلل الصورة بدقة. ميّز بين ما يظهر بوضوح وما لا يمكن الجزم به. لا تخمّن النصوص غير المقروءة.'},
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {'type': 'image_url', 'image_url': {'url': 'data:$mimeType;base64,$base64'}},
              ],
            },
          ],
        }),
      ).timeout(const Duration(seconds: 90));
    } catch (error) {
      throw AiGatewayException('تعذر إرسال الصورة إلى نموذج Vision: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiGatewayException('استجابة Vision غير ناجحة (${response.statusCode}): ${_trim(response.body, 500)}');
    }
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = payload['choices'] as List?;
      final message = choices?.isNotEmpty == true ? (choices!.first as Map)['message'] : null;
      final content = message is Map ? message['content'] : null;
      if (content is String && content.trim().isNotEmpty) return content.trim();
      if (content is List) {
        final value = content.whereType<Map>().map((item) => item['text']?.toString() ?? '').join('\n').trim();
        if (value.isNotEmpty) return value;
      }
      throw const FormatException('Missing vision response content.');
    } catch (error) {
      throw AiGatewayException('صيغة استجابة Vision غير متوافقة: $error');
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

  Future<List<PlanTask>> createPlan(String request, String projectId, MemoryStore memory, {String? requestId}) async {
    final teamMemory = await memory.contextFor(agentId: 'manager', projectId: projectId);
    const system = '''أنت المدير الرئيسي في TermiAI-Nexus.
حوّل طلب المستخدم إلى خطة تنفيذ عملية ومتسلسلة من 3 إلى 8 مهام. أعد JSON فقط بالشكل {"tasks":[{"id":"t1","title":"...","description":"...","agentId":"architect|developer|qa|security","risk":"low|medium|high"}]}.
يجب أن تتضمن الخطة معماريًا عند الحاجة، ومهمة مطوّر واحدة على الأقل، ومهمة QA أخيرة دائمًا. يجب أن تنشئ مهام التطوير الاختبارات اللازمة قبل بدء QA. مهمة QA هي بوابة التسليم: تفحص ملفات واختبارات المهام السابقة وتشغّل تحققاً حقيقياً عبر run_command كآخر عملية أدوات، ثم تعيد نتائج التنفيذ الفعلية دون كتابة أي ملف. يتولى المنسّق إنشاء docs/QA_REPORT.md تلقائياً بعد التحقق من الأدلة. لا تضع QA قبل آخر مهمة. وزّع العمل على تخصصات الوكلاء ولا تكرر المهام. اجعل كل مهمة تنتج ملفات فعلية عند الحاجة، ولا تدّع التنفيذ أو نجاح اختبار لم يُشغّل. لا تطلب أوامر shell مركّبة ولا عمليات حذف أو نشر/رفع.''' ;
    final firstResponse = await chat(
      agentId: 'manager',
      temperature: 0.1,
      localEngineOnly: true,
      maxTokens: 1536,
      requestId: requestId == null ? null : '$requestId-plan-1',
      system: '$system\nسياق الفريق:\n$teamMemory',
      user: request,
    );
    try {
      return parseProjectPlanResponse(firstResponse);
    } on FormatException catch (firstError) {
      final retryResponse = await chat(
        agentId: 'manager',
        temperature: 0.05,
        localEngineOnly: true,
        maxTokens: 1536,
        requestId: requestId == null ? null : '$requestId-plan-2',
        system: '$system\nالاستجابة السابقة رُفضت بسبب: ${firstError.message}. أعد بناء JSON صحيحاً ومكتملاً، ولا تكرر الخطأ.',
        user: 'طلب المستخدم:\n$request\n\nالاستجابة السابقة التي تحتاج إلى تصحيح:\n${_trim(firstResponse, 1800)}',
      );
      try {
        return parseProjectPlanResponse(retryResponse);
      } on FormatException catch (retryError) {
        throw AiGatewayException(
          'تعذر إعداد خطة صالحة بعد محاولتين. سبب الرفض الأول: ${firstError.message}. سبب الرفض الثاني: ${retryError.message}.',
        );
      }
    }
  }

  /// Parses and validates the manager's project plan independently of the AI engine.
  /// Exposed so the exact response contract can be covered by unit tests.
  List<PlanTask> parseProjectPlanResponse(String raw) {
    final decoded = _decodeJson(raw);
    final items = decoded['tasks'];
    if (items is! List || items.length < 3 || items.length > 8) {
      throw const FormatException('Project plan must contain between 3 and 8 tasks.');
    }

    const allowedAgents = {'architect', 'developer', 'qa', 'security'};
    const allowedRisks = {'low', 'medium', 'high'};
    const requiredFields = ['id', 'title', 'description', 'agentId', 'risk'];
    final seenIds = <String>{};
    final tasks = <PlanTask>[];

    for (final item in items) {
      if (item is! Map) {
        throw const FormatException('Every project task must be a JSON object.');
      }
      final data = Map<String, dynamic>.from(item);
      for (final field in requiredFields) {
        final value = data[field];
        if (value is! String || value.trim().isEmpty) {
          throw FormatException('Project task field $field is missing or empty.');
        }
      }

      final id = (data['id'] as String).trim();
      final title = (data['title'] as String).trim();
      final description = (data['description'] as String).trim();
      final agentId = (data['agentId'] as String).trim();
      final risk = (data['risk'] as String).trim();

      if (!allowedAgents.contains(agentId)) {
        throw const FormatException('Project task has an unsupported agentId.');
      }
      if (!allowedRisks.contains(risk)) {
        throw const FormatException('Project task has an unsupported risk value.');
      }
      if (!seenIds.add(id)) {
        throw FormatException('Project plan contains duplicate task id: $id');
      }

      tasks.add(PlanTask(
        id: id,
        title: title,
        description: description,
        agentId: agentId,
        risk: risk,
      ));
    }
    if (!tasks.any((task) => task.agentId == 'developer')) {
      throw const FormatException('Project plan must include a developer task.');
    }
    if (!tasks.any((task) => task.agentId == 'qa') || tasks.last.agentId != 'qa') {
      throw const FormatException('Project plan must end with a QA verification task.');
    }
    return tasks;
  }

  Future<String> executeTask({
    required String agentId,
    required String taskTitle,
    required String taskDescription,
    required String projectId,
    required String workspaceContext,
    required MemoryStore memory,
    required String requestId,
    required AgentToolRuntime toolRuntime,
  }) async {
    final context = _trim(
      await memory.contextFor(agentId: agentId, projectId: projectId),
      4000,
    );
    final roleInstructions = switch (agentId) {
      'architect' => 'دورك المعماري: اقرأ بنية المشروع أولاً، حدّد العقود والاعتماديات ونقاط الدخول، واكتب وثيقة التصميم والواجهات بين الوحدات. لا تنفذ تغييرات خارج نطاق التصميم.',
      'developer' => 'دورك المطوّر: نفّذ المطلوب فعلياً في ملفات المصدر، حافظ على أسلوب المشروع، أضف الاعتماديات الضرورية إلى ملفات تعريفها فقط، واكتب كوداً مترابطاً لا ملفات شكلية أو TODOs بديلة.',
      'qa' => 'دورك مهندس الجودة وبوابة التسليم الأخيرة: افحص بنية Android وملفات المشروع والأسرار عبر inspect_project. لا تشترط وجود Flutter SDK داخل الهاتف؛ الاختبارات والتحليل وتجميع APK مسؤولية GitHub Actions بعد الرفع. لا تنشئ أو تعدّل أي ملف ولا تستخدم write_file_chunk. اجعل آخر استدعاء أداة أمراً للتحقق. أعد JSON نهائياً يتضمن summary و stagedFiles فارغة و verification و risks. لا تعتبر وجود اختبار أو اقتراح فحص دليلاً على النجاح. لا تدّع نجاحاً إذا كانت الأداة غير متاحة أو فشل الأمر؛ اذكر ذلك بوضوح. المنسّق سينشئ تقرير QA بعد استلام أدلتك الفعلية.',
      'security' => 'دورك مهندس الأمن: افحص الصلاحيات ومسارات الملفات والأسرار والاعتماديات والإعدادات، أصلح المخاطر داخل نطاق المهمة، ولا تنفذ حذفاً أو نشرًا أو git push أو تغييرات صلاحيات خارجية.',
      _ => 'نفّذ المهمة ضمن الدور المحدد ولا تدّع تنفيذ شيء لم تنفذه.',
    };
    final availableTools = agentId == 'qa'
        ? 'list_files، search_files، read_file، inspect_project'
        : 'list_files، search_files، read_file، write_file_chunk، run_command';
    final roleToolInstructions = agentId == 'qa'
        ? 'أنت وكيل QA للقراءة والتحقق فقط. لا تكتب ملفات ولا تطلب staging. نفّذ inspect_project كآخر استدعاء أداة، وتأكد من وجود بنية Android الأساسية وعدم وجود ملفات أسرار محظورة. لا تدّع أن الاختبارات أو البناء نجحت محلياً؛ GitHub Actions هو الذي يثبت ذلك بعد النشر. أعد JSON فقط بالشكل {"summary":"...","stagedFiles":[],"verification":["..."],"risks":[]}، ولا تضع ملفات legacy في files.'
        : 'استخدم list_files/search_files/read_file لفهم الملفات قبل تعديلها. أنشئ الملفات عبر write_file_chunk بالشكل {"tool_call":{"name":"write_file_chunk","arguments":{"path":"lib/example.dart","content":"محتوى الملف أو جزء منه","mode":"create|append"}}}. استخدم create لأول جزء ثم append للبقية. اجعل كل جزء نحو 6 KB أو أقل. بعد إنهاء الملفات أعد JSON فقط بالشكل {"summary":"...","stagedFiles":["relative/path"],"verification":["..."],"risks":[]} وأدرج كل المسارات التي كتبتها.';
    final system = '''أنت وكيل متخصص في TermiAI-Nexus.
$roleInstructions
الأدوات المتاحة لهذا الدور فقط: $availableTools.
$roleToolInstructions
تشغيل الأوامر يتم داخل Ubuntu/PRoot وبوسائط argv منفصلة، وليس داخل Android host. لا تفترض أن Flutter SDK أو Android SDK مثبت داخل الضيف؛ بوابة QA تستخدم inspect_project، والبناء الحقيقي يجري في GitHub Actions. استدعاء run_command بالشكل {"tool_call":{"name":"run_command","arguments":{"command":"flutter","args":["test"],"workingDirectory":"."}}}. لا تستخدم bash -c أو sh -c أو pipes أو أوامر حذف أو git push/commit/reset/clean أو عمليات GitHub الكتابية. عند تعذر أمر، اقرأ الخطأ ولا تزعم نجاحه.
لا تضع نصاً خارج JSON ولا تختلق نتائج اختبار.''';
    final baseConversation = 'سياق الذاكرة:\n$context\n\nالمهمة: $taskTitle\n$taskDescription\n\nسياق المشروع الحالي:\n$workspaceContext';
    var conversation = baseConversation;
    final toolHistory = <String>[];
    const maxToolCalls = 64;
    for (var call = 0; call < maxToolCalls; call++) {
      final raw = await chat(
        agentId: agentId,
        localEngineOnly: true,
        system: system,
        user: conversation,
        temperature: 0.12,
        maxTokens: 2048,
        requestId: requestId,
      );
      final decoded = _decodeJson(raw);
      final toolCall = decoded['tool_call'];
      if (toolCall == null) {
        parseAgentOutput(raw, allowEmptyStagedFiles: agentId == 'qa');
        return raw;
      }
      if (toolCall is! Map ||
          toolCall['name'] is! String ||
          toolCall['arguments'] is! Map) {
        throw const FormatException('صيغة استدعاء الأداة غير صالحة.');
      }
      final result = await toolRuntime.execute(
        toolCall['name'] as String,
        Map<String, dynamic>.from(toolCall['arguments'] as Map),
      );
      toolHistory.add(jsonEncode(result));
      if (toolHistory.length > 8) toolHistory.removeAt(0);
      conversation = '$baseConversation\n\nآخر نتائج الأدوات (الأقدم محذوفة لتثبيت حجم السياق):\n${toolHistory.join('\n')}\n\nملفات staging الحالية: ${jsonEncode(toolRuntime.stagedPaths)}\nتابع التنفيذ اعتماداً على النتائج الفعلية، ثم أعد JSON النهائي مع stagedFiles.';
    }
    throw AiGatewayException('تجاوز الوكيل الحد الأقصى لاستدعاءات الأدوات ($maxToolCalls) دون تسليم نهائي.');
  }

  Map<String, dynamic> parseManagerResponse(String raw) {
    final decoded = _decodeJson(raw);
    final type = decoded['type'];

    if (type == 'chat') {
      final reply = decoded['reply'];
      if (reply is! String || reply.trim().isEmpty) {
        throw const FormatException(
          'Manager chat response must contain a non-empty reply.',
        );
      }
      return decoded;
    }

    if (type == 'project') {
      final request = decoded['request'];
      if (request is! String || request.trim().isEmpty) {
        throw const FormatException(
          'Manager project response must contain a non-empty request.',
        );
      }
      return decoded;
    }

    throw const FormatException(
      'Manager response type must be either chat or project.',
    );
  }

  Map<String, dynamic> parseAgentOutput(String raw, {bool allowEmptyStagedFiles = false}) {
    final decoded = _decodeJson(raw);
    final summary = decoded['summary'];
    if (summary is! String || summary.trim().isEmpty) {
      throw const FormatException('Agent output must contain a non-empty summary.');
    }
    final files = decoded['files'];
    final stagedFiles = decoded['stagedFiles'];
    if (files != null && files is! List) {
      throw const FormatException('files must be a list when provided.');
    }
    final hasLegacyFiles = files is List && files.isNotEmpty;
    final validManifest = stagedFiles is List &&
        stagedFiles.every((item) => item is String && item.trim().isNotEmpty) &&
        stagedFiles.toSet().length == stagedFiles.length;
    if (stagedFiles != null && !validManifest) {
      throw const FormatException('stagedFiles must contain unique non-empty paths.');
    }
    if (stagedFiles is List && stagedFiles.isEmpty && !allowEmptyStagedFiles) {
      throw const FormatException('An empty stagedFiles manifest is permitted only for QA.');
    }
    final hasStagedFiles = validManifest &&
        (stagedFiles.isNotEmpty || allowEmptyStagedFiles);
    if (!hasLegacyFiles && !hasStagedFiles) {
      throw const FormatException('Agent output must contain file patches or a valid stagedFiles manifest.');
    }
    if (hasLegacyFiles) {
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
    }
    final verification = decoded['verification'];
    if (verification is! List || verification.any((item) => item is! String || item.trim().isEmpty)) {
      throw const FormatException('Agent verification must be a list of non-empty strings.');
    }
    final risks = decoded['risks'];
    if (risks != null && (risks is! List || risks.any((item) => item is! String || item.trim().isEmpty))) {
      throw const FormatException('Agent risks must be a list of non-empty strings when provided.');
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
