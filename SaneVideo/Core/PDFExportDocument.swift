//
//  PDFExportDocument.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI
import UniformTypeIdentifiers

struct PDFExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var pdfData: Data

    init(data: Data) {
        pdfData = data
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            pdfData = data
        } else {
            pdfData = Data()
        }
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: pdfData)
    }
}
