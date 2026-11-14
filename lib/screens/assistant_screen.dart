import 'package:material_ui/material_ui.dart';

import '../core/nexus_feature_suite.dart';
import '../core/nexus_theme.dart';
import '../core/project_coordinator.dart';
import '../core/project_execution_manager.dart';
import '../models/domain.dart';
import '../widgets/agent_avatar.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    super.key,
    required this.coordinator,
    required this.executionManager,
    this.onBack,
  });
  final ProjectCoordinator coordinator;
  final ProjectExecutionManager executionManager;
  final VoidCallback? onBack;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _request = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      isUser: false,
      text: 'مرحباً بك في مساحة العمل. اكتب ما تريد بناءه أو تطويره، وسأحلل طلبك وأعرض خطة واضحة قبل أن يبدأ أي وكيل بالتنفيذ.',
    ),
  ];
  String? _pendingProjectId;
  String? _executingProjectId;
  final Set<String> _executedProjects = {};
  bool _planning = false;
  bool _executing = false;
  bool _cancellingExecution = false;
  bool _mediaBusy = false;
  NexusImagePayload? _pendingImage;

  @override
  void initState() {
    super.initState();
    _restoreConversation();
  }

  Future<void> _restoreConversation() async {
    try {
      final saved = await widget.coordinator.memory.managerConversation();
      if (!mounted || saved.isEmpty || _messages.length != 1) return;

      final projects = await widget.coordinator.listProjects();
      final byId = {for (final project in projects) project.id: project};
      final restored = <_ChatMessage>[];
      final restoredExecuted = <String>{};

      for (final item in saved) {
        final role = item['role']?.toString();
        final text = item['text']?.toString() ?? '';
        if (text.isEmpty || (role != 'user' && role != 'assistant')) continue;

        final projectId = item['projectId']?.toString();
        final project = projectId == null ? null : byId[projectId];
        if (project != null &&
            project.tasks.any((task) => task.status != TaskStatus.pending) &&
            !project.tasks.any((task) => task.status == TaskStatus.running)) {
          restoredExecuted.add(project.id);
        }
        restored.add(_ChatMessage(
          isUser: role == 'user',
          text: text,
          project: project,
          isError: item['isError'] == true,
        ));
      }

      if (!mounted || restored.isEmpty || _messages.length != 1) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(restored);
        _pendingProjectId = null;
        _executedProjects.addAll(restoredExecuted);
      });
      _scrollToLatest();
    } catch (_) {
      // Conversation recovery must not block the assistant.
    }
  }

  Future<void> _persistConversation() async {
    try {
      final data = _messages.map((message) => <String, dynamic>{
        'role': message.isUser ? 'user' : 'assistant',
        'text': message.text,
        'projectId': message.project?.id,
        'isError': message.isError,
      }).toList();
      await widget.coordinator.memory.saveManagerConversation(data);
    } catch (_) {
      // Persistence errors must not interrupt a conversation.
    }
  }

  @override
  void dispose() {
    _request.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }


  Future<void> _pickImage() async {
    if (_planning || _executing || _mediaBusy) return;
    setState(() => _mediaBusy = true);
    try {
      final image = await NexusDeviceServices.pickImage();
      if (!mounted || image == null) return;
      setState(() => _pendingImage = image);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إرفاق صورة (${(image.sizeBytes / 1024).round()} KB).')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرفاق الصورة: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  Future<void> _voiceInput() async {
    if (_planning || _executing || _mediaBusy) return;
    setState(() => _mediaBusy = true);
    try {
      final transcript = await NexusDeviceServices.recognizeSpeech();
      if (!mounted || transcript == null) return;
      final previous = _request.text.trim();
      _request.text = previous.isEmpty ? transcript : '$previous\n$transcript';
      _request.selection = TextSelection.collapsed(offset: _request.text.length);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحويل الصوت إلى نص: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  Future<void> _submit() async {
    final selectedImage = _pendingImage;
    final typedPrompt = _request.text.trim();
    if ((typedPrompt.isEmpty && selectedImage == null) || _planning || _executing || _mediaBusy) return;
    final prompt = typedPrompt.isEmpty ? 'حلّل الصورة المرفقة وحدد ما الذي يظهر فيها.' : typedPrompt;

    final previousMessages = _messages
        .where((message) => message.text.trim().isNotEmpty)
        .toList();

    _request.clear();
    setState(() {
      _planning = true;
      _pendingImage = null;
      _pendingProjectId = null;
      _messages.add(_ChatMessage(isUser: true, text: selectedImage == null ? prompt : '$prompt\n[صورة مرفقة]'));
    });
    _persistConversation();
    _scrollToLatest();

    try {
      var requestForManager = prompt;
      if (selectedImage != null) {
        final imageDescription = await widget.coordinator.gateway.describeImage(
          base64: selectedImage.base64,
          mimeType: selectedImage.mimeType,
          prompt: typedPrompt.isEmpty ? 'صف الصورة والعناصر والنصوص الظاهرة فيها.' : typedPrompt,
          agentId: 'manager',
        );
        requestForManager += '\n\nتحليل الصورة المرفقة:\n$imageDescription';
      }
      final history = previousMessages
          .skip(previousMessages.length > 12 ? previousMessages.length - 12 : 0)
          .map((message) =>
              '${message.isUser ? "USER" : "ASSISTANT"}: ${message.text}')
          .join('\n');

      final raw = await widget.coordinator.gateway.chat(
        agentId: 'manager',
        temperature: 0.2,
        system: 'You are the main conversational director of TermiAI-Nexus. '
            'Classify the latest user message using the conversation context. '
            'Return one JSON object only. For normal conversation use '
            '{"type":"chat","reply":"your answer"}. '
            'For a request that clearly asks to create, modify, debug, or build '
            'a software project use '
            '{"type":"project","request":"a clear project request"}. '
            'Do not classify questions, greetings, explanations, or casual '
            'discussion as projects. Reply in the same language as the user. '
            'Do not claim that any task has been executed.',
        user: 'Conversation history:\n$history\nUSER: $requestForManager',
      );

      Map<String, dynamic> result;
      try {
        result = widget.coordinator.gateway.parseAgentOutput(raw);
      } on FormatException {
        result = {};
      }

      final type = result['type']?.toString();
      final projectRequest = result['request']?.toString().trim() ?? '';

      if (type == 'project' && projectRequest.isNotEmpty) {
        final project = await widget.coordinator.prepare(projectRequest);
        if (!mounted) return;

        setState(() {
          _pendingProjectId = project.id;
          _messages.add(_ChatMessage(
            isUser: false,
            text: 'حللت طلبك وحوّلته إلى خطة من ${project.tasks.length} مهام. راجع توزيع العمل أدناه؛ لن يبدأ التنفيذ قبل موافقتك.',
            project: project,
          ));
        });
        _persistConversation();
      } else {
        final reply = type == 'chat'
            ? result['reply']?.toString().trim() ?? ''
            : raw.trim();

        if (reply.isEmpty) {
          throw const FormatException('Empty chat reply');
        }

        if (!mounted) return;
        setState(() {
          _messages.add(_ChatMessage(isUser: false, text: reply));
        });
        _persistConversation();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            isUser: false,
            text: 'تعذر فهم الاستجابة أو إكمال الطلب: $error',
            isError: true,
          ));
        });
        _persistConversation();
      }
    } finally {
      if (mounted) setState(() => _planning = false);
      _scrollToLatest();
    }
  }

  Future<void> _execute(ProjectRecord project) async {
    if (_executing || _pendingProjectId != project.id) return;
    setState(() {
      _executing = true;
      _cancellingExecution = false;
      _executingProjectId = project.id;
      _pendingProjectId = null;
      _messages.add(const _ChatMessage(
        isUser: false,
        text: 'تم اعتماد الخطة. بدأ الفريق تنفيذ المهام بالتسلسل المعتمد، وستظهر تحديثات الحالة داخل بطاقة الخطة.',
      ));
    });
    _persistConversation();
    _scrollToLatest();

    try {
      await widget.executionManager.enqueue(
        project,
        onTaskChanged: (_) {
          if (mounted) {
            setState(() {});
            _persistConversation();
          }
          _scrollToLatest();
        },
      );
      if (mounted) {
        final failed = project.tasks.any((task) => task.status == TaskStatus.rolledBack || task.status == TaskStatus.failed || task.status == TaskStatus.interrupted);
        setState(() {
          _executedProjects.add(project.id);
          _messages.add(_ChatMessage(
            isUser: false,
            text: failed
                ? 'انتهى مسار التنفيذ مع مهمة لم تكتمل. راجع سجل المحاولات ونتيجة المهمة داخل الخطة؛ لم أعتبر وجود الملفات دليلاً على نجاح بناء التطبيق.'
                : 'اكتمل مسار المهام. راجع النتائج والملفات في مساحة المشروع، وتذكّر أن بناء التطبيق وتشغيله يحتاجان تحققاً منفصلاً.',
            isError: failed,
          ));
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _messages.add(_ChatMessage(
              isUser: false,
              text: 'توقف التنفيذ بسبب خطأ: $error',
              isError: true,
            )));
      }
    } finally {
      if (mounted) {
        setState(() {
          _executing = false;
          _cancellingExecution = false;
          _executingProjectId = null;
        });
      }
      _persistConversation();
      _scrollToLatest();
    }
  }

  Future<void> _cancelExecution() async {
    final projectId = _executingProjectId;
    if (projectId == null || _cancellingExecution) return;

    setState(() => _cancellingExecution = true);

    try {
      final accepted = await widget.executionManager.cancel(projectId);
      if (!mounted) return;

      if (accepted) {
        setState(() => _messages.add(const _ChatMessage(
          isUser: false,
          text: 'استلم النظام طلب الإلغاء. يجري إيقاف التوليد والتراجع الآمن عن تغييرات المهمة الحالية؛ ستتحدث حالة المهمة عند انتهاء العملية.',
        )));
      } else {
        setState(() {
          _cancellingExecution = false;
          _messages.add(const _ChatMessage(
            isUser: false,
            text: 'لم تقبل خدمة التنفيذ طلب الإلغاء. ما زالت حالة المشروع قيد التنفيذ.',
            isError: true,
          ));
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _cancellingExecution = false;
          _messages.add(_ChatMessage(
            isUser: false,
            text: 'تعذر إرسال طلب الإلغاء: $error',
            isError: true,
          ));
        });
      }
    }

    _persistConversation();
    _scrollToLatest();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: AlignmentDirectional.topStart,
                          radius: 1.2,
                          colors: [
                            NexusPalette.primary.withValues(alpha: 0.075),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(15, 18, 15, 22),
                  itemCount: _messages.length + (_planning ? 1 : 0) + (_executing ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < _messages.length) {
                      final message = _messages[index];
                      return _MessageBubble(
                        message: message,
                        canApprove: message.project != null && message.project!.id == _pendingProjectId,
                        executing: message.project != null && message.project!.id == _executingProjectId,
                        cancelling: _cancellingExecution &&
                            message.project?.id == _executingProjectId,
                        alreadyExecuted: message.project != null && _executedProjects.contains(message.project!.id),
                        onApprove: message.project == null ? null : () => _execute(message.project!),
                  onCancel: _executing && message.project?.id == _executingProjectId ? _cancelExecution : null,
                      );
                    }
                    return _TypingBubble(executing: _executing);
                  },
                ),
              ],
            ),
          ),
          _buildComposer(),
        ],
      );

  Widget _buildHeader() => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 16, 12),
        decoration: const BoxDecoration(
          color: Color(0xCC0A0F1C),
          border: Border(bottom: BorderSide(color: NexusPalette.border)),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'العودة إلى المقر',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
            AgentAvatar(agent: AgentProfile.defaults.first, size: 46),
            const SizedBox(width: 11),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('المدير الرئيسي', style: TextStyle(color: NexusPalette.text, fontSize: 14, fontWeight: FontWeight.w900)),
                  SizedBox(height: 3),
                  Text('يفهم الطلبات ويخطط ويوزّع العمل', style: TextStyle(color: NexusPalette.muted, fontSize: 10)),
                ],
              ),
            ),
            const NexusStatusPill('جلسة محادثة', icon: Icons.lock_outline_rounded),
          ],
        ),
      );

  Widget _buildComposer() => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
          color: Color(0xE60A0F1C),
          border: Border(top: BorderSide(color: NexusPalette.border)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: _pendingImage == null ? 'إرفاق صورة للتحليل' : 'تغيير الصورة المرفقة',
                onPressed: _planning || _executing || _mediaBusy ? null : _pickImage,
                icon: Icon(Icons.image_outlined, color: _pendingImage == null ? NexusPalette.muted : NexusPalette.primaryLight),
              ),
              IconButton(
                tooltip: 'تحويل الصوت العربي إلى نص',
                onPressed: _planning || _executing || _mediaBusy ? null : _voiceInput,
                icon: const Icon(Icons.mic_none_rounded),
                ),
              Expanded(
                child: TextField(
                  controller: _request,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  enabled: !_planning && !_executing,
                  decoration: InputDecoration(
                    hintText: _executing ? 'الفريق ينفذ الخطة المعتمدة…' : (_pendingImage == null ? 'اكتب رسالتك أو فكرة مشروعك…' : 'الصورة جاهزة للتحليل؛ اكتب طلبك…'),
                    prefixIcon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                    filled: true,
                    fillColor: NexusPalette.elevated.withValues(alpha: 0.92),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: (_planning || _executing)
                      ? null
                      : const LinearGradient(colors: [NexusPalette.primaryLight, NexusPalette.primaryDeep]),
                  color: (_planning || _executing) ? NexusPalette.elevated : null,
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: (_planning || _executing)
                      ? const []
                      : const [BoxShadow(color: Color(0x3300F0FF), blurRadius: 16, offset: Offset(0, 4))],
                ),
                child: IconButton(
                  tooltip: 'إرسال الرسالة',
                  onPressed: _planning || _executing ? null : _submit,
                  color: Colors.white,
                  icon: _planning || _executing
                      ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: NexusPalette.primaryLight))
                      : const Icon(Icons.arrow_upward_rounded, size: 22),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ChatMessage {
  const _ChatMessage({required this.isUser, required this.text, this.project, this.isError = false});
  final bool isUser;
  final String text;
  final ProjectRecord? project;
  final bool isError;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.canApprove,
    required this.executing,
    required this.cancelling,
    required this.alreadyExecuted,
    required this.onApprove,
    this.onCancel,
  });

  final _ChatMessage message;
  final bool canApprove;
  final bool executing;
  final bool cancelling;
  final bool alreadyExecuted;
  final VoidCallback? onApprove;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.88;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Align(
        alignment: isUser ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: isUser ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              if (!isUser)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5, right: 5),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AgentAvatar(agent: AgentProfile.defaults.first, size: 22),
                    SizedBox(width: 6),
                    Text('المدير الرئيسي', style: TextStyle(color: NexusPalette.subtle, fontSize: 9, fontWeight: FontWeight.w800)),
                  ]),
                ),
              if (isUser)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [NexusPalette.purple, Color(0xFF6535A8)]),
                    borderRadius: const BorderRadiusDirectional.only(topStart: Radius.circular(20), topEnd: Radius.circular(20), bottomEnd: Radius.circular(5), bottomStart: Radius.circular(20)),
                    border: Border.all(color: NexusPalette.primaryLight.withValues(alpha: 0.25)),
                    boxShadow: const [BoxShadow(color: Color(0x1FA855F7), blurRadius: 14, offset: Offset(0, 5))],
                  ),
                  child: Text(message.text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5)),
                )
              else
                NexusGlassPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  radius: 20,
                  tint: message.isError ? const Color(0xB3291722) : null,
                  borderColor: message.isError ? NexusPalette.danger.withValues(alpha: 0.35) : null,
                  child: Text(
                    message.text,
                    style: TextStyle(color: message.isError ? NexusPalette.danger : NexusPalette.text, fontSize: 13, height: 1.55),
                  ),
                ),
              if (message.project != null) ...[
                const SizedBox(height: 9),
                _PlanBubble(
                  project: message.project!,
                  canApprove: canApprove,
                  executing: executing,
                  cancelling: cancelling,
                  alreadyExecuted: alreadyExecuted,
                  onApprove: onApprove,
                  onCancel: onCancel,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanBubble extends StatelessWidget {
  const _PlanBubble({required this.project, required this.canApprove, required this.executing, required this.cancelling, required this.alreadyExecuted, required this.onApprove, this.onCancel});
  final ProjectRecord project;
  final bool canApprove;
  final bool executing;
  final bool cancelling;
  final bool alreadyExecuted;
  final VoidCallback? onApprove;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => NexusGlassPanel(
        padding: const EdgeInsets.all(14),
        radius: 20,
        borderColor: NexusPalette.primary.withValues(alpha: 0.36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const NexusIconTile(Icons.account_tree_rounded, size: 36),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('خطة المشروع', style: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900, fontSize: 13)),
                Text('${project.tasks.length} مهام • ${project.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.muted, fontSize: 10)),
              ])),
              NexusStatusPill(
                executing
                    ? 'قيد التنفيذ'
                    : alreadyExecuted
                        ? 'اكتمل المسار'
                        : canApprove
                            ? 'بانتظار الموافقة'
                            : 'خطة محفوظة',
                color: executing
                    ? NexusPalette.warning
                    : alreadyExecuted
                        ? NexusPalette.success
                        : NexusPalette.primaryLight,
                icon: executing
                    ? Icons.sync_rounded
                    : alreadyExecuted
                        ? Icons.check_circle_outline_rounded
                        : Icons.fact_check_outlined,
              ),
            ]),
            const Divider(height: 22),
            ...project.tasks.asMap().entries.map((entry) => _TaskLine(index: entry.key + 1, task: entry.value)),
            const SizedBox(height: 12),
            if (canApprove)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: executing ? null : onApprove,
                  icon: executing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded),
                  label: Text(executing ? 'الفريق ينفذ المهام…' : 'أوافق على الخطة وابدأ التنفيذ'),
                ),
              )
            else if (executing)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: cancelling ? null : onCancel,
                  icon: cancelling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.stop_circle_outlined),
                  label: Text(
                    cancelling ? 'يجري إلغاء التنفيذ…' : 'إلغاء تنفيذ المشروع',
                  ),
                  style: OutlinedButton.styleFrom(foregroundColor: NexusPalette.danger),
                ),
              )
            else if (alreadyExecuted)
              const NexusStatusPill('انتهى التنفيذ', color: NexusPalette.success, icon: Icons.check_circle_outline_rounded)
            else
              const Text('هذه خطة سابقة. تظهر هنا للرجوع إليها دون إعادة تشغيلها.', style: TextStyle(color: NexusPalette.subtle, fontSize: 10)),
          ],
        ),
      );
}

