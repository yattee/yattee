import Foundation
import IOKit.pwr_mgt

struct ScreenSaverManager {
    static var shared = Self()

    var noSleepAssertion: IOPMAssertionID = 0
    var noSleepReturn: IOReturn?

    var enabled: Bool {
        noSleepReturn == nil
    }

    @discardableResult mutating func disable(reason: String = "Unknown reason") -> Bool {
        guard enabled else {
            return false
        }

        noSleepReturn = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &noSleepAssertion
        )
        return noSleepReturn == kIOReturnSuccess
    }

    @discardableResult mutating func enable() -> Bool {
        if noSleepReturn != nil {
            _ = IOPMAssertionRelease(noSleepAssertion) == kIOReturnSuccess
            noSleepReturn = nil
            return true
        }
        return false
    }
}
