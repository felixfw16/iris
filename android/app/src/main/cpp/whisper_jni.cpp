#include <jni.h>
#include <string>
#include <thread>
#include <algorithm>
#include "whisper.h"

extern "C" JNIEXPORT jlong JNICALL Java_id_sahabatnetra_app_WhisperNative_init(JNIEnv *env, jobject, jstring path) {
    const char *model_path = env->GetStringUTFChars(path, nullptr);
    auto params = whisper_context_default_params();
    params.use_gpu = false;
    auto *ctx = whisper_init_from_file_with_params(model_path, params);
    env->ReleaseStringUTFChars(path, model_path);
    return reinterpret_cast<jlong>(ctx);
}
extern "C" JNIEXPORT jstring JNICALL Java_id_sahabatnetra_app_WhisperNative_transcribe(JNIEnv *env, jobject, jlong handle, jfloatArray samples) {
    auto *ctx = reinterpret_cast<whisper_context *>(handle);
    if (!ctx) return env->NewStringUTF("");
    auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = std::min(4u, std::max(1u, std::thread::hardware_concurrency()));
    params.language = "id";
    params.translate = false;
    params.no_context = true;
    params.single_segment = true;
    params.print_realtime = false;
    params.print_progress = false;
    params.print_timestamps = false;
    params.print_special = false;
    const auto length = env->GetArrayLength(samples);
    auto *data = env->GetFloatArrayElements(samples, nullptr);
    const int result = whisper_full(ctx, params, data, length);
    env->ReleaseFloatArrayElements(samples, data, JNI_ABORT);
    std::string text;
    if (result == 0) for (int i = 0; i < whisper_full_n_segments(ctx); ++i) text += whisper_full_get_segment_text(ctx, i);
    return env->NewStringUTF(text.c_str());
}
extern "C" JNIEXPORT void JNICALL Java_id_sahabatnetra_app_WhisperNative_free(JNIEnv *, jobject, jlong handle) {
    if (handle) whisper_free(reinterpret_cast<whisper_context *>(handle));
}
