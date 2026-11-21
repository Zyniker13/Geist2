import SwiftUI

/// In-app licenses screen: shows the open-source licenses for all
/// external dependencies and attribution for installed modules.
struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // External dependencies
                Section("Dependencies") {
                    licenseRow(
                        name: "GRDB.swift",
                        version: "7.x",
                        license: "MIT License",
                        url: "https://github.com/groue/GRDB.swift"
                    )
                    licenseRow(
                        name: "swift-crypto",
                        version: "3.x",
                        license: "Apache License 2.0",
                        url: "https://github.com/apple/swift-crypto"
                    )
                }

                // Module attribution
                Section("Installed Modules") {
                    Text("Module attribution is shown on the Modules screen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("licensesTitle")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private func licenseRow(
        name: String,
        version: String,
        license: String,
        url: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.body)
                    .bold()
                Spacer()
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(license)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let link = URL(string: url) {
                Link(url, destination: link)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
