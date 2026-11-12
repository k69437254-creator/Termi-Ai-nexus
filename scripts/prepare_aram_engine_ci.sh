#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/android/aram-source"
COMMIT="$(tr -d '[:space:]' < "$ROOT/android/aram-engine.commit")"
REPO="https://github.com/k69437254-creator/Aram-Ai.git"
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid pinned Aram AI commit" >&2; exit 1; }

if [[ ! -d "$SOURCE/.git" ]]; then
  git clone --filter=blob:none --no-checkout "$REPO" "$SOURCE"
fi
git -C "$SOURCE" fetch --depth 1 origin "$COMMIT"
git -C "$SOURCE" checkout --detach "$COMMIT"
test "$(git -C "$SOURCE" rev-parse HEAD)" = "$COMMIT"

bash "$SOURCE/scripts/prepare_native.sh"

# The upstream Android binding uses its own version-catalog aliases. Adapt only
# this pinned module to the host build's plugin/dependency declarations.
python3 - "$SOURCE/vendor/llama.cpp/examples/llama.android/lib/build.gradle.kts" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
replacements = {
    'alias(libs.plugins.android.library)': 'id("com.android.library")',
    'alias(libs.plugins.jetbrains.kotlin.android)': '',
    'implementation(libs.androidx.core.ktx)': 'implementation("androidx.core:core-ktx:1.17.0")',
    'implementation(libs.androidx.datastore.preferences)': 'implementation("androidx.datastore:datastore-preferences:1.2.0")',
    'testImplementation(libs.junit)': 'testImplementation("junit:junit:4.13.2")',
    'androidTestImplementation(libs.androidx.junit)': 'androidTestImplementation("androidx.test.ext:junit:1.3.0")',
}
for old, new in replacements.items():
    if old in s:
        s = s.replace(old, new, 1)
    elif new not in s:
        raise SystemExit(f"Pinned llama Android Gradle file changed; missing expected expression: {old}")
# The host enables AGP 9 built-in Kotlin; remove the old Kotlin plugin DSL.
kotlin_block = '''    kotlin {
        jvmToolchain(17)

        compileOptions {
            targetCompatibility = JavaVersion.VERSION_17
        }
    }
'''
s = s.replace(kotlin_block, '')
if 'libs.' in s or 'org.jetbrains.kotlin.android' in s or 'kotlin {' in s:
    raise SystemExit("Upstream llama module still contains an incompatible version-catalog/Kotlin-plugin DSL")
p.write_text(s)
PY

echo "Aram AI native source prepared at pinned commit $COMMIT"
