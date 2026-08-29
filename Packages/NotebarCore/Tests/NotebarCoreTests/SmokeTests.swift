import Testing
@testable import NotebarCore

@Test("core module is importable")
func coreIsImportable() {
    #expect(NotebarCore.version == "0.1.0")
}
