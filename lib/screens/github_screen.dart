import 'package:material_ui/material_ui.dart';

import '../core/github_service.dart';
import '../core/nexus_theme.dart';

class GitHubScreen extends StatefulWidget {
  const GitHubScreen({super.key});

  @override
  State<GitHubScreen> createState() => _GitHubScreenState();
}

class _GitHubScreenState extends State<GitHubScreen> {
  final GitHubService _github = GitHubService();
  List<Map<String, dynamic>> _repos = [];
  bool _busy = false;
  String _message = 'اربط حساب GitHub من الإعدادات ثم حدّث قائمة المستودعات.';

  Future<void> _load() async {
    if (_busy) return;
    setState(() { _busy = true; _message = ''; });
    try {
      final repos = await _github.repositories();
      if (mounted) setState(() { _repos = repos; _message = 'تم تحميل ${repos.length} مستودعاً.'; });
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createRepository() async {
    final name = TextEditingController();
    final description = TextEditingController();
    var privateRepo = true;
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إنشاء مستودع'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المستودع')),
            const SizedBox(height: 9),
            TextField(controller: description, decoration: const InputDecoration(labelText: 'الوصف')),
            SwitchListTile(value: privateRepo, onChanged: (value) => setDialogState(() => privateRepo = value), title: const Text('مستودع خاص')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, {'name': name.text.trim(), 'description': description.text.trim(), 'private': privateRepo}), child: const Text('إنشاء')),
          ],
        ),
      ),
    );
    name.dispose();
    description.dispose();
    if (values == null || (values['name'] as String).isEmpty) return;
    setState(() => _busy = true);
    try {
      final repo = await _github.createRepository(name: values['name'] as String, description: values['description'] as String, isPrivate: values['private'] as bool);
      if (mounted) setState(() => _message = 'تم إنشاء ${repo['full_name']}');
      if (mounted) setState(() => _busy = false);
      await _load();
    } catch (error) {
      if (mounted) setState(() { _message = error.toString(); _busy = false; });
    }
  }

  Future<void> _createIssue(Map<String, dynamic> repo) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Issue — ${repo['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')),
          const SizedBox(height: 9),
          TextField(controller: body, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'التفاصيل')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, [title.text.trim(), body.text.trim()]), child: const Text('إنشاء')),
        ],
      ),
    );
    title.dispose();
    body.dispose();
    if (values == null || values.first.isEmpty) return;
    final parts = (repo['full_name'] as String).split('/');
    try {
      final issue = await _github.createIssue(owner: parts.first, repo: parts.last, title: values.first, body: values.last);
      if (mounted) setState(() => _message = 'تم إنشاء Issue #${issue['number']}');
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _createPullRequest(Map<String, dynamic> repo) async {
    final title = TextEditingController();
    final head = TextEditingController();
    final base = TextEditingController(text: (repo['default_branch'] ?? 'main').toString());
    final body = TextEditingController();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pull Request — ${repo['name']}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')),
          const SizedBox(height: 8),
          TextField(controller: head, decoration: const InputDecoration(labelText: 'Head branch')),
          const SizedBox(height: 8),
          TextField(controller: base, decoration: const InputDecoration(labelText: 'Base branch')),
          const SizedBox(height: 8),
          TextField(controller: body, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'الوصف')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, [title.text.trim(), head.text.trim(), base.text.trim(), body.text.trim()]), child: const Text('فتح PR')),
        ],
      ),
    );
    title.dispose();
    head.dispose();
    base.dispose();
    body.dispose();
    if (values == null || values.first.isEmpty || values[1].isEmpty || values[2].isEmpty) return;
    final parts = (repo['full_name'] as String).split('/');
    try {
      final pr = await _github.createPullRequest(owner: parts.first, repo: parts.last, title: values[0], head: values[1], base: values[2], body: values[3]);
      if (mounted) setState(() => _message = 'تم فتح Pull Request #${pr['number']}');
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  @override
  void dispose() {
    _github.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            const Expanded(child: NexusPageHeader(
              title: 'GitHub Workspace',
              subtitle: 'Repositories • Issues • Pull Requests',
              kicker: 'DEVELOPMENT INTEGRATION',
              padding: EdgeInsets.zero,
            )),
            IconButton(tooltip: 'تحديث', onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh_rounded)),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(onPressed: _busy ? null : _createRepository, icon: const Icon(Icons.add_rounded), label: const Text('مستودع')),
          ]),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 3, 15, 9),
            child: NexusGlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              radius: 13,
              blur: 6,
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 15, color: NexusPalette.primaryLight),
                const SizedBox(width: 8),
                Expanded(child: Text(_message, style: const TextStyle(color: NexusPalette.muted, fontSize: 10))),
              ]),
            ),
          ),
        Expanded(
          child: _repos.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const NexusIconTile(Icons.code_rounded, size: 54),
                  const SizedBox(height: 13),
                  const Text('لا توجد مستودعات معروضة', style: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900, fontSize: 14)),
                  const SizedBox(height: 6),
                  const Text('أضف رمز GitHub في الإعدادات ثم حدّث القائمة.', textAlign: TextAlign.center, style: TextStyle(color: NexusPalette.muted, fontSize: 11)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh_rounded), label: const Text('تحديث القائمة')),
                ])))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(13, 2, 13, 22),
                  itemCount: _repos.length,
                  itemBuilder: (context, index) {
                    final repo = _repos[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Card(
                        child: ExpansionTile(
                          leading: NexusIconTile(repo['private'] == true ? Icons.lock_outline_rounded : Icons.public_rounded, size: 38),
                          title: Text('${repo['name']}', style: const TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900, fontSize: 12)),
                          subtitle: Text('${repo['full_name']} • ${repo['language'] ?? 'Unknown'}', style: const TextStyle(color: NexusPalette.muted, fontSize: 9)),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(15, 0, 15, 13),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${repo['description'] ?? 'لا يوجد وصف'}', style: const TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.5)),
                                const SizedBox(height: 7),
                                Wrap(spacing: 7, runSpacing: 6, children: [
                                  TextButton.icon(onPressed: () => _createIssue(repo), icon: const Icon(Icons.add_task_rounded, size: 16), label: const Text('Issue')),
                                  TextButton.icon(onPressed: () => _createPullRequest(repo), icon: const Icon(Icons.call_merge_rounded, size: 16), label: const Text('Pull Request')),
                                ]),
                              ]),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]);
}
