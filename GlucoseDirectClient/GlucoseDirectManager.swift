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
        client = GlucoseDirectClient()
        updateTimer = DispatchTimer(timeInterval: 10, queue: processQueue)

        scheduleUpdateTimer()
    }

    public required convenience init?(rawState: CGMManager.RawStateValue) {
        self.init()

        shouldSyncToRemoteService = rawState[Config.shouldSyncKey] as? Bool ?? false
    }

    // MARK: Public

    public enum CGMError: String, Error {
        case tooFlatData = "BG data is too flat."
    }

    public static let managerIdentifier = "GlucoseDirectClient"
    public static let localizedTitle = LocalizedString("Glucose Direct Client", comment: "Title for the CGMManager option")

    public let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()
    public let providesBLEHeartbeat = false

    public var managedDataInterval: TimeInterval?
    public var shouldSyncToRemoteService = false
    public var device: HKDevice?

    public var managerIdentifier: String {
        return GlucoseDirectManager.managerIdentifier
    }

    public var localizedTitle: String {
        return GlucoseDirectManager.localizedTitle
    }

    public var glucoseDisplay: GlucoseDisplayable? { latestBackfill }

    public var cgmManagerStatus: CGMManagerStatus {
        // TODO: Probably need a better way to calculate this.
        if let latestGlucose = latestBackfill, latestGlucose.startDate.timeIntervalSinceNow > -TimeInterval(minutes: 4.5) {
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
        "## GlucoseDirectManager\nlatestBackfill: \(String(describing: latestBackfill))\n"
    }

    public var appURL: URL? {
        return URL(string: "diabox://")
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
            if let latestGlucose = self.latestBackfill, latestGlucose.startDate.timeIntervalSinceNow > -TimeInterval(minutes: 0.5) {
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

                    if let latestGlucose = self.latestBackfill {
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

                    self.latestBackfill = newGlucose.first
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

    private var latestBackfill: BloodGlucose?

    private var client: GlucoseDirectClient?

    private let keychain = KeychainManager()
    private var requestReceiver: Cancellable?
    private let processQueue = DispatchQueue(label: "GlucoseDirectManager.processQueue")
    private var isFetching = false
    private let updateTimer: DispatchTimer

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

// MARK: - AlertResponder implementation

public extension GlucoseDirectManager {
    func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
}

// MARK: - AlertSoundVendor implementation

public extension GlucoseDirectManager {
    func getSoundBaseURL() -> URL? { return nil }
    func getSounds() -> [Alert.Sound] { return [] }
}
