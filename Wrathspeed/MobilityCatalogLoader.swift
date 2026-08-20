import Foundation
import WrathspeedCore

struct MobilityCatalog: Codable, Equatable {
    var version: Int
    var routines: [MobilityRoutineTemplate]
}

struct MobilityRoutineTemplate: Codable, Equatable, Identifiable {
    var id: String
    var category: MobilityCategory
    var title: String
    var durationMinutes: Int
    var movements: [MobilityMovement]
}

enum MobilityCatalogLoader {
    static func load() throws -> MobilityCatalog {
        let url = Bundle.main.url(forResource: "mobility_catalog", withExtension: "json")
            ?? Bundle.main.bundleURL.appending(path: "mobility_catalog.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MobilityCatalog.self, from: data)
    }

    static func allRoutines() throws -> [MobilityRoutineTemplate] {
        try load().routines
    }

    static func routine(id: String) throws -> MobilityRoutineTemplate? {
        try allRoutines().first { $0.id == id }
    }

    static func allSessions(date: Date = Date(), calendar: Calendar = .current) throws -> [MobilitySession] {
        try allRoutines().map { makeSession(from: $0, date: date, calendar: calendar) }
    }

    static func makeSession(
        from routine: MobilityRoutineTemplate,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> MobilitySession {
        MobilitySession(
            id: stableSessionID(routineID: routine.id, date: date, calendar: calendar),
            date: calendar.startOfDay(for: date),
            category: routine.category,
            title: routine.title,
            movements: routine.movements,
            durationMinutes: routine.durationMinutes,
            routineID: routine.id
        )
    }

    static func stableSessionID(routineID: String, date: Date, calendar: Calendar = .current) -> UUID {
        let day = calendar.startOfDay(for: date)
        var bytes = [UInt8](repeating: 0, count: 16)
        let seed = "wrathspeed.mobility.\(routineID).\(Int(day.timeIntervalSince1970))"
        for (offset, byte) in seed.utf8.enumerated() {
            bytes[offset % 16] ^= byte
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
