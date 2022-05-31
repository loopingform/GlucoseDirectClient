//
//  GlucoseDirectManager.swift
//  GlucoseDirectClient
//
//  Created by Ivan Valkou on 10.10.2019.
//  Copyright © 2019 Ivan Valkou. All rights reserved.
//

import Combine
import HealthKit
import LoopKit

// MARK: - GlucoseDirectManager

public class GlucoseDirectManager: CGMManager {
    // MARK: Lifecycle

    public init() {
        sharedDefaults = UserDefaults(suiteName: Bundle.main.appGroupSuiteName)
        client = GlucoseDirectClient(sharedDefaults)
        updateTimer = DispatchTimer(timeInterval: 10, queue: processQueue)
        scheduleUpdateTimer()
    }

    public required convenience init?(rawState: CGMManager.RawStateValue) {
        self.init()

        shouldSyncToRemoteService = rawState[Config.shouldSyncKey] as? Bool ?? false
    }

    // MARK: Public

    public static let managerIdentifier = "GlucoseDirectClient"
    public static let localizedTitle = LocalizedString("Glucose Direct Client")

    public let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()
    public let providesBLEHeartbeat = false

    public var managedDataInterval: TimeInterval?
    public var shouldSyncToRemoteService = false
    public private(set) var latestGlucose: ClientGlucose?
    public private(set) var latestGlucoseSample: NewGlucoseSample?

    public var sensor: String? {
        sharedDefaults?.string(forKey: "glucosedirect--sensor")
    }

    public var sensorState: String? {
        sharedDefaults?.string(forKey: "glucosedirect--sensor-state")
    }

    public var sensorConnectionState: String? {
        sharedDefaults?.string(forKey: "glucosedirect--sensor-connection-state")
    }

    public var app: String? {
        sharedDefaults?.string(forKey: "glucosedirect--app")
    }
    
    public var appVersion: String? {
        sharedDefaults?.string(forKey: "glucosedirect--app-version")
    }

    public var transmitter: String? {
        sharedDefaults?.string(forKey: "glucosedirect--transmitter")
    }

    public var transmitterBattery: String? {
        sharedDefaults?.string(forKey: "glucosedirect--transmitter-battery")
    }

    public var transmitterHardware: String? {
        sharedDefaults?.string(forKey: "glucosedirect--transmitter-hardware")
    }

    public var transmitterFirmware: String? {
        sharedDefaults?.string(forKey: "glucosedirect--transmitter-firmware")
    }

    public var device: HKDevice? {
        HKDevice(
            name: managerIdentifier,
            manufacturer: nil,
            model: sensor,
            hardwareVersion: transmitterHardware,
            firmwareVersion: transmitterFirmware,
            softwareVersion: appVersion,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
    }

    public var managerIdentifier: String {
        return GlucoseDirectManager.managerIdentifier
    }

    public var localizedTitle: String {
        return GlucoseDirectManager.localizedTitle
    }

    public var glucoseDisplay: GlucoseDisplayable? { latestGlucose }

    public var cgmManagerStatus: CGMManagerStatus {
        // TODO: Probably need a better way to calculate this.
        if let latestGlucose = latestGlucose, latestGlucose.startDate.timeIntervalSinceNow > -TimeInterval(minutes: 4.5) {
            return .init(hasValidSensorSession: true, device: device)
        } else {
            return .init(hasValidSensorSession: false, device: device)
        }
    }

    public var isOnboarded: Bool {
        true
    }

    public var rawState: CGMManager.RawStateValue {
        [Config.shouldSyncKey: shouldSyncToRemoteService]
    }

    public var delegateQueue: DispatchQueue! {
        get { delegate.queue }
        set { delegate.queue = newValue }
    }

    public var cgmManagerDelegate: CGMManagerDelegate? {
        get { delegate.delegate }
        set { delegate.delegate = newValue }
    }

    public var debugDescription: String {
        "## GlucoseDirectManager\nlatestBackfill: \(String(describing: latestGlucose))\n"
    }

    public var appURL: URL? {
        return URL(string: "glucosedirect://")
    }

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        processQueue.async {
            guard let manager = self.client, !self.isFetching else {
                self.delegateQueue.async {
                    completion(.noData)
                }

                return
            }

            // If our last glucose was less than 0.5 minutes ago, don't fetch.
            if let latestGlucose = self.latestGlucose, latestGlucose.startDate.timeIntervalSinceNow > -TimeInterval(minutes: 0.5) {
                self.delegateQueue.async {
                    completion(.noData)
                }

                return
            }

            self.isFetching = true
            self.requestReceiver = manager.fetchLast(60)
                .sink(receiveCompletion: { finish in
                    switch finish {
                    case .finished: break
                    case let .failure(error):
                        self.delegateQueue.async {
                            completion(.error(error))
                        }
                    }
                    self.isFetching = false
                }, receiveValue: { [weak self] glucose in
                    guard let self = self else {
                        return
                    }
                    guard !glucose.isEmpty else {
                        self.delegateQueue.async {
                            completion(.noData)
                        }
                        return
                    }

                    var startDate: Date?

                    if let latestGlucose = self.latestGlucose {
                        startDate = latestGlucose.startDate
                    } else {
                        startDate = self.delegate.call { delegate -> Date? in
                            delegate?.startDateToFilterNewData(for: self)
                        }
                    }

                    let newGlucose = glucose.filterDateRange(startDate, nil)
                    let newGlucoseSamples = newGlucose.filter { $0.isStateValid }.map {
                        NewGlucoseSample(date: $0.startDate, quantity: $0.quantity, condition: nil, trend: $0.trendType, trendRate: $0.trendRate, isDisplayOnly: false, wasUserEntered: false, syncIdentifier: "\(Int($0.startDate.timeIntervalSince1970))", device: self.device)
                    }

                    self.latestGlucose = newGlucose.first
                    self.latestGlucoseSample = newGlucoseSamples.first

                    self.delegateQueue.async {
                        guard !newGlucoseSamples.isEmpty else {
                            completion(.noData)
                            return
                        }

                        completion(.newData(newGlucoseSamples))
                    }
                })
        }
    }

    // MARK: Private

    private enum Config {
        static let shouldSyncKey = "GlucoseDirectClient.shouldSync"
    }

    private var client: GlucoseDirectClient?
    private var requestReceiver: Cancellable?
    private let processQueue = DispatchQueue(label: "GlucoseDirectManager.processQueue")
    private var isFetching = false
    private let updateTimer: DispatchTimer
    private let sharedDefaults: UserDefaults?

    private func scheduleUpdateTimer() {
        updateTimer.suspend()
        updateTimer.eventHandler = { [weak self] in
            guard let self = self else {
                return
            }

            self.fetchNewDataIfNeeded { result in
                guard case .newData = result else {
                    return
                }

                self.delegate.notify { delegate in
                    delegate?.cgmManager(self, hasNew: result)
                }
            }
        }
        updateTimer.resume()
    }
}

public extension GlucoseDirectManager {
    func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
}

public extension GlucoseDirectManager {
    func getSoundBaseURL() -> URL? { return nil }
    func getSounds() -> [Alert.Sound] { return [] }
}

private extension Bundle {
    var appGroupSuiteName: String {
        return object(forInfoDictionaryKey: "AppGroupIdentifier") as! String
    }
}
