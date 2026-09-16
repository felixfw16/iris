package id.sahabatnetra.app

import org.junit.Assert.*
import org.junit.Test

class VisionMathTest {
    @Test fun unstableOrMissingTemporalDepthIsRejected() {
        assertNull(VisionMath.stableDistance(listOf(1f, 4f, 2f)))
        assertNull(VisionMath.stableDistance(listOf(2f, null, 2.1f)))
        assertEquals(2f, VisionMath.stableDistance(listOf(1.9f, 2f, 2.1f))!!, .01f)
    }
    @Test fun unknownFaceIsRejected() {
        assertNull(VisionMath.identity(listOf("wife" to .4f, "child" to .3f)))
        assertNull(VisionMath.identity(emptyList()))
    }
    @Test fun ambiguousSimilarFacesAreRejected() {
        assertNull(VisionMath.identity(listOf("wife" to .84f, "child" to .81f)))
        assertEquals("wife", VisionMath.identity(listOf("wife" to .9f, "child" to .6f)))
    }
    @Test fun depthRequiresAdequateValidCoverage() {
        assertNull(VisionMath.reliableDepth(listOf(Float.NaN, 2f, 99f)))
        assertNull(VisionMath.reliableDepth(listOf(.1f, .2f)))
        assertEquals(2f, VisionMath.reliableDepth(listOf(1.9f, 2f, 2.1f))!!, .01f)
    }
    @Test fun dispersedDepthDoesNotBecomePreciseDistance() {
        assertNull(VisionMath.reliableDepth(listOf(.5f, 1f, 4f, 5f)))
    }
    @Test fun normalizationPreservesCosineScaleInvariance() {
        val a = VisionMath.normalize(floatArrayOf(1f, 2f, 3f))
        val b = VisionMath.normalize(floatArrayOf(2f, 4f, 6f))
        assertEquals(1f, VisionMath.cosine(a, b), .00001f)
    }
}
