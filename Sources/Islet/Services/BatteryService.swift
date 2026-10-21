import Foundation
import IOKit.ps

@Observable @MainActor
final class BatteryService {
    enum Event { case pluggedIn, unplugged, low }

    private(set) var level = 100
    private(set) var isCharging = false
    private(set) var isPluggedIn = false
    private(set) var hasBattery = false

    @ObservationIgnored var onEvent: ((Event) -> Void)?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var warnedLow = false

    func start() {
        refresh(notify: false)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.refresh(notify: true) }
        }
        if let src = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            source = src
        }
    }

    private func refresh(notify: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let newLevel = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            let plugged = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let wasPlugged = isPluggedIn

            hasBattery = true
            level = newLevel
            isPluggedIn = plugged
            isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false

            guard notify else { continue }
            if plugged != wasPlugged { onEvent?(plugged ? .pluggedIn : .unplugged) }
            if !plugged && newLevel <= 20 && !warnedLow {
                warnedLow = true
                onEvent?(.low)
            }
            if plugged || newLevel > 25 { warnedLow = false }
        }
    }
}
