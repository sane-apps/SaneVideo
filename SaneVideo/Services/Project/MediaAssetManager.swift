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
    let relativePath: String // Relative to project folder
    let fileSize: Int64?
    let checksum: String? // For integrity verification

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

    /// Base directory for project media in iCloud Drive, resolved only when sync features are used.
    private var resolvedICloudMediaBase: URL?

    /// Local media cache directory
    private let localCacheBase: URL

    init() {
        // Local cache in Application Support
        localCacheBase = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("SaneVideo/MediaCache", isDirectory: true)

        // Ensure local cache exists
        try? FileManager.default.createDirectory(
            at: localCacheBase,
            withIntermediateDirectories: true
        )
    }

    private func iCloudMediaBase() -> URL? {
        if let resolvedICloudMediaBase {
            return resolvedICloudMediaBase
        }

        guard Self.canQueryRealICloudContainer else {
            return nil
        }

        let url = FileManager.default.url(
            forUbiquityContainerIdentifier: nil
        )?.appendingPathComponent("Documents/Media", isDirectory: true)
        resolvedICloudMediaBase = url
        return url
    }

    private static var canQueryRealICloudContainer: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["SANEVIDEO_ENABLE_REAL_ICLOUD_TESTS"] == "1" {
            return true
        }

        return !TestEnvironment.isTesting
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
        if let iCloudURL = iCloudMediaBase()?.appendingPathComponent(relativePath),
           FileManager.default.fileExists(atPath: iCloudURL.path)
        {
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
        guard let iCloudBase = iCloudMediaBase() else {
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
                return destinationURL // Already synced
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
        guard let iCloudBase = iCloudMediaBase() else {
            throw MediaAssetError.iCloudNotAvailable
        }

        let iCloudURL = iCloudBase.appendingPathComponent(reference.relativePath)

        // Check if file is already downloaded
        var isDownloaded = false

        if let resourceValues = try? iCloudURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           let status = resourceValues.ubiquitousItemDownloadingStatus
        {
            // URLUbiquitousItemDownloadingStatus is a typed string (NS_TYPED_ENUM), not a true enum
            isDownloaded = (status == .current || status == .downloaded)
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
        iCloudMediaBase() != nil
    }

    /// Get iCloud storage status
    func getICloudStorageStatus() async throws -> (used: Int64, available: Int64) {
        guard let iCloudBase = iCloudMediaBase() else {
            throw MediaAssetError.iCloudNotAvailable
        }

        let values = try iCloudBase.resourceValues(forKeys: [
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
        ])

        let available = values.volumeAvailableCapacity ?? 0
        let total = values.volumeTotalCapacity ?? 0

        return (used: Int64(total - available), available: Int64(available))
    }
}

// MARK: - SHA256 Implementation

private struct SHA256 {
    private var state: [UInt32] = [
        0x6A09_E667, 0xBB67_AE85, 0x3C6E_F372, 0xA54F_F53A,
        0x510E_527F, 0x9B05_688C, 0x1F83_D9AB, 0x5BE0_CD19,
    ]
    private var buffer = [UInt8]()
    private var totalLength: UInt64 = 0

    mutating func update(data: UnsafeRawBufferPointer) {
        let bytes = Array(data)
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
            processBlock(Array(buffer[i ..< i + 64]))
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
            0x428A_2F98, 0x7137_4491, 0xB5C0_FBCF, 0xE9B5_DBA5, 0x3956_C25B, 0x59F1_11F1, 0x923F_82A4, 0xAB1C_5ED5,
            0xD807_AA98, 0x1283_5B01, 0x2431_85BE, 0x550C_7DC3, 0x72BE_5D74, 0x80DE_B1FE, 0x9BDC_06A7, 0xC19B_F174,
            0xE49B_69C1, 0xEFBE_4786, 0x0FC1_9DC6, 0x240C_A1CC, 0x2DE9_2C6F, 0x4A74_84AA, 0x5CB0_A9DC, 0x76F9_88DA,
            0x983E_5152, 0xA831_C66D, 0xB003_27C8, 0xBF59_7FC7, 0xC6E0_0BF3, 0xD5A7_9147, 0x06CA_6351, 0x1429_2967,
            0x27B7_0A85, 0x2E1B_2138, 0x4D2C_6DFC, 0x5338_0D13, 0x650A_7354, 0x766A_0ABB, 0x81C2_C92E, 0x9272_2C85,
            0xA2BF_E8A1, 0xA81A_664B, 0xC24B_8B70, 0xC76C_51A3, 0xD192_E819, 0xD699_0624, 0xF40E_3585, 0x106A_A070,
            0x19A4_C116, 0x1E37_6C08, 0x2748_774C, 0x34B0_BCB5, 0x391C_0CB3, 0x4ED8_AA4A, 0x5B9C_CA4F, 0x682E_6FF3,
            0x748F_82EE, 0x78A5_636F, 0x84C8_7814, 0x8CC7_0208, 0x90BE_FFFA, 0xA450_6CEB, 0xBEF9_A3F7, 0xC671_78F2,
        ]

        var w = [UInt32](repeating: 0, count: 64)
        for i in 0 ..< 16 {
            w[i] = UInt32(block[i * 4]) << 24 | UInt32(block[i * 4 + 1]) << 16 |
                UInt32(block[i * 4 + 2]) << 8 | UInt32(block[i * 4 + 3])
        }

        for i in 16 ..< 64 {
            let s0 = rotateRight(w[i - 15], 7) ^ rotateRight(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotateRight(w[i - 2], 17) ^ rotateRight(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }

        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]

        for i in 0 ..< 64 {
            let s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
            let ch = (e & f) ^ (~e & g)
            let temp1 = h &+ s1 &+ ch &+ k[i] &+ w[i]
            let s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = s0 &+ maj

            h = g
            g = f
            f = e
            e = d &+ temp1
            d = c
            c = b
            b = a
            a = temp1 &+ temp2
        }

        state[0] &+= a
        state[1] &+= b
        state[2] &+= c
        state[3] &+= d
        state[4] &+= e
        state[5] &+= f
        state[6] &+= g
        state[7] &+= h
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
