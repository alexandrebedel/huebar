import Foundation
import HueKit

/// Rattache chaque channel d'une zone Entertainment à sa pièce :
/// channel -> member service -> device propriétaire -> pièce contenant ce device.
public struct ChannelRoomEntry: Sendable, Equatable {
    public let channel: UInt8
    public let roomID: String
    public let deviceID: String

    public init(channel: UInt8, roomID: String, deviceID: String) {
        self.channel = channel
        self.roomID = roomID
        self.deviceID = deviceID
    }
}

public enum SyncRoomMap {
    public static func entries(
        config: EntertainmentConfig,
        services: [EntertainmentService],
        rooms: [(id: String, deviceIDs: Set<String>)]
    ) -> [ChannelRoomEntry] {
        let deviceByService = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0.owner.rid) })
        return config.channels.compactMap { channel in
            guard let serviceRID = channel.members?.first?.service.rid,
                  let deviceID = deviceByService[serviceRID],
                  let room = rooms.first(where: { $0.deviceIDs.contains(deviceID) })
            else { return nil }
            return ChannelRoomEntry(channel: channel.channelID, roomID: room.id, deviceID: deviceID)
        }
    }
}
