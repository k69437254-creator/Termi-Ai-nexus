#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="${1:-$PWD}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_BRANCH="integration/aram-ai-engine"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/TermiAI-Nexus-Obsidian-Backup-$STAMP"

fail() { printf '\n[OBSIDIAN] ERROR: %s\n' "$1" >&2; exit 1; }

[[ -d "$ROOT" ]] || fail "مسار المشروع غير موجود: $ROOT"
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "المسار المحدد ليس مستودع Git."
BRANCH="$(git -C "$ROOT" branch --show-current)"
[[ "$BRANCH" == "$EXPECTED_BRANCH" ]] || fail "الفرع الحالي '$BRANCH'؛ المطلوب '$EXPECTED_BRANCH'. لم يتم تعديل أي ملف."

# These are the exact Git blob hashes of the design files in the supplied package.
# The current integration branch already contains these exact files.
declare -A DESIGN_HASHES=(
  ["lib/main.dart"]="0b18a2a38fe1f27f2598e38102edbb7f594f23e0"
  ["lib/app_shell.dart"]="2c0851da938094463ad7fd8b3692709ed0f3d645"
  ["lib/core/nexus_theme.dart"]="ee7c695fd90f88c539ed0675db32a21a3d82119b"
  ["lib/screens/agents_screen.dart"]="efb21c81bad249f16eef69a4271a6d2dcc2bde88"
  ["lib/screens/control_screen.dart"]="1f62c096b99c6dd1427991b47a5d6b431caef5e5"
  ["lib/screens/github_screen.dart"]="0860c2f4387273098848152880e79cf90b44c829"
  ["lib/screens/office_screen.dart"]="9f6781f8413b12310237e4c5b32dd78d0dca0a0a"
  ["lib/screens/projects_screen.dart"]="d68dd7f01af3119fc0277876f8ba491009c76412"
  ["lib/screens/settings_screen.dart"]="1f72b67a05b9b2dc4a8f8fe2177d43142f193e07"
  ["lib/screens/terminal_screen.dart"]="283cc46fbd5c58ce3bd5bc3e613d55a49afb1179"
)

# Validate the reference package before touching the project.
for file in "${!DESIGN_HASHES[@]}"; do
  [[ -f "$SCRIPT_DIR/$file" ]] || fail "ملف التصميم مفقود من الحزمة: $file"
done

# Require an exact baseline for the two newer project files. Do not replace them
# with the older copies that came inside the original redesign archive.
verify_project_blob() {
  local file="$1" expected="$2" actual status
  [[ -f "$ROOT/$file" ]] || fail "ملف مطلوب مفقود من المشروع: $file"
  status="$(git -C "$ROOT" status --porcelain -- "$file")"
  [[ -z "$status" ]] || fail "يوجد تعديل محلي في $file؛ احفظه أولاً. لم يتم تعديل أي ملف."
  actual="$(git -C "$ROOT" hash-object -- "$ROOT/$file")"
  [[ "$actual" == "$expected" ]] || fail "الملف $file لا يطابق النسخة التي راجعتها من فرع GitHub. أوقفت التثبيت لحماية التعديلات."
}

# Validate all files that will be reapplied and reject local edits.
for file in "${!DESIGN_HASHES[@]}"; do
  expected="${DESIGN_HASHES[$file]}"
  verify_project_blob "$file" "$expected"
done

# Protect the current assistant, engine lifecycle, and 3D office implementations.
verify_project_blob "lib/screens/assistant_screen.dart" "118b3c75754a8430db552da927f9d3c36dd1b5fe"
verify_project_blob "lib/screens/engine_center_screen.dart" "72e959da250d898e195eeecb20d1ef5c1d42dc3a"
verify_project_blob "lib/widgets/virtual_office_3d.dart" "e6b7270134b968c15151f670a336aabc04cdd6fb"

ASSISTANT="$ROOT/lib/screens/assistant_screen.dart"
ENGINE="$ROOT/lib/screens/engine_center_screen.dart"
OFFICE="$ROOT/lib/widgets/virtual_office_3d.dart"

