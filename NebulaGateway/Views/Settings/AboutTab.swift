// AboutTab.swift
// NebulaGateway

import SwiftUI

/// About tab in the Settings window.
struct AboutTab: View {

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image("AboutLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)

            Text(Constants.appName)
                .font(.title2)
                .fontWeight(.semibold)

            Text(String(localized: "settings.about.version \(appVersion)"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(String(localized: "settings.about.author"))
                .font(.subheadline)

            Link(
                "github.com/WS-Company/NebulaGatewayApp",
                destination: Constants.githubURL
            )
            .font(.subheadline)

            Divider()
                .frame(width: 200)

            Text(String(localized: "settings.about.builtWith"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Link(
                "github.com/slackhq/nebula",
                destination: Constants.nebulaGithubURL
            )
            .font(.caption)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
