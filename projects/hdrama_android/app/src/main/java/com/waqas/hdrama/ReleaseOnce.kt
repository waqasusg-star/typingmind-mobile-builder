package com.waqas.hdrama

/** Coordinates resource cleanup when cancellation and completion race. */
internal class ReleaseOnce(private val action: () -> Unit) {
    private val released = java.util.concurrent.atomic.AtomicBoolean(false)
    fun release() { if (released.compareAndSet(false, true)) action() }
}
