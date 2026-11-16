import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/github_service.dart';
import '../core/nexus_theme.dart';
import '../widgets/github_connection_card.dart';

class GitHubScreen extends StatefulWidget {
  const GitHubScreen({super.key});

  @override
  State<GitHubScreen> createState() => _GitHubScreenState();
}

class _GitHubScreenState extends State<GitHubScreen> {
  final GitHubService _github = GitHubService();
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _repos = <Map<String, dynamic>>[];
  final Map<String, List<Map<String, dynamic>>> _workflowRuns = <String, List<Map<String, dynamic>>>{};
  final Set<String> _workflowLoading = <String>{};
  bool _busy = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  int _connectionEpoch = 0;
  String _scope = 'all';
  String _message = 'اربط حساب GitHub لعرض مستودعاتك وإدارة مشاريعك من مساحة واحدة.';
  String _account = '';

  List<Map<String, dynamic>> get _visibleRepos {
    final query = _search.text.trim().toLowerCase();
    return _repos.where((repo) {
      final isPrivate = repo['private'] == true;
      if (_scope == 'private' && !isPrivate) return false;
      if (_scope == 'public' && isPrivate) return false;
      if (query.isEmpty) return true;
      final haystack = '${repo['name'] ?? ''} ${repo['full_name'] ?? ''} ${repo['description'] ?? ''} ${repo['language'] ?? ''}'.toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  @override
  void dispose() {
    _search.dispose();
    _github.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (_busy || _loadingMore) return;
    if (append) {
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _busy = true;
        _message = '';
      });
    }
    final requestedPage = append ? _page + 1 : 1;
    final connectionEpoch = _connectionEpoch;
    try {
      final profile = await _github.authenticatedUser();
      final page = await _github.repositories(page: requestedPage);
      if (!mounted || connectionEpoch != _connectionEpoch) return;
      setState(() {
        _account = profile['login']?.toString() ?? '';
        if (append) {
          _repos = <Map<String, dynamic>>[..._repos, ...page];
        } else {
          _repos = page;
          _workflowRuns.clear();
        }
        _page = requestedPage;
        _hasMore = page.length >= 50;
        _message = 'تمت مزامنة ${_repos.length} مستودعًا من حساب @$_account.';
      });
    } catch (error) {
      if (mounted && connectionEpoch == _connectionEpoch) {
        setState(() => _message = 'تعذرت مزامنة GitHub: $error');
      }
    } finally {
      if (mounted && connectionEpoch == _connectionEpoch) {
        setState(() {
          _busy = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _createRepository() async {
    final name = TextEditingController();
    final description = TextEditingController();
    var privateRepo = true;
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إنشاء مستودع جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'اسم المستودع', hintText: 'my-new-project')),
                const SizedBox(height: 10),
                TextField(controller: description, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'وصف المشروع')),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: privateRepo,
                  onChanged: (value) => setDialogState(() => privateRepo = value),
                  title: const Text('مستودع خاص'),
                  subtitle: const Text('الخصوصية مفعّلة افتراضيًا لحماية المشاريع الجديدة.'),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton.icon(
              onPressed: () {
                final value = name.text.trim();
                if (value.isEmpty || !RegExp(r'^[A-Za-z0-9_.-]{1,100}$').hasMatch(value)) return;
                Navigator.pop(dialogContext, <String, dynamic>{'name': value, 'description': description.text.trim(), 'private': privateRepo});
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('إنشاء المستودع'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    description.dispose();
    if (values == null) return;
    setState(() => _busy = true);
    try {
      final repo = await _github.createRepository(
        name: values['name'] as String,
        description: values['description'] as String,
        isPrivate: values['private'] as bool,
      );
      if (mounted) _showMessage('أُنشئ المستودع ${repo['full_name']} بنجاح.');
    } catch (error) {
      if (mounted) _showMessage('فشل إنشاء المستودع: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await _load();
  }

  Future<void> _createIssue(Map<String, dynamic> repo) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('مهمة جديدة · ${repo['name']}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'عنوان Issue')),
            const SizedBox(height: 9),
            TextField(controller: body, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'التفاصيل والخطوات')),
          ]),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, <String>[title.text.trim(), body.text.trim()]), child: const Text('إنشاء Issue')),
        ],
      ),
    );
    title.dispose();
    body.dispose();
    if (values == null || values.first.isEmpty) return;
    final parts = (repo['full_name'] as String).split('/');
    if (parts.length != 2) return;
    try {
      final issue = await _github.createIssue(owner: parts[0], repo: parts[1], title: values[0], body: values[1]);
      if (mounted) _showMessage('تم إنشاء Issue #${issue['number']} في ${repo['name']}.');
    } catch (error) {
      if (mounted) _showMessage('تعذر إنشاء Issue: $error');
    }
  }

