import 'package:material_ui/material_ui.dart';

import '../core/nexus_theme.dart';
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
  void initState() {
    super.initState();
    for (final agent in AgentProfile.defaults) {
      _agentKeys[agent.id] = TextEditingController();
    }
    _load();
  }

  Future<void> _load() async {
    _base.text = await _vault.read('ai.base_url');
    final storedModel = await _vault.read('ai.model');
    _model.text = storedModel.isEmpty ? 'Spark-X2.6-1.7B' : storedModel;
    _ownerKey.text = await _vault.read('ai.owner_key');
    _githubToken.text = await _vault.read('github.token');
    for (final agent in AgentProfile.defaults) {
      _agentKeys[agent.id]!.text = await _vault.read('ai.agent.${agent.id}.key');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() { _saving = true; _message = ''; });
    try {
      await _vault.write('ai.base_url', _base.text);
      await _vault.write('ai.model', _model.text);
      await _vault.write('ai.owner_key', _ownerKey.text);
      await _vault.write('github.token', _githubToken.text);
      for (final agent in AgentProfile.defaults) {
        await _vault.write('ai.agent.${agent.id}.key', _agentKeys[agent.id]!.text);
      }
      if (mounted) setState(() => _message = 'حُفظت الإعدادات الحساسة في التخزين الآمن للجهاز.');
    } catch (error) {
      if (mounted) setState(() => _message = 'فشل الحفظ: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _base.dispose();
    _model.dispose();
    _ownerKey.dispose();
    _githubToken.dispose();
    for (final controller in _agentKeys.values) { controller.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 28),
      children: [
        const NexusPageHeader(
          title: 'إعدادات النظام',
          subtitle: 'إدارة الاتصال والمفاتيح الخاصة بالمالك والوكلاء والتكاملات.',
          padding: EdgeInsets.fromLTRB(0, 12, 0, 18),
        ),
        _SettingSection(
          icon: Icons.memory_rounded,
          title: 'AI ENGINE / ARAM AI',
          description: 'إعداد بوابة الذكاء الاصطناعي والنموذج المستخدم عند الاتصال ببوابة خارجية.',
          child: Column(children: [
            TextField(controller: _base, keyboardType: TextInputType.url, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'عنوان API Base URL', hintText: 'https://your-gateway.example/v1', prefixIcon: Icon(Icons.link_rounded))),
            const SizedBox(height: 10),
            TextField(controller: _model, decoration: const InputDecoration(labelText: 'اسم النموذج', prefixIcon: Icon(Icons.memory_rounded))),
            const SizedBox(height: 10),
            TextField(controller: _ownerKey, obscureText: true, decoration: const InputDecoration(labelText: 'مفتاح المالك / المفتاح الافتراضي', prefixIcon: Icon(Icons.key_rounded))),
            const SizedBox(height: 9),
            const Text('اترك عنوان البوابة فارغًا لاستخدام محرك Aram AI المدمج عند توفره. لا يوجد عنوان أو مفتاح افتراضي مختلق.', style: TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.5)),
          ]),
        ),
        _SettingSection(
          icon: Icons.hub_rounded,
          title: 'INDEPENDENT AGENT KEYS',
          description: 'يمكن لكل وكيل استخدام مفتاحه الخاص، وإلا يعود إلى مفتاح المالك.',
          child: Column(children: [
            ...AgentProfile.defaults.map((agent) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: TextField(controller: _agentKeys[agent.id], obscureText: true, decoration: InputDecoration(labelText: agent.name, prefixIcon: const Icon(Icons.vpn_key_outlined))),
                )),
          ]),
        ),
        _SettingSection(
          icon: Icons.code_rounded,
          title: 'GITHUB CONNECTION',
          description: 'أضف رمزًا بصلاحيات محدودة حسب العمليات التي تنوي استخدامها.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: _githubToken, obscureText: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'GitHub Personal Access Token', prefixIcon: Icon(Icons.key_rounded))),
            const SizedBox(height: 8),
            const Text('عمليات إنشاء المستودعات والتذاكر وطلبات الدمج تحتاج صلاحيات مناسبة في GitHub. لا تشارك الرمز مع أي جهة.', style: TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.5)),
          ]),
        ),
        const SizedBox(height: 5),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
          label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ الإعدادات'),
        ),
        if (_message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: NexusGlassPanel(
              padding: const EdgeInsets.all(12),
              radius: 14,
              tint: const Color(0xB31A2B27),
              child: Text(_message, style: const TextStyle(color: NexusPalette.success, fontSize: 11)),
            ),
          ),
        const SizedBox(height: 18),
        const NexusSectionHeader('ABOUT', subtitle: 'معلومات المطوّر والتطبيق.'),
        const NexusGlassPanel(
          child: Row(children: [
            NexusIconTile(Icons.code_rounded, size: 42),
            SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Aram Aoyal', style: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900, fontSize: 12)),
              SizedBox(height: 3),
              Text('TermiAI-Nexus • AETHERIUM 3D', style: TextStyle(color: NexusPalette.muted, fontSize: 10)),
              SizedBox(height: 3),
              Text('Telegram: https://t.me/ro_gy', textDirection: TextDirection.ltr, style: TextStyle(color: NexusPalette.primaryLight, fontSize: 10)),
            ])),
          ]),
        ),
      ],
    );
  }
}

class _SettingSection extends StatelessWidget {
  const _SettingSection({required this.icon, required this.title, required this.description, required this.child});
  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: NexusGlassPanel(
          padding: const EdgeInsets.all(15),
          radius: 21,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [NexusIconTile(icon, size: 38), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(color: NexusPalette.primaryLight, fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w900)))]),
            const SizedBox(height: 8),
            Text(description, style: const TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.45)),
            const SizedBox(height: 14),
            child,
          ]),
        ),
      );
}
