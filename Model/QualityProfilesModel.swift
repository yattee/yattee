import Defaults
import Foundation
#if os(iOS)
    import Reachability
    import UIKit
#endif

struct QualityProfilesModel {
    static let shared = Self()

    #if os(tvOS)
        var tvOSProfile: QualityProfile? {
            find(Defaults[.batteryNonCellularProfile])
        }
    #endif

    func find(_ id: QualityProfile.ID) -> QualityProfile? {
        guard id != "default" else { return QualityProfile.defaultProfile }

        return Defaults[.qualityProfiles].first { $0.id == id }
    }

    func add(_ qualityProfile: QualityProfile) {
        Defaults[.qualityProfiles].append(qualityProfile)
    }

    func update(_ from: QualityProfile, _ to: QualityProfile) {
        if let index = Defaults[.qualityProfiles].firstIndex(where: { $0.id == from.id }) {
            Defaults[.qualityProfiles][index] = to
        }
    }

    func remove(_ qualityProfile: QualityProfile) {
        if let index = Defaults[.qualityProfiles].firstIndex(where: { $0.id == qualityProfile.id }) {
            Defaults[.qualityProfiles].remove(at: index)
        }
    }

    func applyToAll(_ qualityProfile: QualityProfile) {
        Defaults[.batteryCellularProfile] = qualityProfile.id
        Defaults[.batteryNonCellularProfile] = qualityProfile.id
        Defaults[.chargingCellularProfile] = qualityProfile.id
        Defaults[.chargingNonCellularProfile] = qualityProfile.id
    }

    func reset() {
        Defaults.reset(.qualityProfiles)
        Defaults.reset(.batteryCellularProfile)
        Defaults.reset(.batteryNonCellularProfile)
        Defaults.reset(.chargingCellularProfile)
        Defaults.reset(.chargingNonCellularProfile)
    }

    #if os(iOS)
        private func findCurrentConnection() -> Reachability.Connection? {
            do {
                let reachability: Reachability = try Reachability()
                return reachability.connection
            } catch {
                return nil
            }
        }
    #endif

    var automaticProfile: QualityProfile? {
        var id: QualityProfile.ID?

        #if os(iOS)
            UIDevice.current.isBatteryMonitoringEnabled = true
            let unplugged = UIDevice.current.batteryState == .unplugged
            let connection = findCurrentConnection()

            if unplugged {
                switch connection {
                case .wifi:
                    id = Defaults[.batteryNonCellularProfile]
                default:
                    id = Defaults[.batteryCellularProfile]
                }
            } else {
                switch connection {
                case .wifi:
                    id = Defaults[.chargingNonCellularProfile]
                default:
                    id = Defaults[.chargingCellularProfile]
                }
            }
        #elseif os(macOS)
            if Power.hasInternalBattery {
                if Power.isConnectedToPower {
                    id = Defaults[.chargingNonCellularProfile]
                } else {
                    id = Defaults[.batteryNonCellularProfile]
                }
            } else {
                id = Defaults[.chargingNonCellularProfile]
            }
        #else
            id = Defaults[.chargingNonCellularProfile]
        #endif

        guard let id else { return nil }

        return find(id)
    }
}
