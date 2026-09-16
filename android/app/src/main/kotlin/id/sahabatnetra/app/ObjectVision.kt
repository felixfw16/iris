package id.sahabatnetra.app

import android.graphics.Bitmap
import android.graphics.RectF
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import org.json.JSONArray
import java.nio.FloatBuffer

data class SeenObject(val label: String, val score: Float, val box: RectF, var meters: Float? = null) {
    fun map(width: Int): Map<String, Any?> = mapOf("label" to label, "confidence" to score.toDouble(), "position" to VisionMath.position(box.centerX() / width), "meters" to meters?.toDouble(), "box" to listOf(box.left.toDouble(), box.top.toDouble(), box.right.toDouble(), box.bottom.toDouble()))
}

/** Borrows the caller's bitmap. Detection must never close/recycle it: depth uses it next. */
class ObjectVision(private val models: ModelFiles) : AutoCloseable {
    private val runtime = OrtEnvironment.getEnvironment()
    private var session: OrtSession? = null
    private val labels by lazy {
        val array = JSONArray(models.file("objectLabels").readText())
        check(array.length() == ObjectDecoder.CLASSES) { "Label model objek tidak sesuai." }
        List(array.length()) { array.getString(it) }
    }

    fun detect(bitmap: Bitmap): List<SeenObject> {
        val active = session ?: OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(2)
            options.setInterOpNumThreads(1)
            runtime.createSession(models.file("objects").absolutePath, options).also { session = it }
        }
        val geometry = ObjectDecoder.letterbox(bitmap.width, bitmap.height)
        val scaled = Bitmap.createScaledBitmap(bitmap, geometry.width, geometry.height, true)
        val pixels = IntArray(geometry.width * geometry.height)
        try {
            scaled.getPixels(pixels, 0, geometry.width, 0, 0, geometry.width, geometry.height)
        } finally {
            if (scaled !== bitmap) scaled.recycle()
        }
        val area = ObjectDecoder.SIZE * ObjectDecoder.SIZE
        val data = FloatArray(3 * area) { 114f / 255f }
        for (i in pixels.indices) {
            val target = (i / geometry.width + geometry.top) * ObjectDecoder.SIZE + i % geometry.width + geometry.left
            val pixel = pixels[i]
            data[target] = ((pixel shr 16) and 255) / 255f
            data[area + target] = ((pixel shr 8) and 255) / 255f
            data[2 * area + target] = (pixel and 255) / 255f
        }
        return OnnxTensor.createTensor(runtime, FloatBuffer.wrap(data), longArrayOf(1, 3, 640, 640)).use { input ->
            active.run(mapOf(active.inputNames.first() to input)).use { result ->
                val output = result[0] as OnnxTensor
                check(output.info.shape.contentEquals(longArrayOf(1, 605, 8400))) { "Format model objek tidak sesuai." }
                ObjectDecoder.decode(output.floatBuffer, geometry).map {
                    SeenObject(labels[it.classId], it.score, RectF(it.left, it.top, it.right, it.bottom))
                }
            }
        }
    }

    override fun close() { session?.close(); session = null }
}
