import Foundation
import Testing
import TrimmyCore

struct PathQuotingTests {
    private let cleaner = TextCleaner()

    @Test(arguments: [
        "My New File",
        "My New File.txt",
        "src/My New File",
        "src/My New File.txt",
        "a/b file.txt",
        "My Project/src",
    ])
    func `quotes existing relative files including extensionless names`(name: String) throws {
        let fixture = try PathFixture()
        defer { fixture.remove() }
        try fixture.create(name)
        let path = fixture.relativePath(name)
        #expect(self.cleaner.quotePathWithSpaces(path) == "\"\(path)\"")
    }

    @Test
    func `quotes existing absolute directories and trims surrounding whitespace`() throws {
        let fixture = try PathFixture()
        defer { fixture.remove() }
        let path = try fixture.create("My Documents/project", directory: true).path
        #expect(self.cleaner.quotePathWithSpaces(path) == "\"\(path)\"")
        #expect(self.cleaner.quotePathWithSpaces("  \(path)  \n") == "\"\(path)\"")
    }

    @Test(arguments: ["./", "../"])
    func `resolves explicit relative paths without changing working directory`(prefix: String) throws {
        let fixture = try PathFixture()
        defer { fixture.remove() }
        try fixture.create("My Project/src")
        let parent = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).lastPathComponent
        let path = prefix + (prefix == "../" ? parent + "/" : "") + fixture.relativePath("My Project/src")
        #expect(self.cleaner.quotePathWithSpaces(path) == "\"\(path)\"")
    }

    @Test
    func `expands home only to check existence and preserves shell expansion`() throws {
        let fixture = try PathFixture(parent: FileManager.default.homeDirectoryForCurrentUser)
        defer { fixture.remove() }
        try fixture.create("My Documents/file.txt")
        let path = "~/" + fixture.relativePath("My Documents/file.txt")
        let expected = "~/\"" + String(path.dropFirst(2)) + "\""
        #expect(self.cleaner.quotePathWithSpaces(path) == expected)
        #expect(self.cleaner.quotePathWithSpaces(path + " missing") == nil)
    }

    @Test
    func `does not quote missing absolute or relative paths`() throws {
        let fixture = try PathFixture()
        defer { fixture.remove() }
        let path = try fixture.create("My New File").path
        try FileManager.default.removeItem(atPath: path)
        #expect(self.cleaner.quotePathWithSpaces(path) == nil)
        #expect(self.cleaner.quotePathWithSpaces(fixture.relativePath("My New File")) == nil)
        #expect(self.cleaner.quotePathWithSpaces("./" + fixture.relativePath("My New File")) == nil)
    }

    @Test
    func `path quoting preserves shell metacharacters literally`() throws {
        let fixture = try PathFixture()
        defer { fixture.remove() }
        let name = #"$TRIMMY_FIXTURE `printf changed` \ "file".txt"#
        let path = try fixture.create(name).path
        let expected = "\"" + fixture.root.path + #"/\$TRIMMY_FIXTURE \`printf changed\` \\ \"file\".txt""#
        #expect(self.cleaner.quotePathWithSpaces(path) == expected)
    }

    @Test
    func `does not re quote paths or quote paths without spaces`() throws {
        let fixture = try PathFixture()
        defer { fixture.remove() }
        let path = try fixture.create("My New File").path
        #expect(self.cleaner.quotePathWithSpaces("\"\(path)\"") == nil)
        #expect(self.cleaner.quotePathWithSpaces("'\(path)'") == nil)
        #expect(try self.cleaner.quotePathWithSpaces(fixture.create("file").path) == nil)
    }

    @Test(arguments: [Aggressiveness.low, .normal, .high])
    func `transform quotes only existing paths at every aggressiveness`(aggressiveness: Aggressiveness) throws {
        let fixture = try PathFixture()
        defer { fixture.remove() }
        try fixture.create("src/My New File")
        let path = fixture.relativePath("src/My New File")
        let config = TrimConfig(aggressiveness: aggressiveness, preserveBlankLines: false, removeBoxDrawing: false)
        let quoted = self.cleaner.transform(path, config: config)
        #expect(quoted.trimmed == "\"\(path)\"")
        #expect(quoted.wasTransformed)
        for text in [
            "and/or this needs spaces", "A/B testing is useful", "i/o matters a lot",
            "input/output needs spaces", "folder/sub folder/file.txt", path + " missing",
            "just some text with spaces", "See /Users/anton/My Documents for details",
            "cd /Users/anton/My Documents", "/usr/bin/ls -la /some/path", "/skill:cmd args",
        ] {
            let result = self.cleaner.transform(text, config: config)
            #expect(result.trimmed == text)
            #expect(!result.wasTransformed)
        }
    }

    @Test(arguments: [
        "https://example.com/path with spaces", "/tmp/My Files\n/second/path",
        "/tmp/My Files\r/second/path", "", "   ",
    ])
    func `does not quote URLs multiline or empty text`(text: String) {
        #expect(self.cleaner.quotePathWithSpaces(text) == nil)
    }
}

private struct PathFixture {
    let root: URL

    init(parent: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws {
        self.root = parent.appendingPathComponent("trimmypathtest" + UUID().uuidString.filter(\.isLetter))
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    @discardableResult
    func create(_ name: String, directory: Bool = false) throws -> URL {
        let path = self.root.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: directory ? path : path.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !directory {
            try Data().write(to: path)
        }
        return path
    }

    func relativePath(_ name: String) -> String {
        self.root.lastPathComponent + "/" + name
    }

    func remove() {
        try? FileManager.default.removeItem(at: self.root)
    }
}
