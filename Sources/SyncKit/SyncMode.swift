import Foundation

/// Style de réactivité lumineuse.
public enum SyncMode: String, Sendable, CaseIterable, Identifiable {
    case club
    case chill
    /// Pour regarder un film : sombre, gronde en rouge, éclate sur les sursauts.
    case horror

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .club: "Club"
        case .chill: "Chill"
        case .horror: "Film d'horreur"
        }
    }
}
