import Foundation
import LidSwitchCore
import Testing

struct DisplaySelectionResolverTests {
    private let resolver = DisplaySelectionResolver()

    @Test func ignoresOfflineGhostAndFollowsVisibleReplacement() {
        let old = external(id: 2, active: false, online: false)
        let selection = ExternalDisplaySelection(display: old, name: "Redmi 27 NU")
        let replacement = external(id: 3, active: true, online: true)
        let snapshot = DisplaySnapshot(lid: .closed, displays: [replacement, old])

        #expect(resolver.resolve(selection, in: snapshot)?.id == 3)
    }

    @Test func resolvesDisplayIntentionallyDisabledByLidSwitch() {
        let display = external(id: 3, active: false, online: false)
        let selection = ExternalDisplaySelection(display: display, name: "Redmi 27 NU")
        let snapshot = DisplaySnapshot(lid: .open, displays: [display])

        #expect(resolver.resolve(
            selection,
            in: snapshot,
            controlledOfflineIDs: [3]
        )?.id == 3)
    }

    @Test func doesNotResolveUncontrolledOfflineGhost() {
        let display = external(id: 2, active: false, online: false)
        let selection = ExternalDisplaySelection(display: display, name: "Redmi 27 NU")
        let snapshot = DisplaySnapshot(lid: .closed, displays: [display])

        #expect(resolver.resolve(selection, in: snapshot) == nil)
    }

    @Test func ambiguousIdenticalVisibleDisplaysRequireExactID() {
        let selected = external(id: 2, active: false, online: false)
        let selection = ExternalDisplaySelection(display: selected, name: "Display")
        let snapshot = DisplaySnapshot(
            lid: .open,
            displays: [
                external(id: 3, active: true, online: true),
                external(id: 4, active: true, online: true)
            ]
        )

        #expect(resolver.resolve(selection, in: snapshot) == nil)
    }

    @Test func reusedDisplayIDWithDifferentHardwareIsNotSelected() {
        let selection = ExternalDisplaySelection(
            display: external(id: 3, active: true, online: true), name: "Redmi"
        )
        let unrelated = DisplayRecord(
            id: 3, vendor: 999, model: 123, serial: 42,
            isBuiltIn: false, isActive: true, isOnline: true, isMain: true
        )
        let snapshot = DisplaySnapshot(lid: .open, displays: [unrelated])
        #expect(resolver.resolve(selection, in: snapshot) == nil)
        #expect(resolver.resolveAll([selection], in: snapshot).isEmpty)
    }

    @Test func multipleSelectionsResolveToDistinctDisplays() {
        let first = external(id: 3, active: true, online: true)
        let second = external(id: 4, active: false, online: false)
        let selections = [
            ExternalDisplaySelection(display: first, name: "First"),
            ExternalDisplaySelection(display: second, name: "Second")
        ]
        let snapshot = DisplaySnapshot(lid: .open, displays: [first, second])
        let result = resolver.resolveAll(selections, in: snapshot, controlledOfflineIDs: [4])
        #expect(result[selections[0].selectionID]?.id == 3)
        #expect(result[selections[1].selectionID]?.id == 4)
    }

    @Test func missingSameModelSelectionDoesNotClaimAlreadySelectedDisplay() {
        let first = external(id: 3, active: true, online: true)
        let missing = external(id: 4, active: false, online: false)
        let selections = [
            ExternalDisplaySelection(display: missing, name: "Missing"),
            ExternalDisplaySelection(display: first, name: "Connected")
        ]
        let snapshot = DisplaySnapshot(lid: .closed, displays: [first, missing])
        let result = resolver.resolveAll(selections, in: snapshot)
        #expect(result[selections[0].selectionID] == nil)
        #expect(result[selections[1].selectionID]?.id == 3)
    }

    @Test func legacySelectionDecodesAndGetsPersistentIdentity() throws {
        let data = Data(#"{"vendor":25001,"model":45061,"serial":0,"lastDisplayID":3,"name":"Redmi"}"#.utf8)
        let decoded = try JSONDecoder().decode(ExternalDisplaySelection.self, from: data)
        let saved = try JSONEncoder().encode([decoded])
        let restored = try JSONDecoder().decode([ExternalDisplaySelection].self, from: saved)
        #expect(restored == [decoded])
    }

    @Test func visibleReplacementWinsOverPreviouslyControlledGhost() {
        let old = external(id: 2, active: false, online: false)
        let selection = ExternalDisplaySelection(display: old, name: "Redmi")
        let replacement = external(id: 3, active: true, online: true)
        let snapshot = DisplaySnapshot(lid: .closed, displays: [old, replacement])
        let result = resolver.resolveAll([selection], in: snapshot, controlledOfflineIDs: [2])
        #expect(result[selection.selectionID]?.id == 3)
    }

    private func external(id: UInt32, active: Bool, online: Bool) -> DisplayRecord {
        DisplayRecord(
            id: id,
            vendor: 25001,
            model: 45061,
            serial: 0,
            isBuiltIn: false,
            isActive: active,
            isOnline: online,
            isMain: active
        )
    }
}
