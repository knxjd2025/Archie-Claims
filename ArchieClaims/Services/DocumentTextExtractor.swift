import Foundation
import PDFKit
import Vision
import UniformTypeIdentifiers

/// Extracts text from attached insurance documents on-device so it can ride
/// along in the AI chat: PDFKit for PDFs, Vision OCR for photos/scans, and
/// plain decoding for text/email files. No bytes leave the phone for
/// extraction; the original file is separately uploaded to the CRM.
enum DocumentTextExtractor {

    /// Cap per document so a giant estimate can't blow up the chat request.
    static let maxCharacters = 15_000

    struct Extraction {
        let filename: String
        let mimeType: String
        let data: Data
        let text: String
        let truncated: Bool
    }

    enum ExtractionError: LocalizedError {
        case unreadable
        case unsupportedType(String)
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "Couldn't read that file."
            case .unsupportedType(let type):
                return "Unsupported file type (\(type)). Use a PDF, photo, or text/email file."
            case .noTextFound:
                return "No readable text found in that document."
            }
        }
    }

    /// Loads a security-scoped picked file and extracts its text.
    static func extract(from url: URL) async throws -> Extraction {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw ExtractionError.unreadable }
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        return try await extract(data: data, filename: url.lastPathComponent, type: type)
    }

    static func extract(data: Data, filename: String, type: UTType) async throws -> Extraction {
        let mimeType = type.preferredMIMEType ?? "application/octet-stream"

        let raw: String
        if type.conforms(to: .pdf) {
            raw = try extractPDF(data: data)
        } else if type.conforms(to: .image) {
            raw = try await ocrImage(data: data)
        } else if type.conforms(to: .text) || type.conforms(to: .emailMessage) {
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                throw ExtractionError.unreadable
            }
            raw = text
        } else {
            throw ExtractionError.unsupportedType(type.identifier)
        }

        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ExtractionError.noTextFound }
        let truncated = cleaned.count > maxCharacters
        return Extraction(
            filename: filename,
            mimeType: mimeType,
            data: data,
            text: truncated ? String(cleaned.prefix(maxCharacters)) + "\n[…document truncated]" : cleaned,
            truncated: truncated
        )
    }

    private static func extractPDF(data: Data) throws -> String {
        guard let document = PDFDocument(data: data) else { throw ExtractionError.unreadable }
        var pages: [String] = []
        for index in 0..<min(document.pageCount, 40) {
            if let text = document.page(at: index)?.string, !text.isEmpty {
                pages.append(text)
            }
        }
        let joined = pages.joined(separator: "\n")
        // Scanned PDFs have no text layer — OCR the first pages instead.
        if joined.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
            throw ExtractionError.noTextFound
        }
        return joined
    }

    private static func ocrImage(data: Data) async throws -> String {
        guard let image = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(image, 0, nil) else {
            throw ExtractionError.unreadable
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage).perform([request])
                    let lines = (request.results ?? []).compactMap {
                        $0.topCandidates(1).first?.string
                    }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    continuation.resume(throwing: ExtractionError.unreadable)
                }
            }
        }
    }
}
