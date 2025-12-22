//
//  CMTime+Extensions.swift
//  SaneVideo
//
//  CMTime convenience extensions

import AVFoundation
import Foundation

extension CMTime {
    /// Create CMTime from seconds with standard timescale (retained for convenience)
    init(seconds: Double) {
        self.init(seconds: seconds, preferredTimescale: 600)
    }
}
