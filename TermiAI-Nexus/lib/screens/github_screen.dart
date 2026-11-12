import 'package:flutter/material.dart';
import '../core/github_service.dart';

class GitHubScreen extends StatefulWidget {
  const GitHubScreen({super.key});
  @override
  State<GitHubScreen> createState() => _GitHubScreenState();
}

class _GitHubScreenState extends State<GitHubScreen> {
  final GitHubService _github = GitHubService();
  List<Map<String, dynamic>> _repos = [];
  bool _busy = false;
  String _message = 'اربط حساب GitHub من الإعدادات ثم حدّث القائمة.';

  Future<void> _load() async {
    setState(() { _busy = true; _message = ''; });
    try { final repos = await _github.repositories(); if (mounted) setState(() { _repos = repos; _message = 'تم تحميل ${repos.length} مستودعاً.'; }); }
    catch (e) { if (mounted) setState(() => _message = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _createRepository() async {
    final name = TextEditingController();
    final description = TextEditingController();
    var privateRepo = true;
    final values = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(title: const Text('إنشاء مستودع'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المستودع')), const SizedBox(height: 8), TextField(controller: description, decoration: const InputDecoration(labelText: 'الوصف')), SwitchListTile(value: privateRepo, onChanged: (v) => setDialogState(() => privateRepo = v), title: const Text('مستودع خاص'))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, {'name': name.text.trim(), 'description': description.text.trim(), 'private': privateRepo}), child: const Text('إنشاء'))])));
    name.dispose(); description.dispose();
    if (values == null || (values['name'] as String).isEmpty) return;
    setState(() => _busy = true);
    try {
      final repo = await _github.createRepository(name: values['name'] as String, description: values['description'] as String, isPrivate: values['private'] as bool);
      if (mounted) setState(() { _message = 'تم إنشاء ${repo['full_name']}'; });
      await _load();
    } catch (e) { if (mounted) setState(() => _message = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _createIssue(Map<String, dynamic> repo) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final values = await showDialog<List<String>>(context: context, builder: (context) => AlertDialog(title: Text('Issue — ${repo['name']}'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')), const SizedBox(height: 8), TextField(controller: body, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'التفاصيل'))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, [title.text.trim(), body.text.trim()]), child: const Text('إنشاء'))]));
    title.dispose(); body.dispose();
    if (values == null || values.first.isEmpty) return;
    final parts = (repo['full_name'] as String).split('/');
    try { final issue = await _github.createIssue(owner: parts.first, repo: parts.last, title: values.first, body: values.last); if (mounted) setState(() => _message = 'تم إنشاء Issue #${issue['number']}'); }
    catch (e) { if (mounted) setState(() => _message = e.toString()); }
  }

  Future<void> _createPullRequest(Map<String, dynamic> repo) async {
    final title = TextEditingController();
    final head = TextEditingController();
    final base = TextEditingController(text: (repo['default_branch'] ?? 'main').toString());
    final body = TextEditingController();
    final values = await showDialog<List<String>>(context: context, builder: (context) => AlertDialog(title: Text('Pull Request — ${repo['name']}'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')), TextField(controller: head, decoration: const InputDecoration(labelText: 'Head branch')), TextField(controller: base, decoration: const InputDecoration(labelText: 'Base branch')), TextField(controller: body, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'الوصف'))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, [title.text.trim(), head.text.trim(), base.text.trim(), body.text.trim()]), child: const Text('فتح PR'))]));
    title.dispose(); head.dispose(); base.dispose(); body.dispose();
    if (values == null || values.first.isEmpty || values[1].isEmpty || values[2].isEmpty) return;
    final parts = (repo['full_name'] as String).split('/');
    try { final pr = await _github.createPullRequest(owner: parts.first, repo: parts.last, title: values[0], head: values[1], base: values[2], body: values[3]); if (mounted) setState(() => _message = 'تم فتح Pull Request #${pr['number']}'); }
    catch (e) { if (mounted) setState(() => _message = e.toString()); }
  }

  @override
  void dispose() { _github.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(16), child: Row(children: [const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('GitHub Workspace', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), Text('Repositories • Issues • Pull Requests', style: TextStyle(color: Color(0xFF91A6BE), fontSize: 10))])), IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)), FilledButton.tonalIcon(onPressed: _busy ? null : _createRepository, icon: const Icon(Icons.add), label: const Text('مستودع'))])),
    if (_busy) const LinearProgressIndicator(minHeight: 2),
    if (_message.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Align(alignment: Alignment.centerRight, child: Text(_message, style: const TextStyle(color: Color(0xFF9EB4CB), fontSize: 11)))),
    Expanded(child: _repos.isEmpty ? const Center(child: Text('لا توجد بيانات مستودعات. اضغط تحديث بعد إضافة الرمز.', style: TextStyle(color: Color(0xFF91A6BE)), textAlign: TextAlign.center)) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: _repos.length, itemBuilder: (context, index) {
      final repo = _repos[index];
      return Card(child: ExpansionTile(leading: Icon(repo['private'] == true ? Icons.lock_outline : Icons.public, color: const Color(0xFF7BCBDD)), title: Text('${repo['name']}', style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${repo['full_name']} • ${repo['language'] ?? 'Unknown'}', style: const TextStyle(fontSize: 10)), children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${repo['description'] ?? 'لا يوجد وصف'}', style: const TextStyle(color: Color(0xFF9CB0C7), fontSize: 11)), Row(children: [TextButton.icon(onPressed: () => _createIssue(repo), icon: const Icon(Icons.add_task), label: const Text('Issue')), TextButton.icon(onPressed: () => _createPullRequest(repo), icon: const Icon(Icons.call_merge), label: const Text('Pull Request'))])]))]));
    })),
  ]);
}
