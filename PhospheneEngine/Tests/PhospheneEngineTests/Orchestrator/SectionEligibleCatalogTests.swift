// SectionEligibleCatalogTests — SECDET.6 completion-gated-preset section-length gate.
//
// A `wait_for_completion_event` preset reserves its full natural cycle, so on a non-last
// real section a preset whose cycle exceeds the section would swallow the later sections
// (live-test 2: Arachne's 150 s cycle ate a 203 s track's later boundaries). The gate keeps
// such presets out unless they fit, so section-rich tracks transition per section.

import Foundation
import Testing
@testable import Orchestrator
import Presets

@Suite("SectionEligibleCatalog (SECDET.6)")
struct SectionEligibleCatalogTests {

    /// Minimal decodable preset (the production sidecar fields the gate reads).
    private func preset(_ name: String, wait: Bool = false, cycle: Int? = nil, dur: Int = 30) throws
        -> PresetDescriptor {
        var json = "{\"name\":\"\(name)\",\"family\":\"geometric\",\"duration\":\(dur),\"passes\":[\"ray_march\"]"
        if wait { json += ",\"wait_for_completion_event\":true" }
        if let cycle { json += ",\"natural_cycle_seconds\":\(cycle)" }
        json += "}"
        return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    @Test("long completion-gated preset is dropped from a short non-last real section")
    func dropsLongWaitPresetOnShortSection() throws {
        let catalog = [try preset("Normal"), try preset("Arachne", wait: true, cycle: 150)]
        let pool = DefaultSessionPlanner.sectionEligibleCatalog(
            catalog, sectionLength: 30, isRealSection: true, isLastSection: false)
        #expect(pool.map(\.name) == ["Normal"], "Arachne (150 s cycle) can't fit a 30 s section")
    }

    @Test("completion-gated preset is kept when the section is long enough")
    func keepsWaitPresetOnLongSection() throws {
        let catalog = [try preset("Normal"), try preset("Arachne", wait: true, cycle: 150)]
        let pool = DefaultSessionPlanner.sectionEligibleCatalog(
            catalog, sectionLength: 200, isRealSection: true, isLastSection: false)
        #expect(pool.count == 2, "a 200 s section can hold Arachne's 150 s cycle")
    }

    @Test("the last section is exempt — a long build may run to the track end")
    func lastSectionExempt() throws {
        let catalog = [try preset("Normal"), try preset("Arachne", wait: true, cycle: 150)]
        let pool = DefaultSessionPlanner.sectionEligibleCatalog(
            catalog, sectionLength: 30, isRealSection: true, isLastSection: true)
        #expect(pool.count == 2, "nothing after the last section to swallow")
    }

    @Test("equal-slice (non-real) sections are not gated — legacy behaviour")
    func equalSliceNotGated() throws {
        let catalog = [try preset("Normal"), try preset("Arachne", wait: true, cycle: 150)]
        let pool = DefaultSessionPlanner.sectionEligibleCatalog(
            catalog, sectionLength: 30, isRealSection: false, isLastSection: false)
        #expect(pool.count == 2)
    }

    @Test("a completion-gated preset with no explicit cycle falls back to its duration")
    func cycleDefaultsToDuration() throws {
        // dur 20 ≤ 30 → fits; dur 90 > 30 → dropped.
        let catalog = [try preset("ShortWait", wait: true, dur: 20),
                       try preset("LongWait", wait: true, dur: 90)]
        let pool = DefaultSessionPlanner.sectionEligibleCatalog(
            catalog, sectionLength: 30, isRealSection: true, isLastSection: false)
        #expect(pool.map(\.name) == ["ShortWait"])
    }

    @Test("never empties the catalog — falls back when every preset is gated out")
    func neverEmpty() throws {
        let catalog = [try preset("Arachne", wait: true, cycle: 150)]   // only a too-long wait preset
        let pool = DefaultSessionPlanner.sectionEligibleCatalog(
            catalog, sectionLength: 30, isRealSection: true, isLastSection: false)
        #expect(pool.count == 1, "fall back to the full catalog rather than emptying it")
    }
}
