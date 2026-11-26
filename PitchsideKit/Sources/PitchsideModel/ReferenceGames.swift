import CryptoKit
import Foundation
import Notation

/// One of the real games Pitchside ships to get a scorer started: a file from the Planet
/// Kubb archive (pk-kubb-score `games/` at the pinned edition tag, unmodified), and why it
/// was chosen. Read only. It is never saved in the GameStore, so it never reaches the
/// journal, the roster or the cross-game Stats tab.
public struct ReferenceGame: Sendable, Hashable, Identifiable {
  /// The archive's file name, e.g. `2012-07-15-us-nationals-...-game-2.txt`.
  public let file: String
  /// Why it is in the collection, one line, shown under it.
  public let why: String
  /// The file's text, exactly as the archive has it.
  public let text: String

  /// The file in the archive, at the edition Pitchside's copy came from. (The wiki page
  /// its `Source` header names is no longer served.)
  public var archiveURL: URL {
    URL(string: "https://github.com/Planet-Kubb/pk-kubb-score/blob/\(NotationReader.edition)/games/\(file)")!
  }

  /// The same id on every launch, from the file name, so a pushed screen survives a
  /// refresh. Distinct from any UUID() a saved game gets.
  public var id: UUID { Self.id(for: file) }

  public static func id(for file: String) -> UUID {
    var bytes = Array(SHA256.hash(data: Data("pitchside.reference/\(file)".utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50  // a name-based UUID (version 5 layout)
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                       bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
  }
}

/// The collection, in CATALOG.tsv's order.
public enum ReferenceGames {
  /// The folder in this package's bundle (scripts/vendor-notation.sh fills it).
  public static var folder: URL? { Bundle.module.url(forResource: "ReferenceGames", withExtension: nil) }

  /// Every listed game whose file is in the bundle.
  public static func all() -> [ReferenceGame] {
    guard let folder, let catalog = try? String(contentsOf: folder.appending(path: "CATALOG.tsv"), encoding: .utf8)
    else { return [] }
    return catalog.split(separator: "\n").compactMap { line in
      guard !line.hasPrefix("#") else { return nil }
      let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
      guard parts.count == 2,
        let text = try? String(contentsOf: folder.appending(path: parts[0]), encoding: .utf8)
      else { return nil }
      return ReferenceGame(file: parts[0], why: parts[1], text: text)
    }
  }

  /// The game as Pitchside shows it: finished, read only, teams and options from the file.
  public static func game(_ reference: ReferenceGame, read: GameRead) -> Game {
    GameStore.game(from: read, origin: .reference(reference.file), id: reference.id)
  }

  /// Where the bundled games came from and on what terms, for the credit on each sheet.
  /// pk-kubb-score has no LICENSE file; the terms are the Planet Kubb blog's 2012 statement
  /// (pk-kubb-score `sources/planetkubb.com/posts/2012-07-08-planet-kubb-scoring-system-beta.html`).
  public static let terms =
    "From the Planet Kubb wiki archive (wiki.planetkubb.com, 2011 to 2015), kept in pk-kubb-score. Planet Kubb published its content under Creative Commons BY-SA. The file is shown unmodified."
}

/// The credit a reference game's headers give: who scored it, where it was published.
public struct ReferenceCredit: Sendable, Hashable {
  public var event: String?
  public var date: String?
  public var location: String?
  public var scoredBy: String?
  public var enteredBy: String?
  public var source: URL?
  public var video: URL?
  public var videoOffset: String?

  public init(headers: [String: String]) {
    func value(_ key: String) -> String? {
      headers[key].map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
    }
    event = value("Event")
    date = value("Start").map { String($0.prefix(10)) } ?? value("Event date")
    location = value("Location")
    scoredBy = value("Scored by")
    enteredBy = value("Entered by")
    source = value("Source").flatMap(URL.init(string:))
    video = value("Video").flatMap(URL.init(string:))
    videoOffset = value("Video offset")
  }
}
