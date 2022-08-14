import Foundation

struct Power {
    static var hasInternalBattery: Bool {
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let psList = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as [CFTypeRef]

        for ps in psList {
            if let psDesc = IOPSGetPowerSourceDescription(psInfo, ps).takeUnretainedValue() as? [String: Any] {
                if let type = psDesc[kIOPSTypeKey] as? String {
                    if type == "InternalBattery" {
                        return true
                    }
                }
            }
        }

        return false
    }

    static var isConnectedToPower: Bool {
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let psList = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as [CFTypeRef]

        for ps in psList {
            if let psDesc = IOPSGetPowerSourceDescription(psInfo, ps).takeUnretainedValue() as? [String: Any] {
                if let type = psDesc[kIOPSTypeKey] as? String,
                   type == "InternalBattery",
                   let powerSourceState = (psDesc[kIOPSPowerSourceStateKey] as? String)
                {
                    return powerSourceState == kIOPSACPowerValue
                }
            }
        }

        return false
    }
}
