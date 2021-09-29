import Foundation
import SwiftUI

struct DefaultAccountHint: View {
    @EnvironmentObject<InstancesModel> private var instancesModel

    var body: some View {
        Group {
            if !instancesModel.defaultAccount.isNil {
                VStack {
                    HStack(spacing: 2) {
                        hintText
                            .truncationMode(.middle)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("You have no default account set")
            }
        }
        #if os(tvOS)
            .foregroundColor(.gray)
        #elseif os(macOS)
            .font(.caption2)
            .foregroundColor(.secondary)
        #endif
    }

    var hintText: some View {
        Group {
            if let account = instancesModel.defaultAccount {
                Text(
                    "**\(account.description)** account on instance **\(account.instance.shortDescription)** is your default."
                )
            }
        }
    }
}
