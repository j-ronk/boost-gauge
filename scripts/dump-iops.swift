#!/usr/bin/env swift
// Usage: swift scripts/dump-iops.swift > Tests/Fixtures/Battery/iops-<state>.plist
// Writes the internal battery's IOPowerSources description as plist XML, the same dict BatteryItem reads in-process.
import Foundation
import IOKit.ps

guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
    FileHandle.standardError.write(Data("no power sources\n".utf8)); exit(1)
}
for ps in list {
    guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
          (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
    let data = try PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0)
    FileHandle.standardOutput.write(data)
    exit(0)
}
FileHandle.standardError.write(Data("no internal battery\n".utf8)); exit(1)
