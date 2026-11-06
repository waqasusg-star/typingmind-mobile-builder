package com.waqas.hdrama

import android.view.MotionEvent
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class PullRefreshLayoutTest {
    private fun event(action: Int,x: Float,y: Float) = MotionEvent.obtain(0,200,action,x,y,0)
    @Test fun onlyTopDownwardPullRefreshesAndDuplicatePullWaitsForCompletion() {
        val layout = PullRefreshLayout(RuntimeEnvironment.getApplication()); var count = 0
        layout.canRefresh = { true }; layout.refresh = { count++ }
        fun pull() {
            layout.onInterceptTouchEvent(event(MotionEvent.ACTION_DOWN,10f,10f))
            if (layout.onInterceptTouchEvent(event(MotionEvent.ACTION_MOVE,10f,150f))) {
                layout.onTouchEvent(event(MotionEvent.ACTION_MOVE,10f,150f))
                layout.onTouchEvent(event(MotionEvent.ACTION_UP,10f,150f))
            }
        }
        pull(); assertEquals(1,count); pull(); assertEquals(1,count)
        layout.complete(); pull(); assertEquals(2,count)
        layout.complete(); layout.canRefresh = { false }; pull(); assertEquals(2,count)
    }
    @Test fun horizontalAndCancelledPullsDoNotRefresh() {
        val layout = PullRefreshLayout(RuntimeEnvironment.getApplication()); var count = 0
        layout.canRefresh = { true }; layout.refresh = { count++ }
        layout.onInterceptTouchEvent(event(MotionEvent.ACTION_DOWN,0f,0f))
        assertFalse(layout.onInterceptTouchEvent(event(MotionEvent.ACTION_MOVE,180f,10f)))
        assertFalse(layout.onInterceptTouchEvent(event(MotionEvent.ACTION_MOVE,180f,200f)))
        layout.onInterceptTouchEvent(event(MotionEvent.ACTION_DOWN,0f,0f))
        assertTrue(layout.onInterceptTouchEvent(event(MotionEvent.ACTION_MOVE,0f,150f)))
        layout.onTouchEvent(event(MotionEvent.ACTION_MOVE,0f,150f));layout.onTouchEvent(event(MotionEvent.ACTION_CANCEL,0f,150f))
        assertEquals(0,count)
    }
    @Test fun fastPullRefreshesThroughRealChildTouchDispatchEvenWithOneMove() {
        val layout = PullRefreshLayout(RuntimeEnvironment.getApplication()); var count = 0
        val child = android.view.View(layout.context).apply {
            setOnTouchListener { _,e ->
                if (e.actionMasked == MotionEvent.ACTION_DOWN) parent.requestDisallowInterceptTouchEvent(true)
                true
            }
        }
        layout.addView(child,android.widget.FrameLayout.LayoutParams(-1,-1))
        layout.canRefresh = { true }; layout.refresh = { count++ }
        layout.measure(android.view.View.MeasureSpec.makeMeasureSpec(320,android.view.View.MeasureSpec.EXACTLY),android.view.View.MeasureSpec.makeMeasureSpec(600,android.view.View.MeasureSpec.EXACTLY))
        layout.layout(0,0,320,600)
        layout.dispatchTouchEvent(event(MotionEvent.ACTION_DOWN,20f,20f))
        layout.dispatchTouchEvent(event(MotionEvent.ACTION_MOVE,20f,150f))
        layout.dispatchTouchEvent(event(MotionEvent.ACTION_UP,20f,150f))
        assertEquals(1,count)
    }

}
