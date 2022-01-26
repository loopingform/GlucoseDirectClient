//
//  BloodGlucose.swift
//  GlucoseDirectClient
//
//  Created by Ivan Valkou on 10.10.2019.
//  Copyright © 2019 Ivan Valkou. All rights reserved.
//
import HealthKit
import LoopKit

// MARK: - BloodGlucose

public struct BloodGlucose: Codable {
    public var sgv: Int?
    public let trend: Int
    public let date: Date
    public let filtered: Double?
    public let noise: Int?

    public var glucose: Int { sgv ?? 0 }
}

// MARK: GlucoseValue

extension BloodGlucose: GlucoseValue {
    public var startDate: Date { date }
    public var quantity: HKQuantity { .init(unit: .milligramsPerDeciliter, doubleValue: Double(glucose)) }
}

// MARK: GlucoseDisplayable

extension BloodGlucose: GlucoseDisplayable {
    public var isStateValid: Bool { glucose >= 40 && glucose <= 500 }
    public var trendType: GlucoseTrend? { GlucoseTrend(rawValue: trend) }
    public var isLocal: Bool { false }

    // TODO: Placeholder. This functionality will come with LOOP-1311
    public var glucoseRangeCategory: GlucoseRangeCategory? {
        return nil
    }

    public var trendRate: HKQuantity? {
        return nil
    }
}

extension HKUnit {
    static let milligramsPerDeciliter: HKUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
}
