package com.waqas.hdrama

import org.junit.Assert.*
import org.junit.Test

class EpisodeSwipeTest {
    @Test fun upAdvancesAndDownReturnsOneEpisode() {
        assertEquals(2,EpisodeSwipe.target(1,4,-200f,800,0f,1f))
        assertEquals(0,EpisodeSwipe.target(1,4,200f,800,0f,1f))
    }
    @Test fun firstAndLastEpisodesHaveNoWrap() {
        assertNull(EpisodeSwipe.target(0,4,200f,800,1500f,1f))
        assertNull(EpisodeSwipe.target(3,4,-200f,800,-1500f,1f))
    }
    @Test fun shortSlowAndJitterGesturesDoNotChangeEpisode() {
        assertNull(EpisodeSwipe.target(1,4,-30f,800,-100f,1f))
        assertNull(EpisodeSwipe.target(1,4,-10f,800,-5000f,1f))
    }
    @Test fun shortFastFlingCanChangeEpisode() { assertEquals(2,EpisodeSwipe.target(1,4,-60f,800,-1500f,1f)) }
    @Test fun directionLocksKeepVerticalPagingSeparateFromSeeking() {
        assertEquals(EpisodeSwipe.Axis.NONE,EpisodeSwipe.axis(10f,12f,20f))
        assertEquals(EpisodeSwipe.Axis.VERTICAL,EpisodeSwipe.axis(15f,-100f,20f))
        assertEquals(EpisodeSwipe.Axis.HORIZONTAL,EpisodeSwipe.axis(-100f,15f,20f))
        assertEquals(EpisodeSwipe.Axis.NONE,EpisodeSwipe.axis(100f,100f,20f))
    }
}