  Future<void> _createPullRequest(Map<String, dynamic> repo) async {
    final title = TextEditingController();
    final head = TextEditingController();
    final base = TextEditingController(text: (repo['default_branch'] ?? 'main').toString());
    final body = TextEditingController();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('طلب دمج · ${repo['name']}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')),
            const SizedBox(height: 8),
            TextField(controller: head, decoration: const InputDecoration(labelText: 'فرع Head')),
            const SizedBox(height: 8),
            TextField(controller: base, decoration: const InputDecoration(labelText: 'فرع Base')),
            const SizedBox(height: 8),
            TextField(controller: body, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'الوصف')),
          ]),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, <String>[title.text.trim(), head.text.trim(), base.text.trim(), body.text.trim()]), child: const Text('فتح Pull Request')),
        ],
      ),
    );
    title.dispose();
    head.dispose();
    base.dispose();
    body.dispose();
    if (values == null || values.first.isEmpty || values[1].isEmpty || values[2].isEmpty) return;
    final parts = (repo['full_name'] as String).split('/');
    if (parts.length != 2) return;
    try {
      final pr = await _github.createPullRequest(owner: parts[0], repo: parts[1], title: values[0], head: values[1], base: values[2], body: values[3]);
      if (mounted) _showMessage('تم فتح Pull Request #${pr['number']} في ${repo['name']}.');
    } catch (error) {
      if (mounted) _showMessage('تعذر فتح Pull Request: $error');
    }
  }

  Future<void> _loadWorkflowRuns(Map<String, dynamic> repo) async {
    final fullName = repo['full_name']?.toString() ?? '';
    if (fullName.isEmpty || _workflowLoading.contains(fullName)) return;
    final parts = fullName.split('/');
    if (parts.length != 2) return;
    setState(() => _workflowLoading.add(fullName));
    try {
      final runs = await _github.workflowRuns(
        owner: parts[0],
        repo: parts[1],
        branch: (repo['default_branch'] ?? 'main').toString(),
      );
      if (mounted) setState(() => _workflowRuns[fullName] = runs.take(5).toList(growable: false));
    } catch (error) {
      if (mounted) _showMessage('تعذر تحميل سجل Actions لهذا المستودع: $error');
    } finally {
      if (mounted) setState(() => _workflowLoading.remove(fullName));
    }
  }

  Future<void> _copyRepositoryUrl(Map<String, dynamic> repo) async {
    final url = repo['html_url']?.toString() ?? '';
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) _showMessage('نُسخ رابط ${repo['full_name']} إلى الحافظة.');
  }

  void _showMessage(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value), behavior: SnackBarBehavior.floating));
  }

  Widget _metric(String label, String value, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 11),
          decoration: BoxDecoration(
            color: NexusPalette.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Column(
            children: <Widget>[
              Icon(icon, color: NexusPalette.primaryLight, size: 17),
              const SizedBox(height: 5),
              Text(value, style: const TextStyle(color: NexusPalette.text, fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.muted, fontSize: 8)),
            ],
          ),
        ),
      );

  String _updatedAt(dynamic raw) {
    final value = DateTime.tryParse(raw?.toString() ?? '');
    if (value == null) return 'غير معروف';
    final local = value.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }

  Widget _repositoryCard(Map<String, dynamic> repo) {
    final fullName = repo['full_name']?.toString() ?? '';
    final isPrivate = repo['private'] == true;
    final runs = _workflowRuns[fullName] ?? const <Map<String, dynamic>>[];
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      color: NexusPalette.card,
      child: ExpansionTile(
        onExpansionChanged: (expanded) {
          if (expanded && !_workflowRuns.containsKey(fullName)) _loadWorkflowRuns(repo);
        },
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: NexusPalette.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(isPrivate ? Icons.lock_outline_rounded : Icons.public_rounded, color: NexusPalette.primaryLight, size: 20),
        ),
        title: Text(repo['name']?.toString() ?? 'مستودع', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900, fontSize: 12)),
        subtitle: Text('$fullName  ·  ${repo['language'] ?? 'لغة غير محددة'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.muted, fontSize: 9)),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _smallTag(isPrivate ? 'خاص' : 'عام', isPrivate ? NexusPalette.warning : NexusPalette.success),
                    const SizedBox(width: 6),
                    _smallTag('الفرع: ${repo['default_branch'] ?? 'main'}', NexusPalette.primaryLight),
                  ],
                ),
                const SizedBox(height: 8),
                Text((repo['description']?.toString().trim().isNotEmpty ?? false) ? repo['description'].toString() : 'لا يوجد وصف لهذا المستودع.', style: const TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.5)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 13,
                  runSpacing: 6,
                  children: <Widget>[
                    _repoMetric(Icons.star_outline_rounded, '${repo['stargazers_count'] ?? 0}'),
                    _repoMetric(Icons.call_split_rounded, '${repo['forks_count'] ?? 0}'),
                    _repoMetric(Icons.update_rounded, _updatedAt(repo['updated_at'])),
                  ],
                ),
                const Divider(height: 20),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    OutlinedButton.icon(onPressed: () => _copyRepositoryUrl(repo), icon: const Icon(Icons.copy_rounded, size: 14), label: const Text('نسخ الرابط')),
                    TextButton.icon(onPressed: () => _createIssue(repo), icon: const Icon(Icons.add_task_rounded, size: 15), label: const Text('Issue')),
                    TextButton.icon(onPressed: () => _createPullRequest(repo), icon: const Icon(Icons.call_merge_rounded, size: 15), label: const Text('Pull Request')),
                    TextButton.icon(onPressed: () => _loadWorkflowRuns(repo), icon: const Icon(Icons.account_tree_outlined, size: 15), label: const Text('سجل Actions')),
                  ],
                ),
                if (_workflowLoading.contains(fullName)) ...<Widget>[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ] else if (runs.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  const Text('أحدث عمليات GitHub Actions', style: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w800, fontSize: 10)),
                  const SizedBox(height: 5),
                  for (final run in runs)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: <Widget>[
                          Icon(_runIcon(run), size: 15, color: _runColor(run)),
                          const SizedBox(width: 7),
                          Expanded(child: Text(run['name']?.toString() ?? run['display_title']?.toString() ?? 'Workflow run', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.muted, fontSize: 9))),
                          Text('${run['status'] ?? ''} · ${run['conclusion'] ?? 'قيد التنفيذ'}', style: TextStyle(color: _runColor(run), fontSize: 8, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ] else if (!_workflowLoading.contains(fullName))
                  const Padding(padding: EdgeInsets.only(top: 8), child: Text('لا توجد عمليات Actions حديثة معروضة لهذا الفرع.', style: TextStyle(color: NexusPalette.subtle, fontSize: 9))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallTag(String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.25))),
        child: Text(value, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w800)),
      );

  Widget _repoMetric(IconData icon, String value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: NexusPalette.subtle),
          const SizedBox(width: 4),
          Text(value, style: const TextStyle(color: NexusPalette.muted, fontSize: 9)),
        ],
      );

  IconData _runIcon(Map<String, dynamic> run) {
    final conclusion = run['conclusion']?.toString();
    if (conclusion == 'success') return Icons.check_circle_rounded;
    if (conclusion == 'failure' || conclusion == 'cancelled' || conclusion == 'timed_out') return Icons.error_rounded;
    return Icons.pending_rounded;
  }

  Color _runColor(Map<String, dynamic> run) {
    final conclusion = run['conclusion']?.toString();
    if (conclusion == 'success') return NexusPalette.success;
    if (conclusion == 'failure' || conclusion == 'cancelled' || conclusion == 'timed_out') return NexusPalette.danger;
    return NexusPalette.warning;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleRepos;
    final privateCount = _repos.where((repo) => repo['private'] == true).length;
    final publicCount = _repos.length - privateCount;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF07101D), Color(0xFF0B1422), Color(0xFF080B17)],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const <Widget>[
                        Text('GITHUB WORKSPACE', style: TextStyle(color: NexusPalette.primaryLight, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                        SizedBox(height: 4),
                        Text('مركز إدارة المشاريع', style: TextStyle(color: NexusPalette.text, fontSize: 19, fontWeight: FontWeight.w900)),
                        SizedBox(height: 3),
                        Text('حسابك ومستودعاتك وسير البناء في مساحة موحدة.', style: TextStyle(color: NexusPalette.muted, fontSize: 10)),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'تحديث المستودعات', onPressed: _busy ? null : () => _load(), icon: const Icon(Icons.refresh_rounded, color: NexusPalette.primaryLight)),
                  const SizedBox(width: 3),
                  FilledButton.tonalIcon(onPressed: _busy ? null : _createRepository, icon: const Icon(Icons.add_rounded, size: 17), label: const Text('جديد')),
                ],
              ),
            ),
            GitHubConnectionCard(
              onConnectionChanged: (connected) {
                if (!mounted) return;
                _connectionEpoch++;
                if (connected) {
                  setState(() {
                    _busy = false;
                    _loadingMore = false;
                  });
                  _load();
                } else {
                  setState(() {
                    _busy = false;
                    _loadingMore = false;
                    _account = '';
                    _repos = <Map<String, dynamic>>[];
                    _workflowRuns.clear();
                    _message = 'فُصل الحساب. اربط حسابًا لمتابعة إدارة المستودعات.';
                    _page = 1;
                    _hasMore = true;
                  });
                }
              },
            ),
            if (_account.isNotEmpty || _repos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
                child: Row(
                  children: <Widget>[
                    _metric('المستودعات', '${_repos.length}', Icons.folder_copy_outlined),
                    const SizedBox(width: 7),
                    _metric('الخاصة', '$privateCount', Icons.lock_outline_rounded),
                    const SizedBox(width: 7),
                    _metric('العامة', '$publicCount', Icons.public_rounded),
                  ],
                ),
              ),
            if (_busy) const Padding(padding: EdgeInsets.symmetric(horizontal: 3), child: LinearProgressIndicator(minHeight: 2)),
            if (_message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 9),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: NexusPalette.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: NexusPalette.primary.withValues(alpha: 0.14))),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.info_outline_rounded, size: 15, color: NexusPalette.primaryLight),
                      const SizedBox(width: 7),
                      Expanded(child: Text(_message, style: const TextStyle(color: NexusPalette.muted, fontSize: 9, height: 1.4))),
                    ],
                  ),
                ),
              ),
            TextField(
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ابحث باسم المستودع أو الوصف أو اللغة…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: () { _search.clear(); setState(() {}); }, icon: const Icon(Icons.close_rounded)),
                isDense: true,
              ),
              controller: _search,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              children: <Widget>[
                ChoiceChip(label: const Text('الكل'), selected: _scope == 'all', onSelected: (_) => setState(() => _scope = 'all')),
                ChoiceChip(label: const Text('الخاصة'), selected: _scope == 'private', onSelected: (_) => setState(() => _scope = 'private')),
                ChoiceChip(label: const Text('العامة'), selected: _scope == 'public', onSelected: (_) => setState(() => _scope = 'public')),
              ],
            ),
            const SizedBox(height: 9),
            if (_busy && _repos.isEmpty)
              const Padding(padding: EdgeInsets.all(26), child: Center(child: CircularProgressIndicator()))
            else if (_repos.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: NexusPalette.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: 0.07))),
                child: Column(
                  children: <Widget>[
                    const Icon(Icons.source_outlined, color: NexusPalette.primaryLight, size: 42),
                    const SizedBox(height: 11),
                    const Text('مساحة المستودعات بانتظار الاتصال', style: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900, fontSize: 13)),
                    const SizedBox(height: 6),
                    const Text('اربط حساب GitHub من بطاقة الحساب أعلاه، ثم ستظهر مشاريعك هنا.', textAlign: TextAlign.center, style: TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.5)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(onPressed: _busy ? null : () => _load(), icon: const Icon(Icons.sync_rounded), label: const Text('مزامنة المستودعات')),
                  ],
                ),
              )
            else if (visible.isEmpty)
              const Padding(padding: EdgeInsets.all(22), child: Center(child: Text('لا توجد نتائج تطابق البحث أو عامل التصفية.', style: TextStyle(color: NexusPalette.muted, fontSize: 10))))
            else ...<Widget>[
              Row(
                children: <Widget>[
                  const Text('مستودعات الحساب', style: TextStyle(color: NexusPalette.text, fontSize: 12, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  Text('${visible.length} معروض', style: const TextStyle(color: NexusPalette.muted, fontSize: 9)),
                ],
              ),
              const SizedBox(height: 7),
              for (final repo in visible) _repositoryCard(repo),
              if (_hasMore && _scope == 'all' && _search.text.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OutlinedButton.icon(
                    onPressed: _loadingMore || _busy ? null : () => _load(append: true),
                    icon: _loadingMore ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more_rounded),
                    label: Text(_loadingMore ? 'جارٍ تحميل المزيد…' : 'تحميل المزيد من المستودعات'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
