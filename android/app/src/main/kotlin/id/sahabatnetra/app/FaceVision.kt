package id.sahabatnetra.app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import org.json.JSONArray
import org.json.JSONObject
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.math.abs

class FaceVision(private val models: ModelFiles, private val store: SecureStore) : AutoCloseable {
    private val detector = FaceDetection.getClient(FaceDetectorOptions.Builder().setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
        .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL).setMinFaceSize(.15f).build())
    private var interpreter: Interpreter? = null
    private val samples = ArrayList<FloatArray>()
    private val poses = ArrayList<Pair<Float, Float>>()
    private var enrollingName = ""
    private var lastEnrollment = 0L
    private fun faces(bitmap: Bitmap): List<Face> = Tasks.await(detector.process(InputImage.fromBitmap(bitmap, 0)), 10, TimeUnit.SECONDS)
    private fun embedding(bitmap: Bitmap, face: Face): FloatArray {
        check(face.boundingBox.width() >= 90 && face.boundingBox.height() >= 90) { "Wajah terlalu jauh. Dekatkan kamera." }
        check(abs(face.headEulerAngleY) < 30 && abs(face.headEulerAngleX) < 25) { "Arahkan wajah lebih menghadap kamera." }
        val active = interpreter ?: Interpreter(models.file("face"), Interpreter.Options().setNumThreads(2)).also { interpreter = it }
        check(active.getInputTensor(0).shape().contentEquals(intArrayOf(1, 112, 112, 3))) { "Format model wajah tidak sesuai." }
        val left = face.getLandmark(FaceLandmark.LEFT_EYE)?.position ?: error("Mata belum terlihat jelas.")
        val right = face.getLandmark(FaceLandmark.RIGHT_EYE)?.position ?: error("Mata belum terlihat jelas.")
        // Sort image coordinates to avoid mirrored eye semantics on different ML Kit versions.
        val eyes = listOf(left, right).sortedBy { it.x }
        val transform = Matrix().apply { setPolyToPoly(floatArrayOf(eyes[0].x, eyes[0].y, eyes[1].x, eyes[1].y), 0, floatArrayOf(38.3f, 51.7f, 73.5f, 51.5f), 0, 2) }
        val aligned = Bitmap.createBitmap(112, 112, Bitmap.Config.ARGB_8888)
        Canvas(aligned).apply { drawColor(Color.BLACK); drawBitmap(bitmap, transform, Paint(Paint.FILTER_BITMAP_FLAG)) }
        val pixels = IntArray(112 * 112); aligned.getPixels(pixels, 0, 112, 0, 0, 112, 112); aligned.recycle()
        val brightness = pixels.map { (((it shr 16) and 255) + ((it shr 8) and 255) + (it and 255)) / 3.0 }
        check(brightness.average() in 35.0..225.0) { "Cahaya wajah kurang sesuai. Cari pencahayaan yang lebih merata." }
        val buffer = ByteBuffer.allocateDirect(112 * 112 * 3 * 4).order(ByteOrder.nativeOrder())
        for (pixel in pixels) for (shift in intArrayOf(16, 8, 0)) buffer.putFloat((((pixel shr shift) and 255) - 128f) / 128f)
        buffer.rewind()
        val outputSize = active.getOutputTensor(0).shape().last()
        val output = arrayOf(FloatArray(outputSize)); active.run(buffer, output)
        return VisionMath.normalize(output[0])
    }
    private fun profiles(): JSONArray = JSONArray(store.get("family_v1") ?: "[]")
    fun list(): List<Map<String, String>> {
        val data = profiles()
        return (0 until data.length()).map { data.getJSONObject(it) }.map { mapOf("id" to it.getString("id"), "name" to it.getString("name")) }
    }
    fun delete(id: String) {
        val old = profiles(); val updated = JSONArray()
        for (i in 0 until old.length()) if (old.getJSONObject(i).getString("id") != id) updated.put(old.getJSONObject(i))
        store.put("family_v1", updated.toString())
    }
    fun enroll(bitmap: Bitmap, name: String): Int {
        require(name.isNotBlank() && name.length <= 40) { "Nama panggilan harus 1 sampai 40 karakter." }
        val detected = faces(bitmap)
        check(detected.size == 1) { "Pendaftaran memerlukan tepat satu wajah di kamera." }
        if (enrollingName != name) { cancelEnrollment(); enrollingName = name }
        check(System.currentTimeMillis() - lastEnrollment > 1000) { "Tunggu sejenak dan ubah arah wajah." }
        val face = detected.first()
        val vector = embedding(bitmap, face)
        if (samples.isNotEmpty()) check(VisionMath.cosine(samples.first(), vector) >= .55f) { "Wajah berbeda dari foto pertama. Batalkan untuk mendaftarkan orang lain." }
        val pose = face.headEulerAngleX to face.headEulerAngleY
        check(poses.none { abs(it.first - pose.first) < 4 && abs(it.second - pose.second) < 4 }) { "Foto terlalu mirip. Hadapkan wajah sedikit ke kiri, kanan, atas, atau bawah." }
        samples.add(vector); poses.add(pose); lastEnrollment = System.currentTimeMillis()
        if (samples.size < 5) return samples.size
        val data = profiles()
        check(data.length() < 20) { "Maksimum 20 profil. Hapus profil yang tidak digunakan." }
        val vectors = JSONArray(); samples.forEach { vectors.put(JSONArray(it.toList())) }
        data.put(JSONObject().put("id", UUID.randomUUID().toString()).put("name", name).put("model", "mobilefacenet-112-v1").put("vectors", vectors))
        store.put("family_v1", data.toString()); cancelEnrollment()
        return 5
    }
    fun recognize(bitmap: Bitmap): String {
        val enrolled = profiles()
        if (enrolled.length() == 0) return "Belum ada wajah keluarga terdaftar. Buka Kelola wajah keluarga bersama pendamping."
        val detected = faces(bitmap)
        if (detected.isEmpty()) return "Belum terlihat wajah. Arahkan kamera ke orang di depan Anda."
        return detected.take(3).joinToString(". ", postfix = ".") { face ->
            val location = VisionMath.position(face.boundingBox.exactCenterX() / bitmap.width)
            try {
                val vector = embedding(bitmap, face)
                val scores = (0 until enrolled.length()).map { i ->
                    val p = enrolled.getJSONObject(i); val vectors = p.getJSONArray("vectors")
                    val similarities = (0 until vectors.length()).map { j -> val a = vectors.getJSONArray(j); VisionMath.cosine(vector, FloatArray(a.length()) { a.getDouble(it).toFloat() }) }.sortedDescending()
                    p.getString("id") to similarities.take(3).average().toFloat()
                }
                val id = VisionMath.identity(scores)
                val name = if (id == null) "Wajah belum dikenali" else (0 until enrolled.length()).map { enrolled.getJSONObject(it) }.first { it.getString("id") == id }.getString("name")
                "$name di $location"
            } catch (_: IllegalStateException) { "Wajah di $location belum terlihat jelas" }
        }
    }
    fun cancelEnrollment() { samples.clear(); poses.clear(); enrollingName = ""; lastEnrollment = 0 }
    override fun close() { cancelEnrollment(); interpreter?.close(); detector.close() }
}
