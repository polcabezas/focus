import Foundation
import Darwin

public enum TrustedClock {
    public static func now(wall: Date = Date(), anchor: inout ClockAnchor?) -> Date {
        let mono = clock_gettime_nsec_np(CLOCK_MONOTONIC)
        let trusted: Date
        if let a = anchor, mono >= a.monotonicNanos {
            let elapsed = Double(mono - a.monotonicNanos) / 1_000_000_000
            trusted = a.trusted.addingTimeInterval(elapsed)
        } else {
            trusted = max(wall, anchor?.trusted ?? wall)
        }
        anchor = ClockAnchor(trusted: trusted, monotonicNanos: mono)
        return trusted
    }
}
