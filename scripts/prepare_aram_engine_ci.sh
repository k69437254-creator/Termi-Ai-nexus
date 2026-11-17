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

# Fetch the exact upstream llama.cpp revision used by the verified native patch.
LLAMA="$SOURCE/vendor/llama.cpp"
LLAMA_COMMIT="a4d4f2fd4ec85ec6a0a9ece4870416c1b6cc24f5"

mkdir -p "$SOURCE/vendor"
if [[ -e "$LLAMA" && ! -d "$LLAMA/.git" ]]; then
  echo "Existing llama.cpp path is not a Git checkout; refusing to overwrite it." >&2
  exit 1
fi

if [[ ! -d "$LLAMA/.git" ]]; then
  git clone --filter=blob:none --no-checkout \
    https://github.com/ggml-org/llama.cpp.git "$LLAMA"
fi

git -C "$LLAMA" fetch --depth 1 origin "$LLAMA_COMMIT"
git -C "$LLAMA" checkout --detach "$LLAMA_COMMIT"
test "$(git -C "$LLAMA" rev-parse HEAD)" = "$LLAMA_COMMIT"

# Apply the reviewed native changes exactly once to the pinned clean source.
git -C "$LLAMA" apply --check "$ROOT/scripts/aram_native_engine.patch"
git -C "$LLAMA" apply "$ROOT/scripts/aram_native_engine.patch"

# Verify critical native integration points before Gradle configuration.
grep -q 'resetConversationNative' "$LLAMA/examples/llama.android/lib/src/main/cpp/ai_chat.cpp"
grep -q 'chat_template_kwargs' "$LLAMA/common/chat.cpp"
grep -q 'beginGeneration' "$LLAMA/examples/llama.android/lib/src/main/java/com/arm/aichat/InferenceEngine.kt"
grep -q 'cancelGeneration' "$LLAMA/examples/llama.android/lib/src/main/java/com/arm/aichat/InferenceEngine.kt"

# Preserve detailed GGUF loader errors for the Android error reporting layer.
python3 "$ROOT/scripts/patch_native_load_diagnostics.py"

grep -q 'ARAM_NATIVE_LOAD_DIAGNOSTICS_V1' "$LLAMA/examples/llama.android/lib/src/main/cpp/logging.h"
grep -q 'lastModelLoadError' "$LLAMA/examples/llama.android/lib/src/main/java/com/arm/aichat/internal/InferenceEngineImpl.kt"

echo "PASS: pinned llama.cpp native patch and load diagnostics applied."

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
