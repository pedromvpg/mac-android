import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var adb: AdbService

    var body: some View {
        TabView {
            FileExplorerView()
                .tabItem {
                    Label("Explorer", systemImage: "folder")
                }

            TransferView()
                .tabItem {
                    Label("Transfer", systemImage: "arrow.up.arrow.down")
                }

            StorageView()
                .tabItem {
                    Label("Storage", systemImage: "internaldrive")
                }
        }
        .frame(minWidth: 780, minHeight: 560)
    }
}

struct TransferView: View {
    @EnvironmentObject private var adb: AdbService
    @State private var remotePath = AdbService.defaultRemote
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            dropZone
            Divider()
            transferLog
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Quick transfer", systemImage: "arrow.up.doc")
                    .font(.title2.weight(.semibold))
                Spacer()
                deviceBadge
            }

            HStack(spacing: 8) {
                Text("Destination on phone")
                    .foregroundStyle(.secondary)
                TextField("Remote path", text: $remotePath)
                    .textFieldStyle(.roundedBorder)
            }

            if let version = adb.adbVersion {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
    }

    private var deviceBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(adb.devices.isEmpty ? Color.red : Color.green)
                .frame(width: 8, height: 8)
            if let device = adb.devices.first {
                Text(device.model ?? device.id)
                    .font(.subheadline.weight(.medium))
            } else {
                Text("No device")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 2, dash: [10, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )

            VStack(spacing: 12) {
                if adb.isTransferring {
                    ProgressView()
                        .controlSize(.large)
                    Text("Transferring…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                        .symbolEffect(.bounce, value: isDropTargeted)

                    Text("Drop files or folders here")
                        .font(.headline)

                    Text("Copied to \(remotePath) on your Android device")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
        }
        .padding(20)
        .frame(maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .disabled(adb.isTransferring)
    }

    private var transferLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent transfers")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            if adb.transferLog.isEmpty {
                Text("No transfers yet")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(adb.transferLog) { entry in
                            TransferRow(entry: entry)
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
        }
        .frame(height: 180)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !adb.isTransferring else { return false }

        var collected: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collected.append(url)
                } else if let url = item as? URL {
                    collected.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            let urls = collected.filter(\.isFileURL)
            guard !urls.isEmpty else { return }
            Task {
                await adb.push(urls: urls, to: remotePath)
            }
        }

        return true
    }
}

struct TransferRow: View {
    let entry: AdbService.TransferEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.success ? .green : .red)
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(entry.remotePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(entry.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

#Preview {
    ContentView()
        .environmentObject(AdbService())
}