# Guard the newer assistant behavior and the matching visual components.
for marker in "managerConversation" "saveManagerConversation" "gateway.chat" "_MessageBubble" "_PlanBubble" "_TypingBubble" "NexusGlassPanel"; do
  grep -Fq "$marker" "$ASSISTANT" || fail "ميزة/مكوّن المساعد غير موجود: $marker"
done

# Guard the current engine screen: keep real model availability and import/download handling.
for marker in "MethodChannel('termai/aram-engine')" "status['modelAvailable']" "importModel" "downloadModel" "_modelAvailable"; do
  grep -Fq "$marker" "$ENGINE" || fail "تكامل محرك Aram AI غير مكتمل: $marker"
done

# Verify the Obsidian/Violet palette has already been applied to the 3D office.
for color in "0xFF171526" "0xFF211B34" "0xFF8B5CF6" "0xFF9A5E9F"; do
  grep -Fq "$color" "$OFFICE" || fail "لون المقر ثلاثي الأبعاد غير موجود: $color"
done

# Check that the package's visual shell is the active app shell.
grep -Fq "EngineCenterScreen" "$ROOT/lib/app_shell.dart" || fail "مركز Aram AI غير مربوط بالتنقل."
grep -Fq "NexusGlassPanel" "$ROOT/lib/core/nexus_theme.dart" || fail "مكوّن الزجاج غير موجود في الثيم."
grep -Fq "0xFF8B5CF6" "$ROOT/lib/core/nexus_theme.dart" || fail "لون Electric Violet غير موجود في الثيم."

# All expected files are now validated. Make a timestamped backup, then reapply
# the ten exact package files. Since they match byte-for-byte, this is idempotent.
mkdir -p "$BACKUP"
for file in "${!DESIGN_HASHES[@]}"; do
  mkdir -p "$BACKUP/$(dirname "$file")"
  cp -p "$ROOT/$file" "$BACKUP/$file"
done

rollback() {
  local code=$?
  trap - EXIT
  if [[ $code -ne 0 ]]; then
    printf '\n[OBSIDIAN] حدث خطأ؛ جارٍ استرجاع الملفات من النسخة الاحتياطية...\n' >&2
    for file in "${!DESIGN_HASHES[@]}"; do
      [[ -f "$BACKUP/$file" ]] || continue
      mkdir -p "$ROOT/$(dirname "$file")"
      cp -p "$BACKUP/$file" "$ROOT/$file"
    done
    printf '[OBSIDIAN] مسار النسخة الاحتياطية: %s\n' "$BACKUP" >&2
  fi
  exit "$code"
}
trap rollback EXIT

for file in "${!DESIGN_HASHES[@]}"; do
  mkdir -p "$ROOT/$(dirname "$file")"
  cp -f "$SCRIPT_DIR/$file" "$ROOT/$file"
  actual="$(git -C "$ROOT" hash-object -- "$ROOT/$file")"
  [[ "$actual" == "${DESIGN_HASHES[$file]}" ]] || fail "فشل التحقق بعد نسخ $file"
done

trap - EXIT
printf '\n[OBSIDIAN] اكتمل تطبيق/تأكيد ملفات التصميم المرجعية.\n'
printf '[OBSIDIAN] تمت مطابقة 10 ملفات تصميم حرفيًا مع الحزمة.\n'
printf '[OBSIDIAN] تم الحفاظ على شاشة المساعد الأحدث وسجل المحادثة.\n'
printf '[OBSIDIAN] تم الحفاظ على مركز المحرك الأحدث وحالة modelAvailable.\n'
printf '[OBSIDIAN] تم التحقق من ألوان المقر ثلاثي الأبعاد.\n'
printf '[OBSIDIAN] النسخة الاحتياطية: %s\n' "$BACKUP"
printf '[OBSIDIAN] لم يتم تنفيذ git add أو commit أو push أو merge.\n'
printf '[OBSIDIAN] لم يتم تشغيل Flutter analyze أو بناء APK؛ لم ندّعِ اختبارًا غير منفذ.\n'
