import Testing
@testable import SyncKit

@Test func modesAreClubChillAndHorror() {
    #expect(SyncMode.allCases == [.club, .chill, .horror])
    #expect(SyncMode.horror.label == "Film d'horreur")
}
