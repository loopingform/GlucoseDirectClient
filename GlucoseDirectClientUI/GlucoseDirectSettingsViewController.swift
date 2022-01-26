//
//  GlucoseDirectSettingsViewController.swift
//  GlucoseDirectClientUI
//
//  Created by Ivan Valkou on 21.10.2019.
//  Copyright © 2019 Ivan Valkou. All rights reserved.
//

import Combine
import GlucoseDirectClient
import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI

public final class GlucoseDirectSettingsViewController: UIHostingController<SettingsView>, CompletionNotifying {
    // MARK: Lifecycle

    public init(cgmManager: GlucoseDirectManager, glucoseUnit: DisplayGlucoseUnitObservable) {
        self.cgmManager = cgmManager
        self.glucoseUnit = glucoseUnit

        
        super.init(rootView: SettingsView(viewModel: viewModel))

        viewModel.onClose = {
            self.completionDelegate?.completionNotifyingDidComplete(self)
            self.dismiss(animated: true)
        }

        viewModel.onDelete = {
            self.cgmManager.notifyDelegateOfDeletion {
                DispatchQueue.main.async {
                    self.completionDelegate?.completionNotifyingDidComplete(self)
                    self.dismiss(animated: true)
                }
            }
        }
    }

    @available(*, unavailable)
    @objc dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Public

    public var completionDelegate: CompletionDelegate?
    public let cgmManager: GlucoseDirectManager
    public let glucoseUnit: DisplayGlucoseUnitObservable

    // MARK: Private

    private var viewModel = SettingsViewModel()
}
