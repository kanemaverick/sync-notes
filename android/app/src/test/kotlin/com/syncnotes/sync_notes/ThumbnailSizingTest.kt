package com.syncnotes.sync_notes

import org.junit.Assert.assertEquals
import org.junit.Test

class ThumbnailSizingTest {
    @Test fun smallPhotosNeverUseZeroSample() {
        assertEquals(1, thumbnailSampleSize(1, 1))
        assertEquals(1, thumbnailSampleSize(480, 320))
    }
    @Test fun cameraPhotosDecodeNearThumbnailSize() {
        assertEquals(8, thumbnailSampleSize(4096, 3072))
        assertEquals(16, thumbnailSampleSize(9000, 12000))
    }
    @Test fun largeDimensionsDoNotOverflow() {
        assertEquals(4194304, thumbnailSampleSize(Int.MAX_VALUE, Int.MAX_VALUE))
    }
    @Test(expected = IllegalArgumentException::class)
    fun invalidBoundsAreRejected() { thumbnailSampleSize(0, 100) }
}
