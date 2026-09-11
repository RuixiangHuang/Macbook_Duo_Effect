import Foundation
import IOKit.hid

/// All device operations run on the caller's serial queue.
final class LidSensor {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private(set) var status = LocalizedText(en: "Lid angle sensor not connected yet", zh: "尚未连接角度传感器")
    private var retryAfter = Date.distantPast

    func connect() {
        disconnect()
        retryAfter = Date().addingTimeInterval(2)
        let handle = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = handle
        let match: [String: Any] = [kIOHIDVendorIDKey: 0x05ac,
                                   kIOHIDPrimaryUsagePageKey: 0x20,
                                   kIOHIDPrimaryUsageKey: 0x8a]
        IOHIDManagerSetDeviceMatching(handle, match as CFDictionary)
        let opened = IOHIDManagerOpen(handle, IOOptionBits(kIOHIDOptionsTypeNone))
        guard opened == kIOReturnSuccess else {
            status = LocalizedText(en: "Sensor connection failed (\(opened))", zh: "传感器连接失败（\(opened)）"); return
        }
        guard let devices = IOHIDManagerCopyDevices(handle) as? Set<IOHIDDevice> else {
            status = LocalizedText(en: "No lid angle sensor found", zh: "未找到开合角度传感器"); return
        }
        for candidate in devices {
            if IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
                device = candidate
                status = LocalizedText(en: "Sensor connected", zh: "传感器已连接")
                return
            }
        }
        status = LocalizedText(en: "Could not open the lid angle sensor", zh: "无法打开角度传感器")
    }

    func read() -> Double? {
        if device == nil, Date() >= retryAfter { connect() }
        guard let device else { return nil }
        var bytes = [UInt8](repeating: 0, count: 8)
        bytes[0] = 1
        var length = bytes.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &length)
        guard result == kIOReturnSuccess, length >= 3,
              let angle = LidReport.angle(Array(bytes.prefix(length))) else {
            status = LocalizedText(en: "Angle read failed; effect paused", zh: "角度读取失败，效果已暂停")
            disconnect()
            retryAfter = Date().addingTimeInterval(2)
            return nil
        }
        status = LocalizedText(en: "Sensor connected", zh: "传感器已连接")
        return angle
    }

    func disconnect() {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        manager = nil
    }
    deinit { disconnect() }
}
