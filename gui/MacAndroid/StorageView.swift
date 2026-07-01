import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var adb: AdbService
    @State private var primaryVolumes: [StorageVolume] = []
    @State private var allVolumes: [StorageVolume] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAllPartitions = false
    @State private var lastUpdated: Date?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading && primaryVolumes.isEmpty {
                ProgressView("Reading storage…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, primaryVolumes.isEmpty {
                ContentUnavailableView(
                    "Cannot read storage",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(errorMessage)
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let errorMessage {
                            errorBanner(errorMessage)
                        }

                        ForEach(primaryVolumes) { volume in
                            StorageCard(volume: volume, prominent: true)
                        }

                        Toggle("Show all partitions", isOn: $showAllPartitions)
                            .toggleStyle(.switch)
                            .padding(.horizontal, 20)

                        if showAllPartitions {
                            allPartitionsTable
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await refresh() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label("Storage", systemImage: "internaldrive")
                    .font(.title2.weight(.semibold))
                if let lastUpdated {
                    Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let device = adb.devices.first {
                Text(device.model ?? device.id)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading || adb.devices.isEmpty)
            .help("Refresh")
        }
        .padding(20)
    }

    private var allPartitionsTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All partitions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            Table(allVolumes) {
                TableColumn("Mount") { volume in
                    Text(volume.label)
                        .lineLimit(1)
                }
                .width(min: 140, ideal: 180)

                TableColumn("Used") { volume in
                    Text("\(volume.used) / \(volume.size)")
                        .foregroundStyle(.secondary)
                }
                .width(ideal: 120)

                TableColumn("Available") { volume in
                    Text(volume.available)
                        .foregroundStyle(.secondary)
                }
                .width(ideal: 80)

                TableColumn("Use") { volume in
                    HStack(spacing: 8) {
                        ProgressView(value: Double(volume.usePercent), total: 100)
                            .progressViewStyle(.linear)
                            .frame(width: 60)
                        Text("\(volume.usePercent)%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .width(ideal: 120)
            }
            .frame(minHeight: 200, maxHeight: 320)
            .padding(.horizontal, 12)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let volumes = try await adb.fetchStorage()
            allVolumes = volumes.filter { !shouldHide($0) }
            primaryVolumes = StorageParser.primaryVolumes(from: volumes)
            lastUpdated = .now
            if primaryVolumes.isEmpty {
                errorMessage = "No storage volumes found."
            }
        } catch {
            primaryVolumes = []
            allVolumes = []
            errorMessage = error.localizedDescription
        }
    }

    private func shouldHide(_ volume: StorageVolume) -> Bool {
        let mount = volume.mountPoint
        if mount.hasPrefix("/apex") || mount.hasPrefix("/bootstrap-apex") { return true }
        if mount == "/dev" || mount == "/mnt" || mount == "/tmp" { return true }
        if volume.filesystem.hasPrefix("/dev/block/loop") { return true }
        if mount.hasPrefix("/system_ext") || mount.hasPrefix("/product") || mount.hasPrefix("/vendor") {
            return volume.usePercent >= 99
        }
        return false
    }
}

struct StorageCard: View {
    let volume: StorageVolume
    var prominent: Bool = false

    private var barColor: Color {
        switch volume.usePercent {
        case 90...: return .red
        case 75..<90: return .orange
        default: return .accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(volume.label, systemImage: "internaldrive.fill")
                    .font(prominent ? .title3.weight(.semibold) : .headline)
                Spacer()
                Text("\(volume.usePercent)% used")
                    .font(.subheadline)
                    .foregroundStyle(volume.usePercent >= 90 ? .red : .secondary)
            }

            ProgressView(value: Double(volume.usePercent), total: 100)
                .tint(barColor)

            HStack {
                stat(label: "Used", value: volume.used)
                Spacer()
                stat(label: "Available", value: volume.available)
                Spacer()
                stat(label: "Total", value: volume.size)
            }

            Text(volume.mountPoint)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium).monospacedDigit())
        }
    }
}

#Preview {
    StorageView()
        .environmentObject(AdbService())
        .frame(width: 600, height: 500)
}
