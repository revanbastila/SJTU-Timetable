package cn.sjtu.jiaotong_course

import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/** Course/account request ownership is independent of UI execution and of
 * other courses. Both native scheduling sources and manual reads use this. */
class AttendancePolling<T>(
    private val clock: () -> Long,
    private val successful: (T) -> Boolean,
    private val cacheable: (T) -> Boolean = { true }
) {
    private class Slot<T> {
        var inFlight: CompletableFuture<T>? = null
        var last: T? = null
        var next = 0L
        var failures = 0
    }
    private val slots = ConcurrentHashMap<String, Slot<T>>()
    fun clear() = slots.clear()
    fun due(key: String): Boolean = slots[key]?.let { slot -> synchronized(slot) {
        slot.inFlight == null && clock() >= slot.next
    } } ?: true
    fun delay(key: String): Long = slots[key]?.let { slot -> synchronized(slot) {
        if (slot.inFlight != null) 1000L else (slot.next - clock()).coerceAtLeast(1)
    } } ?: 1L

    fun read(key: String, manual: Boolean, load: () -> T): T {
        val slot = slots.getOrPut(key) { Slot() }
        var owner = false
        val future = synchronized(slot) {
            slot.inFlight ?: run {
                val cached = slot.last
                if (!manual && clock() < slot.next && cached != null) return cached
                owner = true
                CompletableFuture<T>().also { slot.inFlight = it }
            }
        }
        if (!owner) return future.get(90, TimeUnit.SECONDS)
        val started = clock()
        try {
            val result = load()
            synchronized(slot) {
                if (cacheable(result)) {
                    slot.failures = if (successful(result)) 0 else slot.failures + 1
                    val interval = if (slot.failures == 0) 30_000L else
                        longArrayOf(30_000, 60_000, 120_000, 300_000)[(slot.failures - 1).coerceIn(0, 3)]
                    slot.next = if (slot.failures == 0) (started + interval).coerceAtLeast(clock() + 1000) else clock() + interval
                    slot.last = result
                }
                future.complete(result)
            }
            return result
        } catch (error: Throwable) {
            future.completeExceptionally(error)
            throw error
        } finally {
            synchronized(slot) { slot.inFlight = null }
        }
    }
}
