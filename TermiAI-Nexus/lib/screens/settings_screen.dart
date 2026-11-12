import 'package:flutter/material.dart';
import '../core/secure_vault.dart';
import '../models/domain.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _vault = SecureVault.instance;
  final _base = TextEditingController();
  final _model = TextEditingController(text: 'Spark-X2.6-1.7B');
  final _ownerKey = TextEditingController();
  final _githubToken = TextEditingController();
  final Map<String, TextEditingController> _agentKeys = {};
  bool _loading = true;
  bool _saving = false;
  String _message = '';

  @override
  void initState() { super.initState(); for (final a in AgentProfile.defaults) { _agentKeys[a.id] = TextEditingController(); } _load(); }
  Future<void> _load() async {
    _base.text = await _vault.read('ai.base_url');
    _model.text = (await _vault.read('ai.model')).isEmpty ? 'Spark-X2.6-1.7B' : await _vault.read('ai.model');
    _ownerKey.text = await _vault.read('ai.owner_key');
    _githubToken.text = await _vault.read('github.token');
    for (final a in AgentProfile.defaults) { _agentKeys[a.id]!.text = await _vault.read('ai.agent.${a.id}.key'); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() { _saving = true; _message = ''; });
    try {
      await _vault.write('ai.base_url', _base.text);
      await _vault.write('ai.model', _model.text);
      await _vault.write('ai.owner_key', _ownerKey.text);
      await _vault.write('github.token', _githubToken.text);
      for (final a in AgentProfile.defaults) { await _vault.write('ai.agent.${a.id}.key', _agentKeys[a.id]!.text); }
      if (mounted) setState(() => _message = 'حُفظت الإعدادات الحساسة في التخزين الآمن للجهاز.');
    } catch (e) { if (mounted) setState(() => _message = 'فشل الحفظ: $e'); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  void dispose() {
    _base.dispose(); _model.dispose(); _ownerKey.dispose(); _githubToken.dispose();
    for (final c in _agentKeys.values) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('إعدادات النظام', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4), const Text('تُحفظ المفاتيح في Android Keystore-backed secure storage عبر flutter_secure_storage.', style: TextStyle(color: Color(0xFF91A6BE), fontSize: 11, height: 1.5)),
      const SizedBox(height: 18),
      const _SectionTitle('AI ENGINE / ARAM AI'),
      TextField(controller: _base, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'عنوان API Base URL', hintText: 'https://your-gateway.example/v1', prefixIcon: Icon(Icons.link))),
      const SizedBox(height: 10),
      TextField(controller: _model, decoration: const InputDecoration(labelText: 'اسم النموذج', prefixIcon: Icon(Icons.memory))),
      const SizedBox(height: 10),
      TextField(controller: _ownerKey, obscureText: true, decoration: const InputDecoration(labelText: 'مفتاح المالك / المفتاح الافتراضي', prefixIcon: Icon(Icons.key))),
      const SizedBox(height: 8),
      const Text('ضع عنوان البوابة الفعلي الذي توفره خدمتك. لا يوجد عنوان افتراضي مفترض داخل المشروع.', style: TextStyle(color: Color(0xFF8FA5BE), fontSize: 11)),
      const SizedBox(height: 18),
      const _SectionTitle('INDEPENDENT AGENT KEYS'),
      const Text('كل وكيل يستخدم مفتاحه الخاص إن توفر، وإلا يعود إلى مفتاح المالك.', style: TextStyle(color: Color(0xFF8FA5BE), fontSize: 11)),
      const SizedBox(height: 8),
      ...AgentProfile.defaults.map((agent) => Padding(padding: const EdgeInsets.only(bottom: 9), child: TextField(controller: _agentKeys[agent.id], obscureText: true, decoration: InputDecoration(labelText: agent.name, prefixIcon: const Icon(Icons.vpn_key_outlined))))),
      const SizedBox(height: 12),
      const _SectionTitle('GITHUB CONNECTION'),
      TextField(controller: _githubToken, obscureText: true, decoration: const InputDecoration(labelText: 'GitHub Personal Access Token', prefixIcon: Icon(Icons.code))),
      const SizedBox(height: 8),
      const Text('امنح أقل صلاحيات ممكنة. عمليات إنشاء المستودعات والتذاكر وطلبات الدمج تحتاج صلاحيات مناسبة في GitHub.', style: TextStyle(color: Color(0xFF8FA5BE), fontSize: 11, height: 1.4)),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ الإعدادات')),
      if (_message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_message, style: const TextStyle(color: Color(0xFF83DAB7), fontSize: 12))),
      const Divider(height: 32),
      const _SectionTitle('DEVELOPER'),
      const ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(child: Icon(Icons.code)), title: Text('Aram Aoyal'), subtitle: Text('Telegram: https://t.me/ro_gy')),
    ]);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(title, style: const TextStyle(color: Color(0xFF78CADD), fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w900)));
}
