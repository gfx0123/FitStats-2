import SwiftUI
import UIKit

/// A screenshot picked to send to the coach: scaled down so text stays readable but the upload
/// and Claude's image tokens stay small (long edge 1,568 px, about 1,500 tokens), plus a small
/// preview the server keeps with the message.
struct CoachImageUpload: Identifiable {
    let id = UUID()
    let preview: UIImage
    /// Base64 JPEG for Claude.
    let data: String
    /// Base64 JPEG, long edge 320 px.
    let thumb: String

    static let maxEdge: CGFloat = 1568
    static let thumbEdge: CGFloat = 320

    init?(imageData: Data) {
        guard let image = UIImage(data: imageData),
              let full = image.fitted(maxEdge: Self.maxEdge).jpegData(compressionQuality: 0.8),
              let small = image.fitted(maxEdge: Self.thumbEdge).jpegData(compressionQuality: 0.6) else { return nil }
        preview = UIImage(data: small) ?? image
        data = full.base64EncodedString()
        thumb = small.base64EncodedString()
    }

    var attachment: CoachAttachment { CoachAttachment(mediaType: "image/jpeg", thumb: thumb) }
}

/// A workout CSV to send with a message: its text, read from Files. The server saves its
/// workouts to the Training log (lib/csvimport.ts).
struct CoachFileUpload: Identifiable {
    let id = UUID()
    let name: String
    let text: String

    /// What the server takes per file (about 5 MB of text).
    static let maxBytes = 5_000_000

    enum Problem: Error {
        case unreadable, tooLarge, notText
    }

    /// Reads a file picked in Files: UTF-8, UTF-16 or, failing those, Windows (Central
    /// European) or Latin-1 text.
    static func read(_ url: URL) -> Result<CoachFileUpload, Problem> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        guard data.count <= maxBytes else { return .failure(.tooLarge) }
        let encodings: [String.Encoding] = [.utf8, .utf16, .windowsCP1250, .isoLatin1]
        guard let text = encodings.lazy.compactMap({ String(data: data, encoding: $0) }).first,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !text.contains("\u{0}") else { return .failure(.notText) }
        return .success(CoachFileUpload(name: url.lastPathComponent, text: text))
    }

    var attachment: CoachAttachment { CoachAttachment(mediaType: "text/csv", thumb: nil, name: name) }
}

/// An attached file as a chip: its icon and name.
struct FileChip: View {
    let name: String
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tablecells")
                .font(Font.fs(.footnote, .semibold))
                .foregroundStyle(Theme.recoveryGreen)
            Text(name)
                .font(Font.fs(.footnote, .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(name)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 220)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

extension UIImage {
    /// At most `maxEdge` pixels on the long side, at scale 1 (screenshots and photos decode at
    /// scale 1, so their size is in pixels).
    func fitted(maxEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return self }
        let scale = maxEdge / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// The previews of a message's screenshots, in a row, and its files as chips.
struct AttachmentThumbs: View {
    let attachments: [CoachAttachment]
    var height: CGFloat = 120

    var body: some View {
        let files = attachments.filter(\.isFile)
        let images = attachments.filter { !$0.isFile }
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(Array(files.enumerated()), id: \.offset) { FileChip(name: $0.element.name ?? "File") }
            if !images.isEmpty { thumbs(images) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(files: files.count, images: images.count))
        .accessibilityIdentifier("coach-attachments")
    }

    private func label(files: Int, images: Int) -> String {
        var parts: [String] = []
        if files > 0 { parts.append(files == 1 ? "a file" : "\(files) files") }
        if images > 0 { parts.append(images == 1 ? "a screenshot" : "\(images) screenshots") }
        let text = parts.joined(separator: " and ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func thumbs(_ attachments: [CoachAttachment]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { item in
                if let thumb = item.element.thumb, let data = Data(base64Encoded: thumb), let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: height * min(1, image.size.width / max(image.size.height, 1)) , height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: height * 0.5, height: height)
                        .overlay(Image(systemName: "photo").foregroundStyle(Theme.tertiary))
                }
            }
        }
    }
}