class _TaskLine extends StatelessWidget {
  const _TaskLine({required this.index, required this.task});
  final int index;
  final PlanTask task;

  @override
  Widget build(BuildContext context) {
    final color = switch (task.status) {
      TaskStatus.completed => NexusPalette.success,
      TaskStatus.running => NexusPalette.primaryLight,
      TaskStatus.failed || TaskStatus.rolledBack || TaskStatus.interrupted => NexusPalette.danger,
      _ => NexusPalette.muted,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 25,
          height: 25,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(9)),
          child: task.status == TaskStatus.completed
              ? Icon(Icons.check_rounded, color: color, size: 15)
              : Text('$index', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(task.title, style: const TextStyle(color: NexusPalette.text, fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('${task.agentId}  •  ${task.status.name}  •  مخاطر ${task.risk}', style: TextStyle(color: color, fontSize: 9)),
          if (task.result.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(task.result, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.4)),
          ],
        ])),
      ]),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({required this.executing});
  final bool executing;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 15),
          child: NexusGlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            radius: 18,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 9),
              Text(executing ? 'يتابع الفريق تنفيذ المهام…' : 'أراجع الطلب وأجهّز الخطة…', style: const TextStyle(color: NexusPalette.muted, fontSize: 11)),
            ]),
          ),
        ),
      );
}
