package id.sahabatnetra.app

import kotlin.math.abs
import kotlin.math.sqrt

object VisionMath {
    fun normalize(vector: FloatArray): FloatArray {
        val norm = sqrt(vector.sumOf { (it * it).toDouble() }).toFloat()
        require(norm.isFinite() && norm > 1e-6f) { "Embedding wajah tidak valid." }
        return FloatArray(vector.size) { vector[it] / norm }
    }
    fun cosine(a: FloatArray, b: FloatArray): Float {
        require(a.size == b.size)
        return a.indices.sumOf { (a[it] * b[it]).toDouble() }.toFloat()
    }
    fun identity(scores: List<Pair<String, Float>>, threshold: Float = .72f, margin: Float = .08f): String? {
        val sorted = scores.sortedByDescending { it.second }
        val best = sorted.firstOrNull() ?: return null
        if (!best.second.isFinite() || best.second < threshold) return null
        if (sorted.size > 1 && best.second - sorted[1].second < margin) return null
        return best.first
    }
    fun median(values: List<Float>): Float? {
        val sorted = values.filter { it.isFinite() }.sorted()
        if (sorted.isEmpty()) return null
        return if (sorted.size % 2 == 0) (sorted[sorted.size / 2 - 1] + sorted[sorted.size / 2]) / 2 else sorted[sorted.size / 2]
    }
    /** No metres from relative-depth maps; inputs must already be metric model outputs. */
    fun reliableDepth(values: List<Float>): Float? {
        val valid = values.filter { it.isFinite() && it >= .5f && it <= 5f }
        if (values.isEmpty() || valid.size < values.size * .7) return null
        val center = median(valid) ?: return null
        val deviation = median(valid.map { abs(it - center) }) ?: return null
        return if (deviation <= maxOf(.25f, center * .2f)) center else null
    }
    fun position(centerX: Float): String = when { centerX < .35f -> "kiri"; centerX > .65f -> "kanan"; else -> "depan" }
    fun stableDistance(readings: List<Float?>): Float? {
        if (readings.size < 3 || readings.any { it == null || !it.isFinite() }) return null
        val valid = readings.filterNotNull()
        val median = median(valid) ?: return null
        return if (valid.all { abs(it - median) <= maxOf(.5f, median * .2f) }) median else null
    }
}
