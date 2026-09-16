package id.sahabatnetra.app

import java.nio.FloatBuffer
import org.junit.Assert.*
import org.junit.Test

class ObjectDecoderTest {
    private fun output() = FloatBuffer.allocate(605 * 8400)
    private fun put(data: FloatBuffer, anchor: Int, category: Int, score: Float, x: Float, y: Float, w: Float, h: Float) {
        for ((channel, value) in listOf(x, y, w, h).withIndex()) data.put(channel * 8400 + anchor, value)
        data.put((4 + category) * 8400 + anchor, score)
    }
    @Test fun portraitLetterboxRestoresCameraCoordinatesForDepth() {
        val output = output()
        put(output, 0, 164, .9f, 320f, 320f, 240f, 320f)
        val geometry = ObjectDecoder.letterbox(720, 960)
        assertEquals(80, geometry.left)
        assertEquals(0, geometry.top)
        val box = ObjectDecoder.decode(output, geometry).single()
        assertEquals(164, box.classId)
        assertEquals(180f, box.left, .001f)
        assertEquals(540f, box.right, .001f)
        assertEquals(240f, box.top, .001f)
        assertEquals(720f, box.bottom, .001f)
    }
    @Test fun overlappingHierarchyLabelsDoNotBecomeTwoObjects() {
        val output = output()
        put(output, 0, 381, .9f, 100f, 100f, 80f, 80f)
        put(output, 1, 322, .8f, 101f, 101f, 80f, 80f)
        put(output, 2, 164, .7f, 500f, 500f, 80f, 80f)
        val boxes = ObjectDecoder.decode(output, ObjectDecoder.letterbox(640, 640))
        assertEquals(listOf(381, 164), boxes.map { it.classId })
    }
    @Test fun tenDistinctObjectsSurviveInsteadOfOnlyThree() {
        val output = output()
        for (i in 0..11) put(output, i, 600, .9f, 20f + i * 50, 100f, 20f, 20f)
        assertEquals(10, ObjectDecoder.decode(output, ObjectDecoder.letterbox(640, 640)).size)
    }
    @Test fun invalidScoresAndPaddingDetectionsAreRejected() {
        val output = output()
        put(output, 0, 164, .39f, 320f, 320f, 40f, 40f)
        put(output, 1, 164, Float.NaN, 320f, 320f, 40f, 40f)
        put(output, 2, 164, .9f, 20f, 20f, 10f, 10f)
        put(output, 3, 164, .9f, Float.NaN, 320f, 40f, 40f)
        assertTrue(ObjectDecoder.decode(output, ObjectDecoder.letterbox(720, 960)).isEmpty())
    }
}
