package com.lhht.ai_assistant

import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TRANSLATION_CHANNEL = "com.lhht.ai_assistant/mlkit_translation"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TRANSLATION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "translate" -> {
                    val text = call.argument<String>("text")?.trim().orEmpty()
                    val sourceTag = call.argument<String>("sourceTag")?.trim().orEmpty()
                    val targetTag = call.argument<String>("targetTag")?.trim().orEmpty()
                    translateOnDevice(text, sourceTag, targetTag, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun translateOnDevice(
        text: String,
        sourceTag: String,
        targetTag: String,
        result: MethodChannel.Result,
    ) {
        if (text.isBlank()) {
            result.error("EMPTY_TEXT", "Nội dung cần dịch đang trống.", null)
            return
        }

        val source = TranslateLanguage.fromLanguageTag(normalizeLanguageTag(sourceTag))
        val target = TranslateLanguage.fromLanguageTag(normalizeLanguageTag(targetTag))
        if (source == null || target == null) {
            result.error(
                "UNSUPPORTED_LANGUAGE",
                "ML Kit chưa hỗ trợ cặp ngôn ngữ $sourceTag → $targetTag.",
                null,
            )
            return
        }

        val options = TranslatorOptions.Builder()
            .setSourceLanguage(source)
            .setTargetLanguage(target)
            .build()
        val translator = Translation.getClient(options)

        // Không bắt buộc Wi‑Fi: người dùng có thể đang phiên dịch ngoài đường.
        // Model chỉ tải ở lần đầu cho mỗi ngôn ngữ rồi được cache trên thiết bị.
        val conditions = DownloadConditions.Builder().build()
        translator.downloadModelIfNeeded(conditions)
            .addOnSuccessListener {
                translator.translate(text)
                    .addOnSuccessListener { translated ->
                        translator.close()
                        result.success(translated)
                    }
                    .addOnFailureListener { error ->
                        translator.close()
                        result.error(
                            "TRANSLATE_FAILED",
                            error.message ?: "Không dịch được trên thiết bị.",
                            null,
                        )
                    }
            }
            .addOnFailureListener { error ->
                translator.close()
                result.error(
                    "MODEL_DOWNLOAD_FAILED",
                    error.message ?: "Không tải được model dịch trên thiết bị.",
                    null,
                )
            }
    }

    private fun normalizeLanguageTag(tag: String): String {
        val lower = tag.lowercase()
        return when {
            lower.startsWith("vi") -> "vi"
            lower.startsWith("en") -> "en"
            lower.startsWith("zh") -> "zh"
            lower.startsWith("ja") -> "ja"
            lower.startsWith("ko") -> "ko"
            lower.startsWith("fr") -> "fr"
            lower.startsWith("de") -> "de"
            lower.startsWith("es") -> "es"
            lower.startsWith("th") -> "th"
            lower.startsWith("ru") -> "ru"
            else -> lower.substringBefore('-')
        }
    }
}
