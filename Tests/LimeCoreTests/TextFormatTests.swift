import Testing
@testable import LimeCore

@Suite struct SubtitleTests {
    let srt = "1\n00:00:01,000 --> 00:00:02,500\nHello\n\n2\n00:00:03,000 --> 00:00:04,000\n<i>World</i>\n"

    @Test func srtToVtt() throws {
        let vtt = try TextFormats.subtitles(srt, to: "vtt")
        #expect(vtt.hasPrefix("WEBVTT\n\n00:00:01.000 --> 00:00:02.500\nHello"))
    }

    @Test func vttToSrtPadsShortTimestampsAndDropsSettings() throws {
        let vtt = "WEBVTT\n\nNOTE made by hand\n\nintro\n01:02.5 --> 01:04.000 align:start\nHi there\n"
        let result = try TextFormats.subtitles(vtt, to: "srt")
        #expect(result == "1\n00:01:02,500 --> 00:01:04,000\nHi there\n")
    }

    @Test func toPlainTextStripsTags() throws {
        #expect(try TextFormats.subtitles(srt, to: "txt") == "Hello\nWorld\n")
    }
}

@Suite struct TableTests {
    @Test func csvWithQuotesAndCommasRoundTrips() throws {
        let csv = "name,note\n\"Smith, J\",\"said \"\"hi\"\"\"\nAna,ok\n"
        let rows = TextFormats.parseCSV(csv)
        #expect(rows == [["name", "note"], ["Smith, J", "said \"hi\""], ["Ana", "ok"]])
        let tsv = try TextFormats.table(csv, from: "csv", to: "tsv")
        #expect(tsv == "name\tnote\nSmith, J\tsaid \"hi\"\nAna\tok\n")
        #expect(try TextFormats.table(tsv, from: "tsv", to: "csv") == csv)
    }
}
