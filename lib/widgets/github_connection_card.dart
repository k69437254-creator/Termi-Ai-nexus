// GitHub account connection is intentionally managed inside GitHub Workspace.
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;

import '../core/nexus_theme.dart';
import '../core/secure_vault.dart';

class GitHubConnectionCard extends StatefulWidget {
  const GitHubConnectionCard({super.key, this.onConnectionChanged});

  final ValueChanged<bool>? onConnectionChanged;

  @override
  State<GitHubConnectionCard> createState() => _GitHubConnectionCardState();
}

class _GitHubConnectionCardState extends State<GitHubConnectionCard> {
  final TextEditingController _token = TextEditingController();
  final SecureVault _vault = SecureVault.instance;
  bool _busy = true;
  bool _connected = false;
  bool _showToken = false;
  String _account = '';
  String _displayName = '';
  String _avatarUrl = '';
  String _bio = '';
  int _publicRepos = 0;
  int _followers = 0;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _restoreConnection();
  }

  Future<Map<String, dynamic>> _verify(String value) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/user'),
      headers: <String, String>{
        'Authorization': 'Bearer $value',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw StateError(
        'رفض GitHub الرمز (${response.statusCode}). تحقق من صلاحيته وصلاحيات المستودعات المطلوبة.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['login'] is! String) {
      throw const FormatException('أعاد GitHub بيانات حساب غير مكتملة.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  void _applyProfile(Map<String, dynamic> data) {
    _account = data['login']?.toString() ?? '';
    _displayName = data['name']?.toString().trim() ?? '';
    _avatarUrl = data['avatar_url']?.toString() ?? '';
    _bio = data['bio']?.toString().trim() ?? '';
    _publicRepos = (data['public_repos'] as num?)?.toInt() ?? 0;
    _followers = (data['followers'] as num?)?.toInt() ?? 0;
    _connected = _account.isNotEmpty;
  }

  Future<void> _restoreConnection() async {
    var connected = false;
    try {
      final saved = await _vault.read('github.token');
      if (saved.isNotEmpty) {
        final profile = await _verify(saved);
        _applyProfile(profile);
        _message = 'تمت استعادة الاتصال والتحقق من الحساب المحفوظ.';
        connected = true;
      }
    } catch (error) {
      _connected = false;
      _message = 'تعذر التحقق من الرمز المحفوظ: $error';
    } finally {
      if (mounted) setState(() => _busy = false);
      if (connected) widget.onConnectionChanged?.call(true);
    }
  }

  Future<void> _connect() async {
    final value = _token.text.trim();
    if (value.length < 20 || value.contains(RegExp(r'\s'))) {
      setState(() => _message = 'أدخل Personal Access Token صالحًا دون مسافات.');
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    var connected = false;
    try {
      final profile = await _verify(value);
      await _vault.write('github.token', value);
      _token.clear();
      if (!mounted) return;
      setState(() {
        _applyProfile(profile);
        _message = 'تم التحقق من الحساب وحفظ الرمز داخل التخزين الآمن للجهاز.';
      });
      connected = true;
    } catch (error) {
      if (mounted) setState(() => _message = 'فشل ربط الحساب: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
      if (connected) widget.onConnectionChanged?.call(true);
    }
  }

  Future<void> _disconnect() async {
    setState(() {
      _busy = true;
      _message = '';
    });
    var disconnected = false;
    try {
      await _vault.write('github.token', '');
      if (!mounted) return;
      setState(() {
        _connected = false;
        _account = '';
        _displayName = '';
        _avatarUrl = '';
        _bio = '';
        _publicRepos = 0;
        _followers = 0;
        _message = 'تم فصل الحساب من هذا الجهاز. لم يُحذف أي مستودع من GitHub.';
      });
      disconnected = true;
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر فصل الحساب: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
      if (disconnected) widget.onConnectionChanged?.call(false);
    }
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _connected ? NexusPalette.success : NexusPalette.warning;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: NexusPalette.card,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: NexusPalette.primary.withValues(alpha: 0.28)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x19000000), blurRadius: 18, offset: Offset(0, 7)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: NexusPalette.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: NexusPalette.primary.withValues(alpha: 0.30)),
                ),
                child: const Icon(Icons.code_rounded, color: NexusPalette.primaryLight),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('حساب GitHub', style: TextStyle(color: NexusPalette.text, fontSize: 14, fontWeight: FontWeight.w900)),
                    SizedBox(height: 3),
                    Text('هوية الاتصال وإدارة صلاحية الوصول', style: TextStyle(color: NexusPalette.muted, fontSize: 10)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(24)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(_connected ? Icons.verified_rounded : Icons.link_off_rounded, size: 13, color: statusColor),
                    const SizedBox(width: 5),
                    Text(_connected ? 'متصل' : 'غير متصل', style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_busy && !_connected)
            const LinearProgressIndicator(minHeight: 2)
          else if (_connected) ...<Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 25,
                  backgroundColor: NexusPalette.primary.withValues(alpha: 0.12),
                  backgroundImage: _avatarUrl.startsWith('https://') ? NetworkImage(_avatarUrl) : null,
                  child: _avatarUrl.startsWith('https://') ? null : const Icon(Icons.person_rounded, color: NexusPalette.primaryLight, size: 25),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(_displayName.isEmpty ? '@$_account' : _displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900, fontSize: 13)),
                      const SizedBox(height: 3),
                      Text('@$_account', textDirection: TextDirection.ltr, style: const TextStyle(color: NexusPalette.primaryLight, fontSize: 10, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _disconnect,
                  icon: const Icon(Icons.link_off_rounded, size: 15),
                  label: const Text('فصل'),
                ),
              ],
            ),
            if (_bio.isNotEmpty) ...<Widget>[
              const SizedBox(height: 9),
              Text(_bio, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.4)),
            ],
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(child: _profileMetric(Icons.folder_copy_outlined, 'مستودعات عامة', '$_publicRepos')),
                const SizedBox(width: 8),
                Expanded(child: _profileMetric(Icons.people_outline_rounded, 'المتابعون', '$_followers')),
                const SizedBox(width: 8),
                Expanded(child: _profileMetric(Icons.lock_outline_rounded, 'الرمز', 'محفوظ')),
              ],
            ),
            const SizedBox(height: 8),
            const Text('الرمز غير معروض ولا يُمرّر إلى الوكلاء؛ يُقرأ من التخزين الآمن عند الحاجة إلى طلب GitHub.', style: TextStyle(color: NexusPalette.success, fontSize: 10, height: 1.4)),
          ] else ...<Widget>[
            const Text('اربط حسابك برمز وصول شخصي. يتحقق التطبيق من الحساب أولًا، ثم يحفظ الرمز محليًا في التخزين الآمن.', style: TextStyle(color: NexusPalette.muted, fontSize: 11, height: 1.5)),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              obscureText: !_showToken,
              autocorrect: false,
              enableSuggestions: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'Personal Access Token',
                hintText: 'github_pat_… أو ghp_…',
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  tooltip: _showToken ? 'إخفاء الرمز' : 'إظهار الرمز مؤقتًا',
                  onPressed: () => setState(() => _showToken = !_showToken),
                  icon: Icon(_showToken ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('استخدم أقل الصلاحيات التي تسمح بإنشاء المستودعات وقراءة المستودعات ورفع الملفات وسير العمل وقراءة Actions. لا تمنح صلاحيات إضافية لا تحتاجها.', style: TextStyle(color: NexusPalette.subtle, fontSize: 10, height: 1.5)),
            const SizedBox(height: 11),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _connect,
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_user_outlined),
                label: Text(_busy ? 'جارٍ التحقق من الحساب…' : 'التحقق وربط الحساب'),
              ),
            ),
          ],
          if (_message.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(_message, style: TextStyle(color: _message.startsWith('فشل') || _message.startsWith('تعذر') ? NexusPalette.danger : NexusPalette.muted, fontSize: 10, height: 1.45)),
          ],
        ],
      ),
    );
  }

  Widget _profileMetric(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          children: <Widget>[
            Icon(icon, color: NexusPalette.primaryLight, size: 16),
            const SizedBox(height: 5),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.text, fontSize: 11, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.muted, fontSize: 8)),
          ],
        ),
      );
}
