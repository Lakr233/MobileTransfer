import Foundation

struct DeviceBatteryStatus {
    let percentage: Int?
    let isCharging: Bool?

    init(values: [String: String]) {
        percentage = values["BatteryCurrentCapacity"].flatMap(Int.init).flatMap { (0...100).contains($0) ? $0 : nil }
        switch values["BatteryIsCharging"]?.lowercased() {
        case "true", "1": isCharging = true
        case "false", "0": isCharging = false
        default: isCharging = nil
        }
    }

    var symbol: String {
        if isCharging == true { return "battery.100percent.bolt" }
        switch percentage ?? 0 {
        case 88...100: return "battery.100percent"
        case 63...87: return "battery.75percent"
        case 38...62: return "battery.50percent"
        case 13...37: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    #if DEBUG
    static func verify() -> Bool {
        let charging = Self(values: ["BatteryCurrentCapacity": "88", "BatteryIsCharging": "true"])
        let unplugged = Self(values: ["BatteryCurrentCapacity": "18", "BatteryIsCharging": "0"])
        let unknown = Self(values: ["BatteryCurrentCapacity": "101"])
        return charging.symbol == "battery.100percent.bolt" && charging.percentage == 88
            && unplugged.symbol == "battery.25percent" && unplugged.isCharging == false
            && unknown.percentage == nil && unknown.isCharging == nil
    }
    #endif
}
