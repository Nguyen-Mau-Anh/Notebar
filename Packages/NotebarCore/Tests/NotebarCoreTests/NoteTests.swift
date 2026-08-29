import Testing
@testable import NotebarCore

/// `isEmptyAndUntitled` is the predicate `PanelViewModel.closeNote` uses to
/// decide whether closing a note's tab should delete the note outright
/// instead of just closing the tab (user report: closing an "Untitled",
/// empty note left it stranded in the all-notes menu with no way back in
/// except the down-arrow button). Covered here as a pure `Note` property so
/// the rule is exercised without needing a repository or the app target.
@Suite("Note.isEmptyAndUntitled")
struct NoteEmptyAndUntitledTests {
    @Test("a freshly created note — default title, empty body — is empty and untitled")
    func freshNoteIsEmptyAndUntitled() {
        let note = Note()
        #expect(note.isEmptyAndUntitled)
    }

    @Test("a note with a body is not empty and untitled, even with the default title")
    func noteWithBodyIsNotEmptyAndUntitled() {
        let note = Note(body: "Buy milk")
        #expect(!note.isEmptyAndUntitled)
    }

    @Test("a note with a custom title is not empty and untitled, even with an empty body")
    func noteWithTitleIsNotEmptyAndUntitled() {
        let note = Note(title: "Grocery List")
        #expect(!note.isEmptyAndUntitled)
    }

    @Test("a body of only whitespace still counts as empty")
    func whitespaceOnlyBodyIsStillEmpty() {
        let note = Note(body: "   \n\t")
        #expect(note.isEmptyAndUntitled)
    }
}
