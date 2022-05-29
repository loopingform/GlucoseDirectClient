//
//  SettingsView.swift
//  GlucoseDirectClientUI
//
//  Created by Ivan Valkou on 18.10.2019.
//  Copyright © 2019 Ivan Valkou. All rights reserved.
//

import Combine
import SwiftUI

// MARK: - SettingsViewModel

class SettingsViewModel: ObservableObject {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    var onDelete: (() -> Void)?
    var onClose: (() -> Void)?
}

// MARK: - SettingsView

public struct SettingsView: View {
    // MARK: Public

    public var body: some View {
        VStack {
            HStack {
                Spacer()
                deleteCGMButton
                Spacer()
            }
        }
        .navigationBarTitle(Text("CGM Settings"))
        .navigationBarItems(
            trailing: Button(action: {
                self.viewModel.onClose?()
            }, label: {
                Text("Done", bundle: FrameworkBundle.main)
            })
        )
    }

    // MARK: Internal

    @ObservedObject var viewModel: SettingsViewModel

    // MARK: Private

    @State private var showingDeletionSheet = false

    private var deleteCGMButton: some View {
        Button(action: {
            showingDeletionSheet = true
        }, label: {
            Text("Delete CGM").foregroundColor(.red)
        }).actionSheet(isPresented: $showingDeletionSheet) {
            ActionSheet(
                title: Text("Are you sure you want to delete this CGM?"),
                buttons: [
                    .destructive(Text("Delete CGM")) {
                        self.viewModel.onDelete?()
                    },
                    .cancel(),
                ]
            )
        }
    }
}
