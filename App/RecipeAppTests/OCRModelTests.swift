import CoreGraphics
import CoreText
import Foundation
import ImageIO
import RecipeCore
import RecipeImport
import Testing
import UniformTypeIdentifiers

@testable import RecipeApp

/// OCR on a photo the test renders itself: a plain image with the
/// recipe text drawn on it. No fixture photo needed.
@MainActor
struct OCRModelTests {
    /// Renders black text on a white canvas and returns PNG bytes.
    private func renderText(_ lines: [String]) throws -> Data {
        let width = 800
        let height = Int(CGFloat(lines.count) * 60 + 120)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        for (index, line) in lines.enumerated() {
            let font = CTFontCreateWithName("Helvetica" as CFString, 34, nil)
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ]
            let attributed = CFAttributedStringCreate(
                nil, line as CFString, attributes as CFDictionary)!
            let lineRef = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: 40, y: CGFloat(height - 80 - index * 60))
            CTLineDraw(lineRef, context)
        }
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithData(
            NSMutableData() as NSMutableData, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        // The destination wrote into our mutable data; redo with a kept
        // reference to read it back.
        let data = NSMutableData()
        let final = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(final, image, nil)
        CGImageDestinationFinalize(final)
        return data as Data
    }

    @Test func ocrReadsARenderedRecipeCard() async throws {
        let png = try renderText([
            "Sunny Scramble",
            "Ingredients",
            "3 eggs",
            "1 tbsp butter",
            "Directions",
            "Melt the butter.",
            "Add the eggs and stir.",
        ])
        let lines = try await OCRModel.recognize(png)
        let text = lines.joined(separator: "\n")
        #expect(text.contains("Scramble"))
        #expect(text.contains("butter"))

        // The recognized text goes through the chain and saves.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("g2-ocr-\(UUID().uuidString)")
        let model = LibraryModel(
            root: root,
            clock: LibraryClock(now: { 1_800_000_000 }, newID: { UUID().uuidString }))
        let importer = ImportModel()
        let ocr = OCRModel.shared
        await ocr.importPhoto(png, into: model, importer: importer)
        guard case .done(let document) = importer.stage else {
            Issue.record("OCR import did not finish: \(importer.stage)")
            return
        }
        #expect(!document.title.isEmpty)
        #expect(!model.recipes.isEmpty)
        // The photo itself was stored and referenced.
        #expect(document.photoHashes.count == 1)
        #expect(model.photos.data(for: document.photoHashes[0]) != nil)
    }

    @Test func blankImageReportsNoReadableText() async throws {
        let png = try renderText([" "])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("g2-ocr2-\(UUID().uuidString)")
        let model = LibraryModel(
            root: root,
            clock: LibraryClock(now: { 1_800_000_000 }, newID: { UUID().uuidString }))
        let importer = ImportModel()
        await OCRModel.shared.importPhoto(png, into: model, importer: importer)
        guard case .failed(let message) = importer.stage else {
            Issue.record("expected a readable failure, got \(importer.stage)")
            return
        }
        #expect(message.contains("No readable text"))
        #expect(model.recipes.isEmpty)
    }
}
