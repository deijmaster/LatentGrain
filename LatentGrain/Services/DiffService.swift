import Foundation

/// Compares two `PersistenceSnapshot`s and produces a `PersistenceDiff`.
struct DiffService {

    func diff(before: PersistenceSnapshot, after: PersistenceSnapshot) -> PersistenceDiff {
        let beforeByPath = Dictionary(uniqueKeysWithValues: before.items.map { ($0.fullPath, $0) })
        let afterByPath  = Dictionary(uniqueKeysWithValues: after.items.map  { ($0.fullPath, $0) })

        let beforePaths = Set(beforeByPath.keys)
        let afterPaths  = Set(afterByPath.keys)

        let addedPaths   = afterPaths.subtracting(beforePaths)
        let removedPaths = beforePaths.subtracting(afterPaths)
        let commonPaths  = beforePaths.intersection(afterPaths)

        let added: [PersistenceItem] = addedPaths
            .compactMap { afterByPath[$0] }
            .sorted { $0.fullPath < $1.fullPath }

        let removed: [PersistenceItem] = removedPaths
            .compactMap { beforeByPath[$0] }
            .sorted { $0.fullPath < $1.fullPath }

        let modified: [(before: PersistenceItem, after: PersistenceItem)] = commonPaths
            .compactMap { path -> (before: PersistenceItem, after: PersistenceItem)? in
                guard
                    let b = beforeByPath[path],
                    let a = afterByPath[path],
                    b.contentsHash != a.contentsHash
                else { return nil }
                return (before: b, after: a)
            }
            .sorted { $0.before.fullPath < $1.before.fullPath }

        return PersistenceDiff(
            id: UUID(),
            before: before,
            after: after,
            added: added,
            removed: removed,
            modified: modified
        )
    }
}
