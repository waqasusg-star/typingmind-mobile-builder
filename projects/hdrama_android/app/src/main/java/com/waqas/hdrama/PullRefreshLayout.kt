package com.waqas.hdrama

import android.content.Context
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import kotlin.math.abs

/** Intercept only a downward pull begun at the top of the page; normal scrolling stays with WebView. */
class PullRefreshLayout(context: Context) : FrameLayout(context) {
    var canRefresh: (MotionEvent) -> Boolean = { false }
    var refresh: () -> Unit = {}
    var onPull: (Float) -> Unit = {}
    private var eligible = false
    private var pulling = false
    private var rejected = false
    private var startX = 0f
    private var startY = 0f
    private var distance = 0f
    private var refreshing = false
    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                startX = event.x; startY = event.y; distance = 0f; pulling = false; rejected = false
                eligible = !refreshing && canRefresh(event)
            }
            MotionEvent.ACTION_POINTER_DOWN -> { eligible = false; rejected = true }
            MotionEvent.ACTION_MOVE -> if (eligible && !rejected) {
                val x = event.x - startX; val y = event.y - startY
                if (y < -context.dp(12) || abs(x) > context.dp(12) && abs(x) > abs(y)) rejected = true
                else if (y > context.dp(12) && y > abs(x) * 1.3f) { pulling = true; return true }
            }
        }
        return pulling
    }
    override fun requestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {
        // WebView may claim its first scroll before the pull direction is known.
        if (disallowIntercept && eligible && !rejected && !refreshing) return
        super.requestDisallowInterceptTouchEvent(disallowIntercept)
    }
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!pulling) return super.onTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_MOVE -> {
                distance = (event.y - startY).coerceAtLeast(0f)
                onPull((distance / context.dp(100)).coerceIn(0f,1f))
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                distance = (event.y - startY).coerceAtLeast(0f)
                val trigger = event.actionMasked == MotionEvent.ACTION_UP && distance >= context.dp(100)
                pulling = false; eligible = false; onPull(0f)
                if (trigger && !refreshing) { refreshing = true; refresh() }
                performClick()
            }
            MotionEvent.ACTION_POINTER_DOWN -> { pulling = false; eligible = false; onPull(0f) }
        }
        return true
    }
    fun complete() { refreshing = false; onPull(0f) }
    override fun performClick(): Boolean { super.performClick(); return true }
}
