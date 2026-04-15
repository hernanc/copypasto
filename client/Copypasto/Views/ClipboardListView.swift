import SwiftUI

struct ClipboardListView: View {
    @EnvironmentObject var authService: AuthService
    @State private var hoveredEntryId: String?
    @State private var copiedEntryId: String?

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().padding(.horizontal, 8)
            contentSection
            Divider().padding(.horizontal, 8)
            footerSection
        }
        .frame(width: 320)
    }

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Clipboard History")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(authService.clipboardEntries.count) items")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            connectionBadge
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var connectionBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectionColor)
                .frame(width: 6, height: 6)
            Text(authService.connectionState.statusLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(connectionColor.opacity(0.1))
        )
    }

    private var connectionColor: Color {
        switch authService.connectionState {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .disconnected, .waitingForNetwork:
            return .red
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if authService.clipboardEntries.isEmpty {
            emptyState
        } else {
            entryList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.quaternary)
            Text("No clipboard entries yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Copy something to get started")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var entryList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(authService.clipboardEntries) { entry in
                    entryRow(for: entry)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 260)
    }

    private func entryRow(for entry: ClipboardEntry) -> some View {
        ClipboardEntryRow(
            entry: entry,
            isHovered: hoveredEntryId == entry.id,
            isCopied: copiedEntryId == entry.id,
            onCopy: { copyEntry(entry) }
        )
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredEntryId = isHovered ? entry.id : nil
            }
        }
    }

    private func copyEntry(_ entry: ClipboardEntry) {
        authService.copyEntry(entry)
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedEntryId = entry.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if copiedEntryId == entry.id {
                    copiedEntryId = nil
                }
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Button {
                authService.logout()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Clipboard Entry Row

private struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let isHovered: Bool
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.preview ?? "Encrypted entry")
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foregroundStyle(isHovered ? .primary : .primary)

                    Text(formatDate(entry.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)

                Group {
                    if isCopied {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(isHovered ? .secondary : .quaternary)
                    }
                }
                .font(.system(size: 12))
                .frame(width: 16)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
