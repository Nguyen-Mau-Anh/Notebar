import AppKit
import Testing
@testable import NotebarStore

/// Covers `NoteListMarkers` — spec §6.2d's list-marker bookkeeping — for
/// every piece of it that doesn't need a live `NSTextView`: marker text
/// generation, detecting an existing marker, diffing/renumbering a run, and
/// the `body_plain` marker-stripping `NoteRTF.plainText` relies on. The
/// `NSTextView`-only glue (caret handling, `typingAttributes`, the
/// `shouldChangeTextIn` Return-key interception) lives in the app target's
/// `NoteListEditing` and isn't exercised here — it has no meaning without a
/// live text view and first responder.
@Suite("NoteListMarkers")
struct NoteListMarkersTests {
    private var orderedList: NSTextList { NSTextList(markerFormat: .decimal, options: 0) }
    private var bulletedList: NSTextList { NSTextList(markerFormat: .disc, options: 0) }

    private func orderedStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.textLists = [orderedList]
        return style
    }

    private func bulletedStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.textLists = [bulletedList]
        return style
    }

    // MARK: - markerText

    @Test("an ordered list's marker text is the item number, a period, and a tab")
    func orderedMarkerText() {
        #expect(NoteListMarkers.markerText(for: 1, list: orderedList) == "1.\t")
        #expect(NoteListMarkers.markerText(for: 2, list: orderedList) == "2.\t")
        #expect(NoteListMarkers.markerText(for: 10, list: orderedList) == "10.\t")
    }

    @Test("a bulleted list's marker text never depends on item number")
    func bulletedMarkerTextIsConstant() {
        let first = NoteListMarkers.markerText(for: 1, list: bulletedList)
        let fifth = NoteListMarkers.markerText(for: 5, list: bulletedList)
        #expect(first == fifth)
        #expect(first.hasSuffix("\t"))
    }

    // MARK: - isListParagraph

    @Test("a paragraph style with a text list is a list paragraph")
    func styleWithTextListIsListParagraph() {
        #expect(NoteListMarkers.isListParagraph(orderedStyle()))
        #expect(NoteListMarkers.isListParagraph(bulletedStyle()))
    }

    @Test("a plain paragraph style, or none at all, is not a list paragraph")
    func plainStyleIsNotListParagraph() {
        #expect(!NoteListMarkers.isListParagraph(NSParagraphStyle.default))
        #expect(!NoteListMarkers.isListParagraph(nil))
    }

    // MARK: - existingMarkerRange

    @Test("finds a marker at the start of a populated list paragraph")
    func findsMarkerBeforeContent() {
        let text = "1.\tBuy milk" as NSString
        let range = NoteListMarkers.existingMarkerRange(in: text, paragraphRange: NSRange(location: 0, length: text.length))
        #expect(range == NSRange(location: 0, length: 3))
    }

    @Test("finds a marker on an otherwise-empty list paragraph")
    func findsMarkerOnEmptyItem() {
        let text = "1.\t" as NSString
        let range = NoteListMarkers.existingMarkerRange(in: text, paragraphRange: NSRange(location: 0, length: text.length))
        #expect(range == NSRange(location: 0, length: 3))
    }

    @Test("no marker found in a paragraph with no tab at all")
    func noMarkerWithoutTab() {
        let text = "Buy milk" as NSString
        let range = NoteListMarkers.existingMarkerRange(in: text, paragraphRange: NSRange(location: 0, length: text.length))
        #expect(range == nil)
    }

    @Test("no marker found in a zero-length paragraph")
    func noMarkerInEmptyParagraph() {
        let text = "" as NSString
        let range = NoteListMarkers.existingMarkerRange(in: text, paragraphRange: NSRange(location: 0, length: 0))
        #expect(range == nil)
    }

    @Test("finds the marker of a second paragraph, not the first paragraph's")
    func findsMarkerWithinLaterParagraph() {
        let text = "1.\tFirst\n2.\tSecond" as NSString
        let secondParagraphRange = NSRange(location: 9, length: text.length - 9)
        let range = NoteListMarkers.existingMarkerRange(in: text, paragraphRange: secondParagraphRange)
        #expect(range == NSRange(location: 9, length: 3))
    }

    // MARK: - renumbering(for:list:)

    @Test("an already-correct run needs no changes")
    func correctRunNeedsNoChanges() {
        let changes = NoteListMarkers.renumbering(for: ["1.\t", "2.\t", "3.\t"], list: orderedList)
        #expect(changes.isEmpty)
    }

    @Test("a gap left by a deleted middle item is closed")
    func closesGapFromDeletedItem() {
        // Item 2 was deleted: the run now reads 1, 3, 4 and must become 1, 2, 3.
        let changes = NoteListMarkers.renumbering(for: ["1.\t", "3.\t", "4.\t"], list: orderedList)
        #expect(changes == [1: "2.\t", 2: "3.\t"])
    }

    @Test("a duplicate number from an inserted item is fixed")
    func fixesDuplicateFromInsertedItem() {
        // A new item was inserted after item 1 without renumbering yet: 1, 2, 2, 3.
        let changes = NoteListMarkers.renumbering(for: ["1.\t", "2.\t", "2.\t", "3.\t"], list: orderedList)
        #expect(changes == [2: "3.\t", 3: "4.\t"])
    }

    @Test("a missing marker (empty string) is always replaced")
    func missingMarkerIsReplaced() {
        let changes = NoteListMarkers.renumbering(for: ["1.\t", ""], list: orderedList)
        #expect(changes == [1: "2.\t"])
    }

    // MARK: - orderedListRun

    private func attributedList(_ paragraphs: [(String, NSParagraphStyle?)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            let separator = index == paragraphs.count - 1 ? "" : "\n"
            var attributes: [NSAttributedString.Key: Any] = [:]
            if let style = paragraph.1 { attributes[.paragraphStyle] = style }
            result.append(NSAttributedString(string: paragraph.0 + separator, attributes: attributes))
        }
        return result
    }

    @Test("a single ordered-list paragraph is its own run")
    func singleParagraphRun() {
        let text = attributedList([("1.\tOnly item", orderedStyle())])
        let run = NoteListMarkers.orderedListRun(containing: 0, in: text)
        #expect(run?.count == 1)
    }

    @Test("a contiguous ordered run is returned in full regardless of which item location is queried")
    func fullContiguousRun() {
        let text = attributedList([
            ("1.\tFirst", orderedStyle()),
            ("2.\tSecond", orderedStyle()),
            ("3.\tThird", orderedStyle()),
        ])
        let fromMiddle = NoteListMarkers.orderedListRun(containing: text.string.count / 2, in: text)
        #expect(fromMiddle?.count == 3)
        #expect(fromMiddle?.first?.location == 0)
    }

    @Test("a run stops at a non-list paragraph")
    func runStopsAtPlainParagraph() {
        let text = attributedList([
            ("1.\tFirst", orderedStyle()),
            ("2.\tSecond", orderedStyle()),
            ("Just a plain paragraph", nil),
            ("1.\tSeparate list", orderedStyle()),
        ])
        let nsString = text.string as NSString
        let secondItemLocation = nsString.range(of: "Second").location
        let run = NoteListMarkers.orderedListRun(containing: secondItemLocation, in: text)
        #expect(run?.count == 2)

        let plainLocation = nsString.range(of: "plain").location
        #expect(NoteListMarkers.orderedListRun(containing: plainLocation, in: text) == nil)
    }

    @Test("a run stops at a bulleted paragraph — bulleted lists never renumber")
    func runStopsAtBulletedParagraph() {
        let text = attributedList([
            ("1.\tFirst", orderedStyle()),
            ("•\tBulleted", bulletedStyle()),
        ])
        let run = NoteListMarkers.orderedListRun(containing: 0, in: text)
        #expect(run?.count == 1)
    }

    @Test("a plain paragraph is never part of an ordered run")
    func plainParagraphHasNoRun() {
        let text = attributedList([("Just text", nil)])
        #expect(NoteListMarkers.orderedListRun(containing: 0, in: text) == nil)
    }

    // MARK: - renumber(run:list:in:)

    @Test("renumbering a gapped run rewrites only the wrong markers and reports a change")
    func renumberRewritesGap() {
        let text = NSMutableAttributedString(string: "1.\tFirst\n3.\tSecond\n4.\tThird")
        let ranges = [
            NSRange(location: 0, length: 9),
            NSRange(location: 9, length: 10),
            NSRange(location: 19, length: 8),
        ]
        let changed = NoteListMarkers.renumber(run: ranges, list: orderedList, in: text)
        #expect(changed)
        #expect(text.string == "1.\tFirst\n2.\tSecond\n3.\tThird")
    }

    @Test("renumbering an already-correct run makes no edits and reports no change")
    func renumberNoOpOnCorrectRun() {
        let text = NSMutableAttributedString(string: "1.\tFirst\n2.\tSecond")
        let ranges = [
            NSRange(location: 0, length: 9),
            NSRange(location: 9, length: 9),
        ]
        let changed = NoteListMarkers.renumber(run: ranges, list: orderedList, in: text)
        #expect(!changed)
        #expect(text.string == "1.\tFirst\n2.\tSecond")
    }

    @Test("renumbering carries over the marker's existing attributes")
    func renumberPreservesAttributes() {
        let font = NSFont.systemFont(ofSize: 42)
        let text = NSMutableAttributedString(string: "3.\tOnly item", attributes: [.font: font])
        let ranges = [NSRange(location: 0, length: text.length)]
        _ = NoteListMarkers.renumber(run: ranges, list: orderedList, in: text)
        #expect(text.string == "1.\tOnly item")
        let attributeAtStart = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(attributeAtStart == font)
    }

    // MARK: - strippingMarkers (body_plain projection)

    @Test("a numbered item's marker is excluded from the plain-text projection")
    func stripsOrderedMarker() {
        let text = NSAttributedString(string: "1.\tBuy milk", attributes: [.paragraphStyle: orderedStyle()])
        #expect(NoteListMarkers.strippingMarkers(from: text) == "Buy milk")
    }

    @Test("a bulleted item's marker is excluded from the plain-text projection")
    func stripsBulletedMarker() {
        let text = NSAttributedString(string: "•\tBuy milk", attributes: [.paragraphStyle: bulletedStyle()])
        #expect(NoteListMarkers.strippingMarkers(from: text) == "Buy milk")
    }

    @Test("markers are stripped from every paragraph in a multi-item list, other text is untouched")
    func stripsMarkersAcrossMultipleParagraphs() {
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "1.\tFirst\n", attributes: [.paragraphStyle: orderedStyle()]))
        text.append(NSAttributedString(string: "2.\tSecond\n", attributes: [.paragraphStyle: orderedStyle()]))
        text.append(NSAttributedString(string: "Not a list item", attributes: [:]))
        #expect(NoteListMarkers.strippingMarkers(from: text) == "First\nSecond\nNot a list item")
    }

    @Test("plain text with no list paragraphs at all is returned unchanged")
    func plainTextUnaffectedByStripping() {
        let text = NSAttributedString(string: "Just an ordinary note")
        #expect(NoteListMarkers.strippingMarkers(from: text) == "Just an ordinary note")
    }

    @Test("an empty attributed string strips to an empty string")
    func emptyStringStripsToEmpty() {
        #expect(NoteListMarkers.strippingMarkers(from: NSAttributedString(string: "")) == "")
    }

    @Test("a list paragraph with no marker inserted yet strips to nothing lost")
    func listParagraphWithoutMarkerYetIsUnaffected() {
        // The instant between applying the paragraph style and inserting
        // the marker text — no tab exists yet, so there's nothing to strip.
        let text = NSAttributedString(string: "Buy milk", attributes: [.paragraphStyle: orderedStyle()])
        #expect(NoteListMarkers.strippingMarkers(from: text) == "Buy milk")
    }
}
