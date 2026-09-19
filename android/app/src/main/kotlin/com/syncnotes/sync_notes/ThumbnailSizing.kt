package com.syncnotes.sync_notes

internal fun thumbnailSampleSize(width: Int, height: Int, edge: Int = 480): Int {
    require(width > 0 && height > 0 && edge > 0)
    val longest = maxOf(width, height)
    var sample = 1 // BitmapFactory.Options.inSampleSize defaults to ZERO.
    while (longest.toLong() / (sample.toLong() * 2) >= edge) sample *= 2
    return sample
}
