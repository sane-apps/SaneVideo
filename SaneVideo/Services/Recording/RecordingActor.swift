import Foundation

/// Global actor for all recording-related background processing.
/// This ensures strict serialization of media samples and state changes
/// without blocking the Main Actor.
@globalActor
public actor RecordingActor {
    public static let shared = RecordingActor()
}
