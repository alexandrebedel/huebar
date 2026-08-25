import Testing
@testable import SyncKit

@Test func modesAreClubAndChill() {
    #expect(SyncMode.allCases == [.club, .chill])
}
