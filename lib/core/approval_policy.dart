class ApprovalDecision {
  const ApprovalDecision({required this.requiresApproval, required this.reason});
  final bool requiresApproval;
  final String reason;
}

class ApprovalPolicy {
  static final List<RegExp> _rules = [
    RegExp(r'(^|\s)(sudo|su)(\s|$)', caseSensitive: false),
    RegExp(r'\brm\s+(-[^\s]*[rf]|--recursive|--force)\b', caseSensitive: false),
    RegExp(r'\b(mkfs|dd\s+if=|fdisk|parted|wipefs|reboot|shutdown)\b', caseSensitive: false),
    RegExp(r'\b(curl|wget)\b[^\n]*(\||sh\b|bash\b)', caseSensitive: false),
    RegExp(r'\b(git\s+push|git\s+reset\s+--hard|git\s+clean\s+-[a-z]*f)', caseSensitive: false),
    RegExp(r'\b(chmod\s+777|chown\s+-R|setprop|mount|umount)\b', caseSensitive: false),
    RegExp(r'\b(api[_-]?key|token|password|secret)\s*=', caseSensitive: false),
  ];

  static ApprovalDecision inspectCommand(String command) {
    for (final rule in _rules) {
      if (rule.hasMatch(command)) {
        return const ApprovalDecision(requiresApproval: true, reason: 'الأمر قد يغيّر النظام أو يحذف بيانات أو ينقل أسراراً أو يكتب إلى خدمة خارجية.');
      }
    }
    return const ApprovalDecision(requiresApproval: false, reason: 'لم تُطابق صيغة الأمر قواعد الخطر المعروفة. راجع الأمر قبل تشغيله.');
  }

  static bool isSensitivePathSegment(String segment) {
    final name = segment.toLowerCase();
    const exactNames = {
      '.git', '.termai', '.env', '.npmrc', '.pypirc', '.netrc',
      '.git-credentials', 'google-services.json', '.ssh', '.aws', '.azure', '.kube',
    };
    const sensitiveExtensions = {
      '.pem', '.p12', '.pfx', '.jks', '.keystore', '.key', '.gpg', '.asc',
      '.der', '.cer',
    };
    final sensitiveName = RegExp(
      r'(^|[._-])(secret|secrets|credential|credentials|token|password|passwd|private|apikey|api_key|auth|service-account)([._-]|$)',
      caseSensitive: false,
    );
    return exactNames.contains(name) ||
        name.startsWith('.env.') ||
        name.endsWith('.env') ||
        name.startsWith('id_rsa') ||
        name.startsWith('id_ed25519') ||
        sensitiveExtensions.any(name.endsWith) ||
        sensitiveName.hasMatch(name);
  }

  static bool validRelativePath(String path) {
    final normalized = path.replaceAll('\\', '/').trim();
    if (normalized.isEmpty || normalized.startsWith('/') || normalized.startsWith('~')) return false;
    if (RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) return false;
    if (normalized.contains('\u0000')) return false;
    final segments = normalized.split('/');
    if (segments.any((part) =>
        part.isEmpty || part == '.' || part == '..' ||
        isSensitivePathSegment(part))) return false;
    return true;
  }
}
