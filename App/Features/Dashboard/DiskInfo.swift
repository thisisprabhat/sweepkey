import Foundation

struct DiskInfo: Equatable {
    var freeBytes: Int64
    var totalBytes: Int64

    var usedFraction: Double {
        totalBytes > 0 ? Double(totalBytes - freeBytes) / Double(totalBytes) : 0
    }

    /// Free/total space on the home volume.
    static func current() -> DiskInfo? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity
        else { return nil }
        return DiskInfo(freeBytes: free, totalBytes: Int64(total))
    }
}
