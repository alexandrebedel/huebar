import Foundation

public enum HueError: Error, Equatable {
    case missingCredentials(String)
    case invalidResponse
    case badStatus(Int)
}
