//
//  values.swift
//  Sensors
//
//  Created by Serhiy Mytrovtsiy on 17/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//
//  Adapted for Vitals from Stats (https://github.com/exelban/stats, MIT License, see LICENSE in this folder).
//  Only the Apple Silicon CPU and GPU temperature keys are kept, merged across chip generations
//  (M1 to M6, A18 Pro). No key is CPU on one chip and GPU on another, so one merged table is safe.
//

enum StatsSensorKeys {
    static let cpu: Set<String> = [
        "Te05", "Te07", "Te08", "Te09", "Te0H", "Te0L", "Te0P", "Te0S", "Te0c", "Te0h", "Te0i", "Tf04", "Tf09",
        "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E", "Tp00", "Tp01", "Tp04",
        "Tp05", "Tp07", "Tp08", "Tp09", "Tp0C", "Tp0D", "Tp0E", "Tp0G", "Tp0H", "Tp0I", "Tp0K", "Tp0L", "Tp0O",
        "Tp0P", "Tp0R", "Tp0T", "Tp0U", "Tp0V", "Tp0X", "Tp0Y", "Tp0a", "Tp0b", "Tp0d", "Tp0e", "Tp0f", "Tp0g",
        "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y", "Tp1h", "Tp1l", "Tp1p", "Tp1t",
    ]

    static let gpu: Set<String> = [
        "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A", "Tg05", "Tg07", "Tg09", "Tg0D", "Tg0G",
        "Tg0H", "Tg0K", "Tg0L", "Tg0T", "Tg0U", "Tg0X", "Tg0a", "Tg0b", "Tg0c", "Tg0d", "Tg0e", "Tg0f", "Tg0g",
        "Tg0j", "Tg0k", "Tg1U", "Tg1Y", "Tg1c", "Tg1d", "Tg1e", "Tg1f", "Tg1g", "Tg1h", "Tg1k",
    ]
}
