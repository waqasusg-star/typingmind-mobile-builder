package com.waqas.hdrama

import org.junit.Assert.*
import org.junit.Test

class ScreenSeekTest {
    @Test fun dragDirectionOriginAndBoundariesAreStable() {
        assertEquals(54_000L,ScreenSeek.target(24_000,120f,360,120_000))
        assertEquals(0L,ScreenSeek.target(24_000,-120f,360,120_000))
        assertEquals(120_000L,ScreenSeek.target(100_000,240f,360,120_000))
        assertEquals(10_000L,ScreenSeek.target(0,120f,360,30_000))
        assertEquals(24_000L,ScreenSeek.target(24_000,Float.NaN,360,120_000))
    }
}
