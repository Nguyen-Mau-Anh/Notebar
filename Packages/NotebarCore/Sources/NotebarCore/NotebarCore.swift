import Foundation

/// Namespace marker for the pure-Swift core.
///
/// This module must never import AppKit, SwiftUI, or UIKit.
/// `scripts/check-core-purity.sh` enforces that mechanically.
public enum NotebarCore {
    public static let version = "0.1.0"
}
