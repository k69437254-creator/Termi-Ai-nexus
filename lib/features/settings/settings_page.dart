import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../shared/ui_components.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              const PageHeading(title: 'الإعدادات', subtitle: 'معلومات التطبيق والمطوّر وحالة النسخة الحالية.'),
              const SizedBox(height: 20),
              const InfoPanel(
                icon: Icons.settings_suggest_outlined,
                title: 'نسخة تأسيسية 0.1.0',
                description: 'واجهة عربية أولية ومسارات تنقل وإدارة مسودات داخل الذاكرة. لا تتضمن هذه النسخة بعد بيئة Linux أو نظام وكلاء تنفيذي.',
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.border)),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('المطوّر', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    SizedBox(height: 9),
                    Text('Aram Aoyal', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
                    SizedBox(height: 6),
                    SelectableText('https://t.me/ro_gy', style: TextStyle(color: AppTheme.accent, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const _SettingLine(icon: Icons.language_rounded, label: 'لغة الواجهة', value: 'العربية'),
              const _SettingLine(icon: Icons.palette_outlined, label: 'المظهر', value: 'داكن — أزرق وأسود'),
              const _SettingLine(icon: Icons.info_outline, label: 'إصدار التطبيق', value: '0.1.0 (1)'),
            ]),
          ),
        ),
      ],
    );
  }
}

class _SettingLine extends StatelessWidget {
  const _SettingLine({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppTheme.textMuted, size: 19),
          const SizedBox(width: 11),
          Expanded(child: Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12))),
          Text(value, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}
