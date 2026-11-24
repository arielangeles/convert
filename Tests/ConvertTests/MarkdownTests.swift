import AppKit
import Testing
@testable import Convert

@Suite struct MarkdownTests {
    private func font(_ s: NSAttributedString, at i: Int) -> NSFont? {
        s.attribute(.font, at: i, effectiveRange: nil) as? NSFont
    }

    private func traits(_ s: NSAttributedString, at i: Int) -> NSFontDescriptor.SymbolicTraits {
        font(s, at: i)?.fontDescriptor.symbolicTraits ?? []
    }

    @Test func headingsAreBoldAndSizedByLevel() {
        let s = Markdown.render("# Title\n### Sub")
        #expect(s.string == "Title\nSub\n")
        #expect(font(s, at: 0)?.pointSize == 24)
        #expect(traits(s, at: 0).contains(.bold))
        #expect(font(s, at: 6)?.pointSize == 17)
    }

    @Test func bulletsGetADot() {
        #expect(Markdown.render("- one\n* two\n+ three").string == "•  one\n•  two\n•  three\n")
    }

    @Test func codeFencesAreMonospacedAndFencesRemoved() {
        let s = Markdown.render("```\nlet x = 1\n```\nafter")
        #expect(s.string == "let x = 1\nafter\n")
        #expect(traits(s, at: 0).contains(.monoSpace))
        #expect(!traits(s, at: 10).contains(.monoSpace))
    }

    @Test func inlineBoldItalicAndCode() {
        let s = Markdown.render("**bold** *it* `code`")
        #expect(s.string == "bold it code\n")
        #expect(traits(s, at: 0).contains(.bold))
        #expect(traits(s, at: 5).contains(.italic))
        #expect(traits(s, at: 8).contains(.monoSpace))
    }

    @Test func quotesAreItalic() {
        let s = Markdown.render("> wise words")
        #expect(s.string == "wise words\n")
        #expect(traits(s, at: 0).contains(.italic))
    }
}
