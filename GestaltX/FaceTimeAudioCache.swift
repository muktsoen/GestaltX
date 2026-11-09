// SPDX-License-Identifier: GPL-3.0-only
// Cache offsets are resolved from the device library and matched to the plist layout.
import Foundation

enum FaceTimeAudioChoice: Int, CaseIterable, Identifiable {
    case keep, enable, restoreOriginal
    var id: Int { rawValue }
    var title: LocalizedStringResource {
        switch self {
        case .keep: "Keep Current"
        case .enable: "Enable"
        case .restoreOriginal: "Disable (Restore Original)"
        }
    }
}

struct FaceTimeAudioFlags: Equatable, Codable, Sendable {
    let greenTea: Bool
    let notGreenTea: Bool

    static let enabled = Self(greenTea: false, notGreenTea: true)
    static let restricted = Self(greenTea: true, notGreenTea: false)
}

// Bind saved values to the cache layout; model and OS version are metadata only.
struct FaceTimeAudioOriginal: Codable, Equatable, Sendable {
    let productType: String
    let build: String
    let layoutUUID: String
    let flags: FaceTimeAudioFlags

    init(document: GestaltDocument) throws {
        flags = try FaceTimeAudioCache.flags(in: document)
        productType = document.extra[GestaltKeys.productType] as? String ?? ""
        build = document.root["CacheVersion"] as? String ?? ""
        layoutUUID = document.root["CacheUUID"] as? String ?? ""
    }

    func flags(in document: GestaltDocument) throws -> FaceTimeAudioFlags {
        _ = try FaceTimeAudioCache.validatedData(in: document)
        guard document.root["CacheUUID"] as? String == layoutUUID else {
            throw GestaltFailure("The cache layout or values do not match this preset.")
        }
        return flags
    }
}

struct CachedBooleanChange: Identifiable {
    let name: String
    let offset: Int
    let before: Bool
    let after: Bool
    var id: Int { offset }
}

enum FaceTimeAudioCache {
    static let greenTeaKey = "iyfxmLogGVIaH7aEgqwcIA"
    static let notGreenTeaKey = "4snMZS8LJkSctKypt2m+xA"

    static func validatedData(in document: GestaltDocument, using resolvedLayout: MobileGestaltCacheLayout? = nil) throws -> Data {
        let layout = try resolvedLayout ?? MobileGestaltCacheLayout.resolve(in: document)
        guard layout.matches(document), let data = document.root["CacheData"] as? Data,
              data[layout.validityOffset(for: layout.greenTeaIndex)] == 1,
              data[layout.validityOffset(for: layout.notGreenTeaIndex)] == 1,
              [layout.greenTeaOffset, layout.notGreenTeaOffset].allSatisfy({ offset in
                  data[offset] <= 1 && data[(offset + 1)..<(offset + 8)].allSatisfy { $0 == 0 }
              }),
              [greenTeaKey, notGreenTeaKey, "green-tea", "not-green-tea"].allSatisfy({ document.extra[$0] == nil }) else {
            throw GestaltFailure("The cache layout or values do not match this preset.")
        }
        return data
    }

    static func flags(in document: GestaltDocument, using resolvedLayout: MobileGestaltCacheLayout? = nil) throws -> FaceTimeAudioFlags {
        let layout = try resolvedLayout ?? MobileGestaltCacheLayout.resolve(in: document)
        let data = try validatedData(in: document, using: layout)
        return FaceTimeAudioFlags(greenTea: data[layout.greenTeaOffset] == 1,
                                  notGreenTea: data[layout.notGreenTeaOffset] == 1)
    }

    static func changes(from original: GestaltDocument, to edited: GestaltDocument) -> [CachedBooleanChange] {
        guard let before = original.root["CacheData"] as? Data,
              let after = edited.root["CacheData"] as? Data,
              before != after,
              (try? validatedData(in: original)) != nil,
              let layout = try? MobileGestaltCacheLayout.resolve(in: original),
              after.count == before.count else { return [] }
        return [("green-tea", layout.greenTeaOffset), ("not-green-tea", layout.notGreenTeaOffset)].compactMap { name, offset in
            guard before[offset] != after[offset] else { return nil }
            return CachedBooleanChange(name: name, offset: offset, before: before[offset] != 0, after: after[offset] != 0)
        }
    }

    static func validateEdit(from original: GestaltDocument, to edited: GestaltDocument,
                             using resolvedLayout: MobileGestaltCacheLayout? = nil) throws {
        guard original.root["CacheData"] as? Data != edited.root["CacheData"] as? Data else { return }
        let layout = try resolvedLayout ?? MobileGestaltCacheLayout.resolve(in: original)
        let before = try validatedData(in: original, using: layout)
        let after = try validatedData(in: edited, using: layout)
        guard before.indices.allSatisfy({ index in
            index == layout.greenTeaOffset || index == layout.notGreenTeaOffset || before[index] == after[index]
        }) else {
            throw GestaltFailure("This preset changes unrelated cache bytes.")
        }
    }
}
