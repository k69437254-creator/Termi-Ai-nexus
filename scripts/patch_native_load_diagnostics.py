#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LLAMA = ROOT / "android/aram-source/vendor/llama.cpp"
LOGGING = LLAMA / "examples/llama.android/lib/src/main/cpp/logging.h"
CPP = LLAMA / "examples/llama.android/lib/src/main/cpp/ai_chat.cpp"
KOTLIN = LLAMA / "examples/llama.android/lib/src/main/java/com/arm/aichat/internal/InferenceEngineImpl.kt"
MARKER = "ARAM_NATIVE_LOAD_DIAGNOSTICS_V1"

for path in (LOGGING, CPP, KOTLIN):
    if not path.is_file():
        raise SystemExit(f"Missing pinned llama.cpp Android source file: {path}")

# Keep the native loader's actual GGML error text instead of collapsing every
# load failure into the misleading UnsupportedArchitectureException.
logging = LOGGING.read_text()
if MARKER not in logging:
    anchor = "#pragma once\n#include <android/log.h>\n"
    if logging.count(anchor) != 1:
        raise SystemExit("Unexpected logging.h include section; refusing an unverified patch")
    logging = logging.replace(
        anchor,
        "#pragma once\n#include <android/log.h>\n#include <mutex>\n#include <string>\n\n"
        "// " + MARKER + "\n"
        "inline std::mutex g_ai_chat_load_error_mutex;\n"
        "inline std::string g_ai_chat_load_error;\n\n"
        "static inline void ai_chat_clear_load_error() {\n"
        "    std::lock_guard<std::mutex> lock(g_ai_chat_load_error_mutex);\n"
        "    g_ai_chat_load_error.clear();\n"
        "}\n\n"
        "static inline std::string ai_chat_get_load_error() {\n"
        "    std::lock_guard<std::mutex> lock(g_ai_chat_load_error_mutex);\n"
        "    return g_ai_chat_load_error;\n"
        "}\n",
        1,
    )
    callback_anchor = "static inline void aichat_android_log_callback(enum ggml_log_level level,\n                                              const char* text,\n                                              void* /*user*/) {\n    const int prio = android_log_prio_from_ggml(level);\n"
    callback_replacement = (
        "static inline void aichat_android_log_callback(enum ggml_log_level level,\n"
        "                                              const char* text,\n"
        "                                              void* /*user*/) {\n"
        "    if (level == GGML_LOG_LEVEL_ERROR && text != nullptr) {\n"
        "        std::lock_guard<std::mutex> lock(g_ai_chat_load_error_mutex);\n"
        "        g_ai_chat_load_error.append(text);\n"
        "        constexpr size_t MAX_NATIVE_ERROR_BYTES = 8192;\n"
        "        if (g_ai_chat_load_error.size() > MAX_NATIVE_ERROR_BYTES) {\n"
        "            g_ai_chat_load_error.erase(0, g_ai_chat_load_error.size() - MAX_NATIVE_ERROR_BYTES);\n"
        "        }\n"
        "    }\n"
        "    const int prio = android_log_prio_from_ggml(level);\n"
    )
    if logging.count(callback_anchor) != 1:
        raise SystemExit("Unexpected Android GGML log callback; refusing an unverified patch")
    logging = logging.replace(callback_anchor, callback_replacement, 1)
    LOGGING.write_text(logging)

cpp = CPP.read_text()
if MARKER not in cpp:
    load_anchor = "    auto *model = llama_model_load_from_file(model_path, model_params);\n"
    if cpp.count(load_anchor) != 1:
        raise SystemExit("Unexpected native model-load call; refusing an unverified patch")
    cpp = cpp.replace(load_anchor, "    ai_chat_clear_load_error();\n" + load_anchor, 1)
    function_anchor = (
        "    g_model = model;\n"
        "    return 0;\n"
        "}\n\n"
        "static llama_context *init_context"
    )
    function_replacement = (
        "    g_model = model;\n"
        "    return 0;\n"
        "}\n\n"
        "// " + MARKER + "\n"
        "extern \"C\"\n"
        "JNIEXPORT jstring JNICALL\n"
        "Java_com_arm_aichat_internal_InferenceEngineImpl_lastModelLoadError(JNIEnv *env, jobject) {\n"
        "    const auto detail = ai_chat_get_load_error();\n"
        "    const auto fallback = std::string(\"llama_model_load_from_file returned null without a GGML error log.\");\n"
        "    return env->NewStringUTF((detail.empty() ? fallback : detail).c_str());\n"
        "}\n\n"
        "static llama_context *init_context"
    )
    if cpp.count(function_anchor) != 1:
        raise SystemExit("Unexpected native load function boundary; refusing an unverified patch")
    cpp = cpp.replace(function_anchor, function_replacement, 1)
    CPP.write_text(cpp)

kotlin = KOTLIN.read_text()
if MARKER not in kotlin:
    kotlin = kotlin.replace("import com.arm.aichat.UnsupportedArchitectureException\n", "", 1)
    external_anchor = "    @FastNative\n    private external fun load(modelPath: String): Int\n"
    external_replacement = (
        external_anchor
        + "\n    // " + MARKER + "\n"
        + "    @FastNative\n"
        + "    private external fun lastModelLoadError(): String\n"
    )
    if kotlin.count(external_anchor) != 1:
        raise SystemExit("Unexpected Kotlin native load declaration; refusing an unverified patch")
    kotlin = kotlin.replace(external_anchor, external_replacement, 1)

    old_result = (
        "                load(pathToModel).let {\n"
        "                    // TODO-han.yin: find a better way to pass other error codes\n"
        "                    if (it != 0) throw UnsupportedArchitectureException()\n"
        "                }\n"
    )
    new_result = (
        "                load(pathToModel).let { nativeCode ->\n"
        "                    if (nativeCode != 0) {\n"
        "                        val nativeDetail = runCatching { lastModelLoadError() }\n"
        "                            .getOrNull()?.trim().orEmpty()\n"
        "                        val detail = nativeDetail.ifBlank {\n"
        "                            \"Native GGUF loader returned code $nativeCode without a detailed error.\"\n"
        "                        }\n"
        "                        throw IOException(\"Native GGUF model load failed (code=$nativeCode): $detail\")\n"
        "                    }\n"
        "                }\n"
    )
    if kotlin.count(old_result) != 1:
        raise SystemExit("Unexpected UnsupportedArchitectureException mapping; refusing an unverified patch")
    kotlin = kotlin.replace(old_result, new_result, 1)
    KOTLIN.write_text(kotlin)

# Verify that the generated native and Kotlin code expose the same JNI name.
assert MARKER in LOGGING.read_text()
assert MARKER in CPP.read_text()
assert "Java_com_arm_aichat_internal_InferenceEngineImpl_lastModelLoadError" in CPP.read_text()
assert "private external fun lastModelLoadError(): String" in KOTLIN.read_text()
assert "UnsupportedArchitectureException()" not in KOTLIN.read_text()
print("PASS: native GGML load errors are captured and returned to Kotlin")
