package id.sahabatnetra.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.AudioAttributes
import android.speech.tts.TextToSpeech
import androidx.core.content.ContextCompat
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.sqrt

class SpeechService(private val context: Context, private val models: ModelFiles, private val notify: (String) -> Unit) : AutoCloseable {
    private var tts: TextToSpeech? = null
    @Volatile var ready = false; private set
    private var initialized = false
    private val recording = AtomicBoolean(false)
    private val recordingEpoch = AtomicInteger(0)
    private var whisperContext = 0L
    init {
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                initialized = true
                refreshVoice()
                if (!ready) notify("Pasang suara offline Bahasa Indonesia pada pengaturan suara Android.")
            } else notify("Mesin pembaca suara belum tersedia.")
        }
    }
    fun refreshVoice() {
        if (!initialized) return
        val voice = tts?.voices?.filter { it.locale.language == "id" && !it.isNetworkConnectionRequired && !it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) }?.maxByOrNull { it.quality }
        ready = voice != null
        if (voice != null) {
            tts?.voice = voice; tts?.setSpeechRate(.9f)
            tts?.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
        }
    }
    fun speak(text: String) {
        check(ready) { "Suara offline belum siap. Hasil tetap tersedia di layar." }
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "netra-${System.nanoTime()}")
    }
    fun stop() { recordingEpoch.incrementAndGet(); recording.set(false); tts?.stop() }
    fun listen(isCurrent: () -> Boolean = { true }): String {
        val epoch = recordingEpoch.get()
        check(ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) { "Izin mikrofon diperlukan untuk perintah suara." }
        val model = models.file("speech")
        if (whisperContext == 0L) whisperContext = WhisperNative.init(model.absolutePath)
        check(whisperContext != 0L) { "Model pengenal suara tidak dapat dimuat." }
        val size = maxOf(AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT), 4096)
        val recorder = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, size)
        check(recorder.state == AudioRecord.STATE_INITIALIZED) { recorder.release(); "Mikrofon tidak dapat dibuka." }
        val samples = FloatArray(16000 * 30); var offset = 0
        val buffer = ShortArray(320)
        val endpoint = VoiceEndpoint()
        recording.set(true)
        try {
            if (epoch != recordingEpoch.get() || !isCurrent()) return ""
            recorder.startRecording()
            notify("Mikrofon siap. Silakan bicara; rekaman berhenti otomatis setelah Anda selesai.")
            val deadline = android.os.SystemClock.elapsedRealtime() + 32000
            while (recording.get() && isCurrent() && epoch == recordingEpoch.get() && offset < samples.size && android.os.SystemClock.elapsedRealtime() < deadline) {
                val count = recorder.read(buffer, 0, minOf(buffer.size, samples.size - offset))
                check(count > 0) { "Rekaman mikrofon terputus." }
                var energy = 0.0
                for (i in 0 until count) {
                    val sample = buffer[i] / 32768f
                    samples[offset++] = sample
                    energy += sample * sample
                }
                if (endpoint.accept(sqrt(energy / count), count)) break
            }
        } finally {
            if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) recorder.stop()
            recorder.release()
        }
        if (!recording.getAndSet(false) || epoch != recordingEpoch.get() || !isCurrent()) return ""
        if (!endpoint.hasSpeech()) return ""
        notify("Memahami ucapan Anda.")
        val text = WhisperNative.transcribe(whisperContext, samples.copyOfRange(endpoint.startSample(), minOf(offset, endpoint.endSample())))
        return if (epoch == recordingEpoch.get() && isCurrent()) text else ""
    }
    override fun close() { stop(); tts?.shutdown(); if (whisperContext != 0L) WhisperNative.free(whisperContext); whisperContext = 0 }
}

object WhisperNative {
    init { System.loadLibrary("netra_whisper") }
    external fun init(path: String): Long
    external fun transcribe(handle: Long, samples: FloatArray): String
    external fun free(handle: Long)
}
