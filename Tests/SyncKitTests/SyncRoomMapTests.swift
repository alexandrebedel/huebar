import Testing
@testable import HueKit
@testable import SyncKit

@Test func mapsChannelsToRoomsThroughServices() {
    let ref = { (rid: String, rtype: String) in ResourceRef(rid: rid, rtype: rtype) }
    let config = EntertainmentConfig(
        id: "Z1", metadata: Metadata(name: "HueBar Sync"), status: "inactive",
        channels: [
            .init(channelID: 0, position: .init(x: -1, y: 1, z: 0),
                  members: [.init(service: ref("E1", "entertainment"))]),
            .init(channelID: 1, position: .init(x: 1, y: 1, z: 0),
                  members: [.init(service: ref("E2", "entertainment"))]),
            .init(channelID: 2, position: .init(x: 0, y: 1, z: 0), members: nil), // orphelin
        ])
    let services = [
        EntertainmentService(id: "E1", owner: ref("D1", "device")),
        EntertainmentService(id: "E2", owner: ref("D2", "device")),
    ]
    let rooms: [(id: String, deviceIDs: Set<String>)] = [
        (id: "R-sejour", deviceIDs: ["D1"]),
        (id: "R-cuisine", deviceIDs: ["D2", "D9"]),
    ]

    let entries = SyncRoomMap.entries(config: config, services: services, rooms: rooms)
    #expect(entries == [
        ChannelRoomEntry(channel: 0, roomID: "R-sejour", deviceID: "D1"),
        ChannelRoomEntry(channel: 1, roomID: "R-cuisine", deviceID: "D2"),
    ]) // le channel sans member est ignoré
}

@Test func pickZonePrefersHueBarSync() {
    let zone = { (name: String) in
        EntertainmentConfig(id: name, metadata: Metadata(name: name), status: "inactive", channels: [])
    }
    #expect(MusicSyncEngine.pickZone([zone("Autre"), zone("HueBar Sync")])?.id == "HueBar Sync")
    #expect(MusicSyncEngine.pickZone([zone("Autre")])?.id == "Autre")
    #expect(MusicSyncEngine.pickZone([]) == nil)
}
