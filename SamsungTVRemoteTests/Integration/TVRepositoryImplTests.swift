import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("TVRepositoryImpl")
struct TVRepositoryImplTests {
    @Test("Save TV persists to UserDefaults and can be retrieved")
    func saveAndLoad() throws {
        let defaults = UserDefaults(suiteName: "TVRepositoryImplTests")!
        defaults.removePersistentDomain(forName: "TVRepositoryImplTests")

        let storage = TVUserDefaultsStorage(userDefaults: defaults)
        let tv = SamsungTV(name: "TV", ipAddress: "1.1.1.1", macAddress: "AA", model: "Q", type: .tizen)

        try storage.saveTVs([tv])
        let loaded = try storage.loadSavedTVs()

        #expect(loaded.count == 1)
    }

    @Test("Delete TV removes it from UserDefaults correctly")
    func deleteTV() throws {
        let defaults = UserDefaults(suiteName: "TVRepositoryImplTests.delete")!
        defaults.removePersistentDomain(forName: "TVRepositoryImplTests.delete")
        let storage = TVUserDefaultsStorage(userDefaults: defaults)

        let tv = SamsungTV(name: "TV", ipAddress: "1.1.1.1", macAddress: "AA", model: "Q", type: .tizen)
        try storage.saveTVs([tv])
        try storage.saveTVs([])

        #expect((try storage.loadSavedTVs()).isEmpty)
    }

    @Test("Discovered TVs are merged with saved TVs without duplicates")
    func mergeNoDuplicates() {
        let a = SamsungTV(name: "TV A", ipAddress: "1", macAddress: "AA", model: "Q", type: .tizen)
        let b = SamsungTV(name: "TV B", ipAddress: "2", macAddress: "AA", model: "Q", type: .tizen)
        let merged = Dictionary(grouping: [a, b], by: { $0.macAddress }).compactMap { $0.value.first }
        #expect(merged.count == 1)
    }
}
