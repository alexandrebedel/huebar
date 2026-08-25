import Foundation

/// Style de réactivité lumineuse.
public enum SyncMode: String, Sendable, CaseIterable, Identifiable {
    case club
    case chill

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .club: "Club"
        case .chill: "Chill"
        }
    }
}
