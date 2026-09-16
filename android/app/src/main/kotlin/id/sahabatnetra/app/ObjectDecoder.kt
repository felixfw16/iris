package id.sahabatnetra.app

import java.nio.FloatBuffer
import kotlin.math.roundToInt

/** The same letterbox geometry is used for RGB preprocessing and restoring camera boxes. */
object ObjectDecoder {
    const val SIZE = 640
    const val CLASSES = 601
    const val ANCHORS = 8400
    const val MAX_RESULTS = 10
    const val MIN_SCORE = .4f
    data class Geometry(val sourceWidth: Int, val sourceHeight: Int, val width: Int, val height: Int, val left: Int, val top: Int) {
        val scaleX get() = width.toFloat() / sourceWidth
        val scaleY get() = height.toFloat() / sourceHeight
    }
    data class Box(val classId: Int, val score: Float, val left: Float, val top: Float, val right: Float, val bottom: Float)

    fun letterbox(width: Int, height: Int): Geometry {
        require(width > 0 && height > 0)
        val scale = minOf(SIZE.toFloat() / width, SIZE.toFloat() / height)
        val w = (width * scale).roundToInt().coerceIn(1, SIZE)
        val h = (height * scale).roundToInt().coerceIn(1, SIZE)
        return Geometry(width, height, w, h, (SIZE - w) / 2, (SIZE - h) / 2)
    }

    fun decode(output: FloatBuffer, geometry: Geometry): List<Box> {
        require(output.limit() == (4 + CLASSES) * ANCHORS)
        val candidates = ArrayList<Box>()
        val scores = FloatArray(ANCHORS) { MIN_SCORE }
        val classes = IntArray(ANCHORS) { -1 }
        // Traverse each contiguous score row to avoid strided reads on the phone CPU.
        for (category in 0 until CLASSES) {
            val offset = (category + 4) * ANCHORS
            for (anchor in 0 until ANCHORS) {
                val value = output.get(offset + anchor)
                if (value.isFinite() && value <= 1f && value >= scores[anchor]) {
                    scores[anchor] = value
                    classes[anchor] = category
                }
            }
        }
        for (anchor in 0 until ANCHORS) {
            val score = scores[anchor]
            val classId = classes[anchor]
            if (classId < 0) continue
            val x = output.get(anchor); val y = output.get(ANCHORS + anchor)
            val w = output.get(2 * ANCHORS + anchor); val h = output.get(3 * ANCHORS + anchor)
            if (!x.isFinite() || !y.isFinite() || !w.isFinite() || !h.isFinite() || w <= 0 || h <= 0) continue
            val left = ((x - w / 2 - geometry.left) / geometry.scaleX).coerceIn(0f, geometry.sourceWidth.toFloat())
            val right = ((x + w / 2 - geometry.left) / geometry.scaleX).coerceIn(0f, geometry.sourceWidth.toFloat())
            val top = ((y - h / 2 - geometry.top) / geometry.scaleY).coerceIn(0f, geometry.sourceHeight.toFloat())
            val bottom = ((y + h / 2 - geometry.top) / geometry.scaleY).coerceIn(0f, geometry.sourceHeight.toFloat())
            if (right > left && bottom > top) candidates.add(Box(classId, score, left, top, right, bottom))
        }
        // Class-agnostic NMS also suppresses OIV7 parent/child duplicates (e.g. person/man).
        val kept = ArrayList<Box>()
        for (candidate in candidates.sortedByDescending { it.score }.take(300)) {
            if (kept.none { overlap(it, candidate) > .5f }) kept.add(candidate)
            if (kept.size == MAX_RESULTS) break
        }
        return kept
    }

    private fun overlap(a: Box, b: Box): Float {
        val intersection = maxOf(0f, minOf(a.right, b.right) - maxOf(a.left, b.left)) *
            maxOf(0f, minOf(a.bottom, b.bottom) - maxOf(a.top, b.top))
        val union = (a.right - a.left) * (a.bottom - a.top) + (b.right - b.left) * (b.bottom - b.top) - intersection
        return if (union > 0f) intersection / union else 0f
    }
}
