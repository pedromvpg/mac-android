import SwiftUI
import UniformTypeIdentifiers

struct FileExplorerView: View {
    @EnvironmentObject private var adb: AdbService
    @State private var currentPath = "/storage/emulated/0"
    @State private var entries: [RemoteFile] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pathField = "/storage/emulated/0"
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                fileList
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        .task(id: currentPath) {
            await loadDirectory()
        }
    }

    private var sidebar: some View {
        List(selection: Binding(
            get: { currentPath },
            set: { if let path = $0 { navigate(to: path) } }
        )) {
            Section("Places") {
                ForEach(RemoteBookmark.defaults) { bookmark in
                    Label(bookmark.name, systemImage: bookmark.systemImage)
                        .tag(bookmark.path)
                }
            }

            Section("Device") {
                if adb.devices.isEmpty {
                    Label("Not connected", systemImage: "cable.connector.slash")
                        .foregroundStyle(.secondary)
                } else if let device = adb.devices.first {
                    Label(device.model ?? device.id, systemImage: "smartphone")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Phone")
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: goUp) {
                Image(systemName: "chevron.up")
            }
            .disabled(!canGoUp)
            .help("Go up")

            Button {
                Task { await loadDirectory() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading || adb.devices.isEmpty)
            .help("Refresh")

            Divider().frame(height: 20)

            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                TextField("Path", text: $pathField, onCommit: {
                    navigate(to: pathField)
                })
                .textFieldStyle(.roundedBorder)
            }

            Spacer()

            if adb.isTransferring {
                ProgressView()
                    .controlSize(.small)
                Text("Transferring…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Pull to Mac") {
                Task { await pullSelected() }
            }
            .disabled(selectedFiles.isEmpty || adb.isTransferring)

            Button("Push…") {
                Task { await pushFromPicker() }
            }
            .disabled(adb.devices.isEmpty || adb.isTransferring)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var fileList: some View {
        if isLoading && entries.isEmpty {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            ContentUnavailableView(
                "Empty folder",
                systemImage: "folder",
                description: Text("This directory has no visible files.")
            )
        } else {
            Table(entries, selection: $selectedIDs) {
                TableColumn("Name") { file in
                    if file.isDirectory || file.isSymlink {
                        Button {
                            navigate(to: file.path)
                        } label: {
                            Label {
                                Text(file.name)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: file.iconName)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Label {
                            Text(file.name)
                        } icon: {
                            Image(systemName: file.iconName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .width(min: 180, ideal: 280)

                TableColumn("Size") { file in
                    Text(formattedSize(file.size))
                        .foregroundStyle(.secondary)
                }
                .width(ideal: 80)

                TableColumn("Modified") { file in
                    Text(file.modified ?? "—")
                        .foregroundStyle(.secondary)
                }
                .width(ideal: 130)

                TableColumn("Permissions") { file in
                    Text(file.permissions)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
                .width(ideal: 90)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                let files = files(for: ids)
                if !files.isEmpty {
                    if files.count == 1, let file = files.first, file.isDirectory || file.isSymlink {
                        Button("Open") { navigate(to: file.path) }
                    }
                    Button("Pull to Mac") {
                        selectedIDs = ids
                        Task { await pullSelected() }
                    }
                    if files.count == 1, let file = files.first {
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(file.path, forType: .string)
                        }
                    }
                }
            } primaryAction: { ids in
                if let file = files(for: ids).first, file.isDirectory || file.isSymlink {
                    navigate(to: file.path)
                }
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.06))
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
    }

    private var selectedFiles: [RemoteFile] {
        files(for: selectedIDs)
    }

    private func files(for ids: Set<String>) -> [RemoteFile] {
        entries.filter { ids.contains($0.id) }
    }

    private var canGoUp: Bool {
        currentPath != "/" && !currentPath.isEmpty
    }

    private func goUp() {
        let url = URL(fileURLWithPath: currentPath)
        let parent = url.deletingLastPathComponent().path
        navigate(to: parent.isEmpty ? "/" : parent)
    }

    private func navigate(to path: String) {
        var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { normalized = "/" }
        if !normalized.hasPrefix("/") { normalized = "/\(normalized)" }
        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }
        currentPath = normalized
        pathField = normalized
        selectedIDs = []
    }

    private func loadDirectory() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            entries = try await adb.listDirectory(at: currentPath)
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }

    private func pullSelected() async {
        let files = selectedFiles
        guard !files.isEmpty else { return }

        if files.count == 1, let file = files.first, !file.isDirectory {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.name
            panel.canCreateDirectories = true
            panel.prompt = "Save"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            await adb.pull(remote: file.path, to: url)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose destination folder"
        panel.message = files.count == 1
            ? "Choose where to save “\(files[0].name)” on your Mac."
            : "Choose a folder on your Mac for \(files.count) items from your phone."
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        await adb.pull(
            items: files.map { ($0.path, true) },
            to: destination
        )
    }

    private func pushFromPicker() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        await adb.push(urls: panel.urls, to: currentPath)
        await loadDirectory()
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
                await adb.push(urls: urls, to: currentPath)
                await loadDirectory()
            }
        }

        return true
    }

    private func formattedSize(_ size: Int64?) -> String {
        guard let size else { return "—" }
        if size < 1024 { return "\(size) B" }
        let kb = Double(size) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.1f GB", mb / 1024)
    }
}
