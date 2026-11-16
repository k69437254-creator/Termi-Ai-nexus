// TERMAI_GITHUB_AUTOMATION_UPDATE_20261116_V1
import 'dart:convert';

enum AgentStatus { idle, thinking, working, waiting, error }
enum TaskStatus { pending, running, completed, failed, rolledBack, interrupted }

enum AgentRole { manager, architect, developer, qa, security }

class AgentProfile {
  const AgentProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.description,
    required this.glyph,
  });

  final String id;
  final String name;
  final AgentRole role;
  final String description;
  final String glyph;

  static const defaults = <AgentProfile>[
    AgentProfile(id: 'manager', name: 'المدير الرئيسي', role: AgentRole.manager, description: 'يفهم الطلب ويخطط ويوزّع العمل ويتابع التنفيذ.', glyph: '◈'),
    AgentProfile(id: 'architect', name: 'المهندس المعماري', role: AgentRole.architect, description: 'يصمم البنية والواجهات والعقود بين الوحدات.', glyph: '◇'),
    AgentProfile(id: 'developer', name: 'المطوّر', role: AgentRole.developer, description: 'ينفذ المهام ويقترح ملفات وتعديلات قابلة للمراجعة.', glyph: '⌘'),
    AgentProfile(id: 'qa', name: 'مهندس الجودة', role: AgentRole.qa, description: 'يراجع النتائج ويقترح اختبارات ويتحقق من سلامة المخرجات.', glyph: '✓'),
    AgentProfile(id: 'security', name: 'مهندس الأمن', role: AgentRole.security, description: 'يفحص المخاطر والأسرار والصلاحيات قبل التغييرات الحساسة.', glyph: '⬡'),
  ];
}

class PlanTask {
  PlanTask({required this.id, required this.title, required this.description, required this.agentId, this.risk = 'low'});
  final String id;
  final String title;
  final String description;
  final String agentId;
  final String risk;
  TaskStatus status = TaskStatus.pending;
  String result = '';

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'description': description, 'agentId': agentId,
    'risk': risk, 'status': status.name, 'result': result,
  };

  factory PlanTask.fromJson(Map<String, dynamic> json) {
    final task = PlanTask(
      id: '${json['id'] ?? DateTime.now().microsecondsSinceEpoch}',
      title: '${json['title'] ?? 'مهمة غير معنونة'}',
      description: '${json['description'] ?? ''}',
      agentId: '${json['agentId'] ?? json['agent'] ?? 'developer'}',
      risk: '${json['risk'] ?? 'low'}',
    );
    final savedStatus = json['status'];
    task.status = TaskStatus.values.firstWhere(
      (status) => status.name == savedStatus,
      orElse: () => TaskStatus.pending,
    );
    task.result = '${json['result'] ?? ''}';
    return task;
  }
}

class ProjectRecord {
  ProjectRecord({
    required this.id,
    required this.name,
    required this.request,
    required this.workspacePath,
    required this.createdAt,
    this.tasks = const [],
    this.githubRepository,
    this.githubRepositoryUrl,
    this.githubRunUrl,
    this.githubArtifactUrl,
    this.githubCommitSha,
    this.githubRunId,
    this.deploymentStatus,
    this.deploymentMessage,
    this.deploymentProgress = 0,
    List<String>? executionLog,
  }) : executionLog = executionLog ?? <String>[];
  final String id;
  final String name;
  final String request;
  final String workspacePath;
  final DateTime createdAt;
  final List<PlanTask> tasks;
  String? githubRepository;
  String? githubRepositoryUrl;
  String? githubRunUrl;
  String? githubArtifactUrl;
  String? githubCommitSha;
  int? githubRunId;
  String? deploymentStatus;
  String? deploymentMessage;
  double deploymentProgress;
  final List<String> executionLog;

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'request': request, 'workspacePath': workspacePath,
    'createdAt': createdAt.toIso8601String(),
    'tasks': tasks.map((e) => e.toJson()).toList(),
    'githubRepository': githubRepository,
    'githubRepositoryUrl': githubRepositoryUrl,
    'githubRunUrl': githubRunUrl,
    'githubArtifactUrl': githubArtifactUrl,
    'githubCommitSha': githubCommitSha,
    'githubRunId': githubRunId,
    'deploymentStatus': deploymentStatus,
    'deploymentMessage': deploymentMessage,
    'deploymentProgress': deploymentProgress,
    'executionLog': executionLog,
  };

  factory ProjectRecord.fromJson(Map<String, dynamic> json) => ProjectRecord(
    id: '${json['id']}', name: '${json['name']}', request: '${json['request']}',
    workspacePath: '${json['workspacePath']}',
    createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
    tasks: ((json['tasks'] as List?) ?? const []).whereType<Map>().map((e) => PlanTask.fromJson(Map<String, dynamic>.from(e))).toList(),
    githubRepository: json['githubRepository'] as String?,
    githubRepositoryUrl: json['githubRepositoryUrl'] as String?,
    githubRunUrl: json['githubRunUrl'] as String?,
    githubArtifactUrl: json['githubArtifactUrl'] as String?,
    githubCommitSha: json['githubCommitSha'] as String?,
    githubRunId: (json['githubRunId'] as num?)?.toInt(),
    deploymentStatus: json['deploymentStatus'] as String?,
    deploymentMessage: json['deploymentMessage'] as String?,
    deploymentProgress: (json['deploymentProgress'] as num?)?.toDouble() ?? 0,
    executionLog: ((json['executionLog'] as List?) ?? const []).whereType<String>().toList(),
  );
}

String prettyJson(Object? value) => const JsonEncoder.withIndent('  ').convert(value);
