//
//  MediaAssetManager.swift
//  SaneVideo
//
//  Manages media asset references for iCloud sync
//  Converts between absolute URLs and relative paths for cross-device portability
//

import Foundation

/// Reference to a media asset that can be synced across devices
struct MediaAssetReference: Codable, Sendable, Equatable {
    let originalFilename: String
    let relativePath: String  // Relative to project folder
    let fileSize: Int64?
    let checksum: String?     // For integrity verification

    init(originalFilename: String, relativePath: String, fileSize: Int64? = nil, checksum: String? = nil) {
        self.originalFilename = originalFilename
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.checksum = checksum
    }
}

/// Actor for managing media asset paths and references for sync
actor MediaAssetManager {

    // MARK: - Properties

    /// Base directory for project media in iCloud Drive
    private let iCloudMediaBase: URL?

    /// Local media cache directory
    private let localCacheBase: URL

    init() {
        // iCloud Drive container for media files
        self.iCloudMediaBase = FileManager.default.url(
            forUbiquityContainerIdentifier: nil
        )?.appendingPathComponent("Documents/Media", isDirectory: true)

        // Local cache in Application Support
        self.localCacheBase = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("SaneVideo/MediaCache", isDirectory: true)

        // Ensure local cache exists
        try? FileManager.default.createDirectory(
            at: localCacheBase,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Path Conversion

    /// Convert an absolute URL to a relative path for sync
    /// - Parameters:
    ///   - url: Absolute file URL
    ///   - projectDir: Project directory base
    /// - Returns: Relative path string
    func relativePath(from url: URL, projectDir: URL) -> String {
        let urlPath = url.standardizedFileURL.path
        let basePath = projectDir.standardizedFileURL.path

        if urlPath.hasPrefix(basePath) {
            // Already in project directory
            return String(urlPath.dropFirst(basePath.count + 1))
        }

        // External file - use filename only
        return "Media/\(url.lastPathComponent)"
    }

    /// Resolve a relative path to an absolute URL
    /// - Parameters:
    ///   - relativePath: Relative path from asset reference
    ///   - projectDir: Project directory base
    /// - Returns: Resolved URL if file exists
    func resolveAsset(relativePath: String, projectDir: URL) -> URL? {
        let resolvedURL = projectDir.appendingPathComponent(relativePath)

        if FileManager.default.fileExists(atPath: resolvedURL.path) {
            return resolvedURL
        }

        // Try local cache
        let cachedURL = localCacheBase.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        // Try iCloud media folder
        if let iCloudURL = iCloudMediaBase?.appendingPathComponent(relativePath),
           FileManager.default.fileExists(atPath: iCloudURL.path) {
            return iCloudURL
        }

        return nil
    }

    /// Create an asset reference from a URL
    /// - Parameters:
    ///   - url: Source file URL
    ///   - projectId: Project identifier for organization
    /// - Returns: Asset reference with relative path
    func createAssetReference(
        from url: URL,
        projectId: UUID
    ) async throws -> MediaAssetReference {
        let fileManager = FileManager.default

        // Get file attributes
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64

        // Calculate checksum for integrity
        let checksum = try await calculateChecksum(for: url)

        // Create relative path
        let relativePath = "Media/\(projectId.uuidString)/\(url.lastPathComponent)"

        return MediaAssetReference(
            originalFilename: url.lastPathComponent,
            relativePath: relativePath,
            fileSize: fileSize,
            checksum: checksum
        )
    }

    // MARK: - Asset Operations

    /// Copy asset to project's media folder for sync
    /// - Parameters:
    ///   - sourceURL: Source file URL
    ///   - projectId: Project identifier
    /// - Returns: URL in project media folder
    func copyAssetToProjectFolder(
        sourceURL: URL,
        projectId: UUID
    ) async throws -> URL {
        guard let iCloudBase = iCloudMediaBase else {
            throw MediaAssetError.iCloudNotAvailable
        }

        let projectMediaDir = iCloudBase.appendingPathComponent(projectId.uuidString, isDirectory: true)

        // Create project media directory
        try FileManager.default.createDirectory(
            at: projectMediaDir,
            withIntermediateDirectories: true
        )

        let destinationURL = projectMediaDir.appendingPathComponent(sourceURL.lastPathComponent)

        // Check if already exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            // Verify checksum matches
            let sourceChecksum = try await calculateChecksum(for: sourceURL)
            let destChecksum = try await calculateChecksum(for: destinationURL)

            if sourceChecksum == destChecksum {
                return destinationURL  // Already synced
            }

            // Different file - remove and re-copy
            try FileManager.default.removeItem(at: destinationURL)
        }

        // Copy file
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        return destinationURL
    }

    /// Download asset from iCloud to local cache
    /// - Parameter reference: Asset reference to download
    /// - Returns: Local URL of downloaded file
    func downloadAsset(_ reference: MediaAssetReference) async throws -> URL {
        guard let iCloudBase = iCloudMediaBase else {
            throw MediaAssetError.iCloudNotAvailable
        }

        let iCloudURL = iCloudBase.appendingPathComponent(reference.relativePath)

        // Check if file is already downloaded
        var isDownloaded = false
        var isDownloading = false

        if let resourceValues = try? iCloudURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) {
            switch resourceValues.ubiquitousItemDownloadingStatus {
            case .current:
                isDownloaded = true
            case .downloaded:
                isDownloaded = true
            case .notDownloaded:
                isDownloaded = false
            @unknown default:
                break
            }
        }

        if !isDownloaded {
            // Start download
            try FileManager.default.startDownloadingUbiquitousItem(at: iCloudURL)

            // Wait for download with timeout
            let timeout = Date().addingTimeInterval(300) // 5 minute timeout
            while !isDownloaded && Date() < timeout {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                if let resourceValues = try? iCloudURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) {
                    isDownloaded = resourceValues.ubiquitousItemDownloadingStatus == .current ||
                                   resourceValues.ubiquitousItemDownloadingStatus == .downloaded
                }
            }

            if !isDownloaded {
                throw MediaAssetError.downloadTimeout
            }
        }

        // Copy to local cache
        let localURL = localCacheBase.appendingPathComponent(reference.relativePath)
        let localDir = localURL.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }

        try FileManager.default.copyItem(at: iCloudURL, to: localURL)

        // Verify checksum
        if let expectedChecksum = reference.checksum {
            let actualChecksum = try await calculateChecksum(for: localURL)
            if actualChecksum != expectedChecksum {
                try? FileManager.default.removeItem(at: localURL)
                throw MediaAssetError.checksumMismatch
            }
        }

        return localURL
    }

    // MARK: - Utilities

    /// Calculate SHA256 checksum of a file
    private func calculateChecksum(for url: URL) async throws -> String {
        let data = try Data(contentsOf: url)
        let hash = data.withUnsafeBytes { bytes in
            var hasher = SHA256()
            hasher.update(data: bytes)
            return hasher.finalize()
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Check if iCloud is available
    var isICloudAvailable: Bool {
        iCloudMediaBase != nil
    }

    /// Get iCloud storage status
    func getICloudStorageStatus() async throws -> (used: Int64, available: Int64) {
        guard let iCloudBase = iCloudMediaBase else {
            throw MediaAssetError.iCloudNotAvailable
        }

        let values = try iCloudBase.resourceValues(forKeys: [
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey
        ])

        let available = values.volumeAvailableCapacity ?? 0
        let total = values.volumeTotalCapacity ?? 0

        return (used: Int64(total - available), available: Int64(available))
    }
}

// MARK: - SHA256 Implementation

private struct SHA256 {
    private var state: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]
    private var buffer = [UInt8]()
    private var totalLength: UInt64 = 0

    mutating func update(data: UnsafeRawBufferPointer) {
        var bytes = Array(data)
        totalLength += UInt64(bytes.count)
        buffer.append(contentsOf: bytes)
    }

    mutating func finalize() -> [UInt8] {
        // Pad message
        buffer.append(0x80)
        while (buffer.count % 64) != 56 {
            buffer.append(0x00)
        }

        // Append length in bits
        let bitLength = totalLength * 8
        for i in stride(from: 56, through: 0, by: -8) {
            buffer.append(UInt8(truncatingIfNeeded: bitLength >> i))
        }

        // Process blocks
        for i in stride(from: 0, to: buffer.count, by: 64) {
            processBlock(Array(buffer[i..<i+64]))
        }

        // Convert state to bytes
        var result = [UInt8]()
        for word in state {
            result.append(UInt8(truncatingIfNeeded: word >> 24))
            result.append(UInt8(truncatingIfNeeded: word >> 16))
            result.append(UInt8(truncatingIfNeeded: word >> 8))
            result.append(UInt8(truncatingIfNeeded: word))
        }
        return result
    }

    private mutating func processBlock(_ block: [UInt8]) {
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        ]

        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            w[i] = UInt32(block[i*4]) << 24 | UInt32(block[i*4+1]) << 16 |
                   UInt32(block[i*4+2]) << 8 | UInt32(block[i*4+3])
        }

        for i in 16..<64 {
            let s0 = rotateRight(w[i-15], 7) ^ rotateRight(w[i-15], 18) ^ (w[i-15] >> 3)
            let s1 = rotateRight(w[i-2], 17) ^ rotateRight(w[i-2], 19) ^ (w[i-2] >> 10)
            w[i] = w[i-16] &+ s0 &+ w[i-7] &+ s1
        }

        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]

        for i in 0..<64 {
            let s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
            let ch = (e & f) ^ (~e & g)
            let temp1 = h &+ s1 &+ ch &+ k[i] &+ w[i]
            let s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = s0 &+ maj

            h = g; g = f; f = e; e = d &+ temp1
            d = c; c = b; b = a; a = temp1 &+ temp2
        }

        state[0] &+= a; state[1] &+= b; state[2] &+= c; state[3] &+= d
        state[4] &+= e; state[5] &+= f; state[6] &+= g; state[7] &+= h
    }

    private func rotateRight(_ x: UInt32, _ n: Int) -> UInt32 {
        (x >> n) | (x << (32 - n))
    }
}

// MARK: - Errors

enum MediaAssetError: LocalizedError {
    case iCloudNotAvailable
    case downloadTimeout
    case checksumMismatch
    case fileNotFound
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud is not available. Please sign in to iCloud."
        case .downloadTimeout:
            return "Download timed out. Please check your network connection."
        case .checksumMismatch:
            return "File integrity check failed. The file may be corrupted."
        case .fileNotFound:
            return "The media file could not be found."
        case .copyFailed:
            return "Failed to copy the media file."
        }
    }
}
