package id.sahabatnetra.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.RectF
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterFragmentActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private var sink: EventChannel.EventSink? = null
    private lateinit var store: SecureStore
    private lateinit var models: ModelFiles
    private lateinit var objects: ObjectVision
    private lateinit var depth: DepthVision
    private lateinit var faces: FaceVision
    private lateinit var speech: SpeechService
    private lateinit var gpt: GptService
    private lateinit var qwen: QwenService
    private lateinit var metrics: Metrics
    private val ocr by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }
    var cameraView: CameraView? = null
    private val cameras = ArrayList<CameraView>()
    private val frameLock = Any()
    private var frame: Bitmap? = null
    private var frameAt = 0L
    @Volatile private var scanning = false
    @Volatile private var generation = 0
    @Volatile private var foreground = true
    private var lastAnalysisAt = 0L
    private var cameraPermissionResult: MethodChannel.Result? = null
    private var microphoneResult: MethodChannel.Result? = null
    private var exportResult: MethodChannel.Result? = null
    private var initialized = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        store = SecureStore(this); models = ModelFiles(this); metrics = Metrics(this)
        objects = ObjectVision(models); depth = DepthVision(models); faces = FaceVision(models, store)
        speech = SpeechService(this, models) { message -> emit(mapOf("type" to "status", "message" to message)) }
        gpt = GptService(store)
        qwen = QwenService(this, models) { message -> emit(mapOf("type" to "status", "message" to message)) }
        initialized = true
        flutterEngine.platformViewsController.registry.registerViewFactory("id.sahabatnetra/camera", CameraFactory(this))
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "id.sahabatnetra/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "id.sahabatnetra/control").setMethodCallHandler(::handle)
    }
    fun emit(event: Map<String, Any?>) { main.post { if (!isDestroyed) sink?.success(event) } }
    fun attachCamera(view: CameraView) { cameras.add(view); cameraView = view }
    fun detachCamera(view: CameraView) {
        cameras.remove(view)
        if (cameraView === view) { cameraView = cameras.lastOrNull(); clearFrame(); cameraView?.rebind() }
    }
    private fun permission(value: String) = ContextCompat.checkSelfPermission(this, value) == PackageManager.PERMISSION_GRANTED
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "status" -> { speech.refreshVoice(); result.success(mapOf("models" to models.status(), "ttsReady" to speech.ready, "cameraPermission" to permission(Manifest.permission.CAMERA), "hasApiKey" to (store.get("api_key")?.isNotBlank() == true), "gptModel" to (store.get("gpt_model") ?: ""))) }
                "requestCamera" -> {
                    if (permission(Manifest.permission.CAMERA)) { cameraView?.bind(); result.success(true) }
                    else if (cameraPermissionResult != null) result.error("busy", "Permintaan izin kamera sedang berjalan.", null)
                    else { cameraPermissionResult = result; ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), 101) }
                }
                "startScan" -> {
                    check(permission(Manifest.permission.CAMERA)) { "Izin kamera diperlukan." }
                    check(models.status()["objects"] == true) { "Model objek belum dipasang dalam APK." }
                    generation = call.argument<Int>("generation") ?: generation + 1
                    scanning = true; lastAnalysisAt = 0; result.success(null); haptic()
                }
                "stop" -> { scanning = false; generation = call.argument<Int>("generation") ?: generation + 1; gpt.cancel(); qwen.cancel(); speech.stop(); result.success(null) }
                "speak" -> { speech.speak(call.argument<String>("text") ?: ""); result.success(null) }
                "readText" -> runTask(result, "ocr") {
                    val image = snapshot()
                    try {
                        val text = Tasks.await(ocr.process(InputImage.fromBitmap(image, 0)), 15, TimeUnit.SECONDS).text
                        text.take(4000).ifBlank { "Tulisan belum terbaca. Dekatkan kamera, tahan stabil, dan pastikan cahaya cukup." }
                    } finally { image.recycle() }
                }
                "recognizeFamily" -> runTask(result, "family") { val image = snapshot(); try { faces.recognize(image) } finally { image.recycle() } }
                "measureDistance" -> runTask(result, "depth") {
                    val token = generation
                    var previous = emptyList<SeenObject>()
                    var readings = emptyList<MutableList<Float?>>()
                    var imageWidth = 1
                    repeat(3) { pass ->
                        check(token == generation) { "Pengukuran dibatalkan." }
                        val image = snapshot()
                        try {
                            val seen = objects.detect(image)
                            imageWidth = image.width
                            if (seen.isNotEmpty()) depth.measure(image, seen)
                            if (pass == 0) { previous = seen; readings = seen.map { mutableListOf(it.meters) } }
                            else {
                                for ((index, item) in previous.withIndex()) {
                                    val matched = seen.filter { it.label == item.label }.maxByOrNull { overlap(item.box, it.box) }
                                    if (matched != null && overlap(item.box, matched.box) >= .5f) {
                                        readings[index].add(matched.meters); item.box.set(matched.box)
                                    } else readings[index].add(null)
                                }
                            }
                        } finally { image.recycle() }
                    }
                    for ((index, item) in previous.withIndex()) item.meters = VisionMath.stableDistance(readings[index])
                    mapOf("items" to previous.map { it.map(imageWidth) })
                }
                "describePhoto" -> runTask(result, "gpt") { val image = snapshot(); try { gpt.describe(image, call.argument<Boolean>("online") == true) } finally { image.recycle() } }
                "requestMicrophone" -> {
                    if (permission(Manifest.permission.RECORD_AUDIO)) result.success(true)
                    else if (microphoneResult != null) result.error("busy", "Permintaan mikrofon sedang berjalan.", null)
                    else { microphoneResult = result; ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), 102) }
                }
                "listen" -> {
                    check(permission(Manifest.permission.RECORD_AUDIO)) { "Aktifkan izin mikrofon terlebih dahulu." }
                    val token = generation
                    runTask(result, "speech") { speech.listen { token == generation } }
                }
                "askQwen" -> {
                    check(permission(Manifest.permission.RECORD_AUDIO)) { "Aktifkan izin mikrofon terlebih dahulu." }
                    val token = generation
                    runTask(result, "qwen") {
                        val question = speech.listen { token == generation }.trim()
                        qwen.answer(question, call.argument<Boolean>("thinking") == true,
                            tools = { name ->
                                check(token == generation) { "Permintaan dibatalkan." }
                                emit(mapOf("type" to "status", "generation" to token, "message" to "Memeriksa kamera untuk menjawab pertanyaan Anda."))
                                val output = org.json.JSONObject().put("tool", name)
                                try {
                                    val image = snapshot()
                                    try {
                                        output.put("capturedAt", System.currentTimeMillis()).put("status", "ok")
                                        when (name) {
                                            "detect_objects" -> output.put("objects", org.json.JSONArray(objects.detect(image).take(10).map {
                                                mapOf("label" to it.label, "position" to VisionMath.position(it.box.centerX() / image.width), "confidence" to it.score.toDouble())
                                            })).put("distanceMeasured", false)
                                            "read_text" -> output.put("text", Tasks.await(ocr.process(InputImage.fromBitmap(image, 0)), 15, TimeUnit.SECONDS).text.take(1600))
                                            else -> error("Alat tidak dikenal.")
                                        }
                                    } finally { image.recycle() }
                                } catch (error: Exception) {
                                    output.put("status", "unavailable").put("message", "Pengamatan kamera belum tersedia.")
                                }
                                check(token == generation) { "Permintaan dibatalkan." }
                                output.toString()
                            }) { token == generation }
                    }
                }
                "saveSettings" -> {
                    val key = call.argument<String>("apiKey") ?: ""; val model = call.argument<String>("model") ?: ""
                    require(model.length <= 150 && !model.contains('\n')) { "Model ID tidak valid." }
                    if (key.isNotBlank()) { require(key.length in 20..1024 && !key.any { it.isWhitespace() }) { "Format API key tidak valid." }; store.put("api_key", key) }
                    store.put("gpt_model", model); result.success(null)
                }
                "deleteApiKey" -> { gpt.cancel(); store.remove("api_key"); result.success(null) }
                "listFamily" -> result.success(faces.list())
                "deleteFamily" -> runTask(result, "family_delete") { faces.delete(call.argument<String>("id") ?: ""); null }
                "enrollFace" -> runTask(result, "family_enroll") { val image = snapshot(); try { faces.enroll(image, call.argument<String>("name")?.trim() ?: "") } finally { image.recycle() } }
                "cancelEnrollment" -> { worker.execute { faces.cancelEnrollment() }; result.success(null) }
                "ttsSettings" -> { startActivity(Intent("com.android.settings.TTS_SETTINGS")); result.success(null) }
                "exportMetrics" -> {
                    check(exportResult == null) { "Ekspor sedang berjalan." }; exportResult = result
                    startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("text/csv").putExtra(Intent.EXTRA_TITLE, "sahabat-netra-metrics.csv"), 103)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) { result.error("operation", error.message ?: "Operasi belum dapat dilakukan.", null) }
    }
    private fun runTask(result: MethodChannel.Result, task: String, action: () -> Any?) {
        scanning = false; speech.stop()
        if (!busy.compareAndSet(false, true)) { result.error("busy", "Pemrosesan sebelumnya masih selesai. Tunggu sebentar.", null); return }
        val token = generation
        worker.execute {
            val started = System.currentTimeMillis(); var success = false
            try {
                if (token != generation) error("Permintaan dibatalkan.")
                val value = action(); success = true
                main.post { if (token == generation && !isDestroyed) { result.success(value); haptic() } else result.error("cancelled", "Permintaan dibatalkan.", null) }
            } catch (error: Throwable) {
                val message = when (error) {
                    is OutOfMemoryError -> "Memori perangkat tidak cukup. Tutup aplikasi lain lalu coba lagi."
                    is UnsatisfiedLinkError -> "Pustaka model native tidak tersedia pada APK ini."
                    is IllegalStateException, is IllegalArgumentException -> error.message ?: "Masukan belum sesuai."
                    else -> "Pemrosesan $task gagal. Periksa model dan coba lagi."
                }
                main.post { result.error("processing", message, null) }
            } finally { busy.set(false); runCatching { metrics.record(task, System.currentTimeMillis() - started, success) } }
        }
    }
    fun receiveFrame(bitmap: Bitmap, capturedAt: Long) {
        if (!foreground) { bitmap.recycle(); return }
        synchronized(frameLock) { frame?.recycle(); frame = bitmap; frameAt = capturedAt }
        if (!scanning || capturedAt - lastAnalysisAt < 900 || !busy.compareAndSet(false, true)) return
        lastAnalysisAt = capturedAt
        val token = generation
        val image = synchronized(frameLock) { frame?.copy(Bitmap.Config.ARGB_8888, false) }
        if (image == null) { busy.set(false); return }
        worker.execute {
            val started = System.currentTimeMillis(); var success = false
            try {
                if (token != generation || !scanning) return@execute
                val seen = objects.detect(image); success = true
                if (token == generation && scanning) emit(mapOf("type" to "objects", "generation" to token, "capturedAt" to capturedAt, "items" to seen.map { it.map(image.width) }))
            } catch (_: Throwable) { scanning = false; emit(mapOf("type" to "error", "message" to "Deteksi objek gagal. Periksa paket model dan mulai kembali.")) }
            finally { image.recycle(); busy.set(false); runCatching { metrics.record("objects", System.currentTimeMillis() - started, success) } }
        }
    }
    private fun snapshot(): Bitmap {
        repeat(30) {
            val current = synchronized(frameLock) {
                if (foreground && System.currentTimeMillis() - frameAt <= 2500) frame?.copy(Bitmap.Config.ARGB_8888, false) else null
            }
            if (current != null) return current
            Thread.sleep(50)
        }
        error("Kamera belum siap. Tunggu sebentar lalu coba lagi.")
    }
    fun clearFrame() { synchronized(frameLock) { frame?.recycle(); frame = null; frameAt = 0 } }
    @Suppress("DEPRECATION") private fun haptic() { (getSystemService(VIBRATOR_SERVICE) as? Vibrator)?.vibrate(VibrationEffect.createOneShot(35, VibrationEffect.DEFAULT_AMPLITUDE)) }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 101) { val allowed = permission(Manifest.permission.CAMERA); if (allowed) cameraView?.bind(); cameraPermissionResult?.success(allowed); cameraPermissionResult = null; emit(mapOf("type" to "ready")) }
        if (requestCode == 102) { microphoneResult?.success(permission(Manifest.permission.RECORD_AUDIO)); microphoneResult = null }
    }
    @Deprecated("Platform API") override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 103) {
            val result = exportResult; exportResult = null
            try { val uri = data?.data; if (resultCode == RESULT_OK && uri != null) { contentResolver.openOutputStream(uri)?.use { it.write(metrics.bytes()) } ?: error("Berkas tidak dapat dibuka."); result?.success("Metrik disimpan.") } else result?.success("Ekspor dibatalkan.") }
            catch (_: Exception) { result?.error("export", "Ekspor gagal.", null) }
        }
    }
    override fun onResume() { super.onResume(); foreground = true }
    override fun onPause() { foreground = false; if (initialized) { scanning = false; generation++; speech.stop(); gpt.cancel(); qwen.cancel(); clearFrame() }; super.onPause() }
    private fun overlap(a: RectF, b: RectF): Float {
        val intersection = RectF(a)
        if (!intersection.intersect(b)) return 0f
        val area = intersection.width() * intersection.height()
        return area / (a.width() * a.height() + b.width() * b.height() - area).coerceAtLeast(1f)
    }
    override fun onDestroy() {
        if (initialized) { scanning = false; generation++; gpt.cancel(); qwen.cancel(); speech.stop(); worker.execute { objects.close(); depth.close(); faces.close(); qwen.close(); speech.close(); ocr.close() }; worker.shutdown(); clearFrame() }
        super.onDestroy()
    }
}
