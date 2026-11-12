import 'package:flutter_test/flutter_test.dart';
import 'package:termiai_nexus/core/approval_policy.dart';

void main() {
  group('ApprovalPolicy', () {
    test('flags destructive shell commands', () {
      expect(ApprovalPolicy.inspectCommand('rm -rf project').requiresApproval, isTrue);
      expect(ApprovalPolicy.inspectCommand('git push origin main').requiresApproval, isTrue);
    });

    test('allows ordinary inspection commands through the basic classifier', () {
      expect(ApprovalPolicy.inspectCommand('pwd').requiresApproval, isFalse);
      expect(ApprovalPolicy.inspectCommand('git status --short').requiresApproval, isFalse);
    });

    test('rejects path traversal and absolute paths', () {
      expect(ApprovalPolicy.validRelativePath('../outside.txt'), isFalse);
      expect(ApprovalPolicy.validRelativePath('/etc/passwd'), isFalse);
      expect(ApprovalPolicy.validRelativePath('.termai/checkpoints/override'), isFalse);
      expect(ApprovalPolicy.validRelativePath('.git/config'), isFalse);
      expect(ApprovalPolicy.validRelativePath('lib/main.dart'), isTrue);
    });
  });
}
