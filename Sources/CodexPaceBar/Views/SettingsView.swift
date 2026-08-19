@preconcurrency import AppKit
import CodexActivityInsightsContract
import CodexActivityInsightsControlAdapter
import CodexPaceBarAppSupport
import CodexPaceBarCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var launchAtLogin: LaunchAtLoginController
    @Bindable var activityInsights: ActivityInsightsCollectorController

    @State private var selectedSection: SettingsSection = .activityInsights

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selectedSection)
                .frame(width: 188)

            Divider()

            selectedPage
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    Rectangle()
                        .fill(.regularMaterial)
                        .overlay(Color.black.opacity(0.04))
                }
        }
        .frame(minWidth: 717, minHeight: 534)
        .background(.regularMaterial)
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch selectedSection {
        case .general:
            generalPage
        case .activityInsights:
            activityInsightsPage
        case .appearance:
            appearancePage
        case .advanced:
            advancedPage
        case .about:
            aboutPage
        }
    }

    private var generalPage: some View {
        SettingsPage(
            title: "General",
            subtitle: "Choose how Codex Pace Bar behaves."
        ) {
            VStack(spacing: 0) {
                SettingsControlRow(
                    icon: "power",
                    title: "Launch at login",
                    subtitle: launchAtLogin.statusMessage ?? "Open Codex Pace Bar after signing in"
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.setEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsPageDivider()

                SettingsControlRow(
                    icon: "bell",
                    title: "Usage notifications",
                    subtitle: "Warn about high pace or forecast exhaustion; maximum once per day."
                ) {
                    Toggle("", isOn: $settings.notificationsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .padding(.top, 32)
        }
    }

    private var activityInsightsPage: some View {
        SettingsPage(
            title: "Activity Insights",
            subtitle: "Understand how you and Codex work together."
        ) {
            VStack(spacing: 0) {
                collectorRow

                SettingsPageDivider()

                VStack(spacing: 0) {
                    ActivityMetricRow(
                        icon: "person.fill",
                        title: "User active time",
                        subtitle: "Tracks when you are actively using your computer."
                    )
                    ActivityMetricRow(
                        icon: "terminal",
                        title: "Codex working time",
                        subtitle: "Measures time Codex is generating responses."
                    )
                    ActivityMetricRow(
                        icon: "person.2",
                        title: "Foreground collaboration",
                        subtitle: "Counts time Codex is your active, focused collaborator.",
                        isLast: true
                    )
                }
                .padding(.vertical, 12)

                SettingsPageDivider()

                SettingsControlRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "History-based forecast",
                    subtitle: "Learns from 30 days and adapts to the current window."
                ) {
                    Toggle("", isOn: $settings.historyBasedForecastEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsPageDivider()

                Button(action: revealCollectedData) {
                    Label("View collected data", systemImage: "arrow.up.right.square")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .padding(.leading, 2)
                .padding(.top, 22)
                .help(ActivityInsightsChartSnapshotLocation.defaultDirectoryURL().path)
            }
            .padding(.top, 32)
        }
    }

    private var collectorRow: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: "waveform")
                .font(.system(size: 26, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .frame(width: 30, height: 54, alignment: .top)

            VStack(alignment: .leading, spacing: 6) {
                Text("Activity Insights collector (Beta)")
                    .font(.system(size: 15, weight: .semibold))

                HStack(spacing: 7) {
                    Circle()
                        .fill(collectorStatusColor)
                        .frame(width: 9, height: 9)
                    Text(collectorStatusTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(collectorStatusColor)
                }

                Text("No prompt text or keystrokes are stored.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Toggle(
                "",
                isOn: Binding(
                    get: { activityInsights.isEnabled },
                    set: {
                        activityInsights.setEnabled(
                            $0,
                            configuredCodexPath: settings.codexExecutablePath
                        )
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(activityInsights.isBusy)
            .accessibilityLabel("Enable Activity Insights collector beta")
            .help(activityInsights.statusMessage)
            .padding(.top, 4)
        }
        .frame(minHeight: 74, alignment: .top)
    }

    private var collectorStatusTitle: String {
        if activityInsights.isBusy {
            return "Updating local collection…"
        }
        if activityInsights.isRunning {
            return "Collecting locally"
        }
        if activityInsights.isEnabled {
            return "Enabled; waiting to resume"
        }
        return "Collector is off"
    }

    private var collectorStatusColor: Color {
        if activityInsights.isBusy || (activityInsights.isEnabled && !activityInsights.isRunning) {
            return .orange
        }
        return activityInsights.isRunning ? .green : .secondary
    }

    private var appearancePage: some View {
        SettingsPage(
            title: "Appearance",
            subtitle: "Choose how the menu bar communicates your pace."
        ) {
            SettingsControlRow(
                icon: "paintpalette",
                title: "Color scheme",
                subtitle: "Set the meaning of the colors shown in the menu bar."
            ) {
                Picker("Color scheme", selection: $settings.barColorScheme) {
                    ForEach(BarColorScheme.allCases) { scheme in
                        Text(scheme.settingsTitle).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            .padding(.top, 32)
        }
    }

    private var advancedPage: some View {
        SettingsPage(
            title: "Advanced",
            subtitle: "Configure how Codex Pace Bar reads and refreshes usage data."
        ) {
            VStack(spacing: 0) {
                SettingsControlRow(
                    icon: "terminal",
                    title: "Codex executable path",
                    subtitle: "Command or full path used to start the local Codex app-server."
                ) {
                    TextField("Codex executable path", text: $settings.codexExecutablePath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                }

                SettingsPageDivider()

                SettingsControlRow(
                    icon: "arrow.clockwise",
                    title: "Refresh interval",
                    subtitle: "How often usage data is refreshed."
                ) {
                    Stepper(
                        "\(settings.refreshIntervalSeconds) sec",
                        value: $settings.refreshIntervalSeconds,
                        in: SettingsStore.minimumRefreshInterval...SettingsStore.maximumRefreshInterval,
                        step: 60
                    )
                    .frame(width: 136)
                }

                SettingsPageDivider()

                SettingsControlRow(
                    icon: "waveform.path",
                    title: "Pace delta",
                    subtitle: "Threshold used for pace comparison."
                ) {
                    Stepper(
                        "\(settings.deltaThresholdPercentagePoints) pp",
                        value: $settings.deltaThresholdPercentagePoints,
                        in: SettingsStore.minimumDeltaThreshold...SettingsStore.maximumDeltaThreshold
                    )
                    .frame(width: 118)
                }
            }
            .padding(.top, 32)
        }
    }

    private var aboutPage: some View {
        SettingsPage(
            title: "About",
            subtitle: "Codex Pace Bar is an unofficial, local-only macOS utility."
        ) {
            HStack(alignment: .center, spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Codex Pace Bar")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Version \(appVersion)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Link("GitHub repository", destination: repositoryURL)
                        .font(.system(size: 13))
                }
            }
            .padding(.top, 36)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development build"
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/awronski/codex-pace-bar")!
    }

    private func revealCollectedData() {
        let directoryURL = ActivityInsightsChartSnapshotLocation.defaultDirectoryURL()
        let chartURL = ActivityInsightsChartSnapshotLocation.defaultFileURL()
        if FileManager.default.fileExists(atPath: chartURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([chartURL])
        } else {
            NSWorkspace.shared.open(directoryURL)
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case activityInsights
    case appearance
    case advanced
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .activityInsights: "Activity Insights"
        case .appearance: "Appearance"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .activityInsights: "waveform"
        case .appearance: "paintpalette"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.leading, 84)
            .frame(height: 56)

            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon)
                                .font(.system(size: 20, weight: .regular))
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 24)

                            Text(section.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selection == section ? Color.white : Color.primary)
                        .padding(.horizontal, 8)
                        .frame(height: 43)
                        .background {
                            if selection == section {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
            }
            .padding(.horizontal, 9)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.10))
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            content
        }
        .padding(.horizontal, 42)
        .padding(.top, 60)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsControlRow<Control: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let control: Control

    init(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Control
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            control
                .controlSize(.regular)
        }
        .frame(minHeight: 76)
    }
}

private struct ActivityMetricRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var isLast = false

    var body: some View {
        HStack(alignment: .top, spacing: 17) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 21)

                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                }
            }
            .frame(width: 30)
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 51, alignment: .top)
    }
}

private struct SettingsPageDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 45)
    }
}
