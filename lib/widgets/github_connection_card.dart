// TERMAI_GITHUB_AUTOMATION_UPDATE_20261116_V1
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/secure_vault.dart';
import '../core/nexus_theme.dart';

/// Token entry belongs to GitHub Workspace, not the general settings page.
/// The value is never displayed again after saving and is checked against /user.
class GitHubConnectionCard extends StatefulWidget {
  const GitHubConnectionCard({super.key});
  @override
  State<GitHubConnectionCard> createState() => _GitHubConnectionCardState();
}

class _GitHubConnectionCardState extends State<GitHubConnectionCard> {
  final _token = TextEditingController();
  final _vault = SecureVault.instance;
  bool _busy = true;
  bool _connected = false;
  bool _showToken = false;
  String _account = '';
  String _message = '';

  @override
  void initState() {
    super.initState();
    _restoreConnection();
  }

  Future<Map<String, dynamic>> _verify(String value) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/user'),
      headers: {
        'Authorization': 'Bearer $value',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw StateError('رفض GitHub الرمز (${response.statusCode}). تحقق من صلاحيته ونطاقاته.');
    }
    final data = jsonDecode(response.body);
    if (data is! Map || data['login'] is! String) {
      throw const FormatException('بيانات حساب GitHub غير صالحة.');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<void> _restoreConnection() async {
    try {
      final saved = await _vault.read('github.token');
      if (saved.isNotEmpty) {
        final data = await _verify(saved);
        _account = data['login'].toString();
        _connected = true;
        _message = 'تم التحقق من اتصال GitHub المحفوظ بأمان.';
      }
    } catch (error) {
      _connected = false;
      _message = 'تعذر التحقق من الاتصال المحفوظ: $error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final value = _token.text.trim();
    if (value.length < 20 || value.contains(RegExp(r'\s'))) {
      setState(() => _message = 'أدخل GitHub Personal Access Token صالحًا.');
      return;
    }
    setState(() { _busy = true; _message = ''; });
    try {
      final data = await _verify(value);
      await _vault.write('github.token', value);
      _token.clear();
      if (!mounted) return;
      setState(() {
        _account = data['login'].toString();
        _connected = true;
        _message = 'تم ربط الحساب والتحقق من الرمز. حُفظ الرمز في التخزين الآمن للجهاز.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'فشل الربط: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await _vault.write('github.token', '');
      if (mounted) setState(() {
        _connected = false;
        _account = '';
        _message = 'فُصل حساب GitHub من هذا الجهاز.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر فصل الحساب: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: NexusPalette.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: NexusPalette.primary.withValues(alpha: .30)),
      boxShadow: const [BoxShadow(color: Color(0x19000000), blurRadius: 18, offset: Offset(0, 7))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.code_rounded, color: NexusPalette.primaryLight, size: 25),
        const SizedBox(width: 9),
        const Expanded(child: Text('اتصال حساب GitHub', style: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900, fontSize: 14))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(color: (_connected ? NexusPalette.success : NexusPalette.warning).withValues(alpha: .13), borderRadius: BorderRadius.circular(30)),
          child: Text(_connected ? 'متصل' : 'غير متصل', style: TextStyle(color: _connected ? NexusPalette.success : NexusPalette.warning, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
      ]),
      const SizedBox(height: 9),
      Text(_connected ? 'الحساب: @$_account' : 'أدخل رمز GitHub هنا لربط حسابك وتصفح المستودعات وتشغيل عمليات النشر.', style: const TextStyle(color: NexusPalette.muted, fontSize: 11, height: 1.5)),
      if (!_connected) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _token,
          obscureText: !_showToken,
          autocorrect: false,
          enableSuggestions: false,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: 'GitHub Personal Access Token',
            hintText: 'github_pat_… أو ghp_…',
            prefixIcon: const Icon(Icons.key_rounded),
            suffixIcon: IconButton(
              tooltip: _showToken ? 'إخفاء الرمز' : 'إظهار الرمز مؤقتًا',
              onPressed: () => setState(() => _showToken = !_showToken),
              icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('لـ classic PAT: النطاقان repo وworkflow. ولـ fine-grained PAT: Repository creation: Write أو Administration: Write لإنشاء المستودع، وContents: Read and write، وWorkflows: Write، وActions: Read، وMetadata: Read. يجب أن يشمل الرمز المستودعات التي ينشئها التطبيق. لا يُرسل الرمز إلى الوكلاء.', style: TextStyle(color: NexusPalette.subtle, fontSize: 10, height: 1.45)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _busy ? null : _connect,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_rounded),
          label: Text(_busy ? 'جارٍ التحقق…' : 'تحقق واربط الحساب'),
        )),
      ] else ...[
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.verified_rounded, color: NexusPalette.success, size: 18),
          const SizedBox(width: 7),
          const Expanded(child: Text('الرمز محفوظ في Android secure storage ولا يظهر في الشاشة.', style: TextStyle(color: NexusPalette.success, fontSize: 10))),
          TextButton(onPressed: _busy ? null : _disconnect, child: const Text('فصل الحساب')),
        ]),
      ],
      if (_message.isNotEmpty) ...[
        const SizedBox(height: 9),
        Text(_message, style: TextStyle(color: _message.startsWith('فشل') || _message.startsWith('تعذر') ? NexusPalette.danger : NexusPalette.muted, fontSize: 10, height: 1.4)),
      ],
    ]),
  );
}
