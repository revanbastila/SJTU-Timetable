package cn.sjtu.jiaotong_course

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

fun main() {
    val clock = AtomicLong(100_000)
    val poll = AttendancePolling<String>({ clock.get() }, { it == "ok" }, { it != "cancelled" })
    var requests = 0
    check(poll.read("account:91", false) { requests++; "ok" } == "ok")
    clock.addAndGet(29_000)
    poll.read("account:91", false) { requests++; "ok" }
    check(requests == 1 && poll.delay("account:91") == 1000L)
    clock.addAndGet(1000)
    poll.read("account:91", false) { requests++; "ok" }
    check(requests == 2)
    poll.read("account:91", true) { requests++; "ok" }
    check(requests == 3) // Explicit manual retry never returns an old completed slot.
    println("PASS shared cadence and fresh manual retry")

    poll.read("account:broken", false) { "network" }
    clock.addAndGet(30_000)
    poll.read("account:broken", false) { "network" }
    check(poll.delay("account:broken") == 60_000L)
    check(poll.due("account:91"))
    clock.addAndGet(60_000)
    poll.read("account:broken", false) { "ok" }
    check(poll.delay("account:broken") == 30_000L)
    println("PASS course failure isolation and successful recovery")

    poll.read("account:slow", false) { clock.addAndGet(45_000); "ok" }
    check(poll.delay("account:slow") == 1000L)
    poll.read("account:cancel", false) { "cancelled" }
    check(poll.due("account:cancel"))
    check(poll.due("other-account:91"))
    println("PASS slow request has no catch-up burst; cancellation and account isolation")

    val executor = Executors.newFixedThreadPool(3)
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    val loading = AtomicInteger()
    try {
        val first = executor.submit<String> {
            poll.read("account:parallel", false) {
                loading.incrementAndGet(); entered.countDown()
                check(release.await(5, TimeUnit.SECONDS)); "ok"
            }
        }
        check(entered.await(5, TimeUnit.SECONDS))
        val other = executor.submit<String> { poll.read("account:other", false) { "ok" } }
        check(other.get(2, TimeUnit.SECONDS) == "ok")
        val second = executor.submit<String> { poll.read("account:parallel", false) { loading.incrementAndGet(); "duplicate" } }
        check(!poll.due("account:parallel"))
        release.countDown()
        check(first.get(5, TimeUnit.SECONDS) == "ok")
        check(second.get(5, TimeUnit.SECONDS) == "ok")
        check(loading.get() == 1)
        println("PASS concurrent foreground/background coalescing and independent courses")
    } finally { release.countDown(); executor.shutdownNow() }
    poll.clear(); check(poll.due("account:91"))
    println("PASS reset; all native polling smoke checks passed")
}
