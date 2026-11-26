import Foundation
import Testing

@testable import PitchsideModel

/// The copies of finished games in the folder Files shows (GameMirror), against
/// temporary folders: real iCloud is not reachable from a test.
@Suite struct MirrorTests {
  let dir = FileManager.default.temporaryDirectory.appending(path: "pitchside-mirror-\(UUID().uuidString)")
  var cloud: GameMirror.Place { GameMirror.Place(.iCloud, folder: dir.appending(path: "cloud/Documents")) }
  var local: GameMirror.Place { GameMirror.Place(.local, folder: dir.appending(path: "local/Documents")) }
  var mirror: GameMirror {
    GameMirror(index: dir.appending(path: "support/mirror.json"), zone: TimeZone(identifier: "America/Chicago")!)
  }

  /// 2026-11-21 14:05 Central.
  static let start = Date(timeIntervalSince1970: 1_795_291_500)

  func entry(_ id: UUID = UUID(), teams: String = "Mossy Stakes v Crooked Crowns", text: String = "1. I -\n",
             at: Date = start) -> GameMirror.Entry {
    GameMirror.Entry(id: id, created: at, teams: teams, text: text)
  }

  func names(_ place: GameMirror.Place) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: place.folder.path)) ?? []).sorted()
  }

  func read(_ place: GameMirror.Place, _ name: String) -> String? {
    try? String(contentsOf: place.folder.appending(path: name), encoding: .utf8)
  }

  @Test func namesAreReadableAndSafe() throws {
    #expect(GameMirror.clean("Birch: the/Batons?") == "Birch the Batons")
    #expect(GameMirror.clean("..hidden") == "hidden")
    #expect(GameMirror.clean("  \n ") == "Team")
    #expect(GameMirror.clean("Kubbkøbing Ås") == "Kubbkøbing Ås")
    #expect(GameMirror.clean(String(repeating: "x", count: 60)).count == 40)
    let r = mirror.sync([entry()], to: local)
    #expect(r.problems.isEmpty)
    #expect(names(local) == ["2026-11-21 1405 Mossy Stakes v Crooked Crowns.txt"])
  }

  @Test func onlyFinishedGamesScoredHereAreMirrored() throws {
    let store = try scratch()
    var done = try sampleGame(store)
    done.status = .finished
    var playing = try sampleGame(store)
    playing.status = .playing
    let opened = Game(origin: .file("x.txt"), status: .finished)
    let entries = GameMirror.Entry.finished([done, playing, opened]) { _ in "text" }
    #expect(entries.map(\.id) == [done.id])
    #expect(entries.first?.teams == "Mossy Stakes v Crooked Crowns")
  }

  @Test func collisionsAreNumberedAndStayPut() throws {
    // Started the same minute: the one that sorts first (by id) keeps the plain name.
    let ids = [UUID(), UUID()].sorted { $0.uuidString < $1.uuidString }
    let first = entry(ids[0], text: "first\n")
    let second = entry(ids[1], text: "second\n")
    mirror.sync([first, second], to: local)
    #expect(names(local) == [
      "2026-11-21 1405 Mossy Stakes v Crooked Crowns 2.txt", "2026-11-21 1405 Mossy Stakes v Crooked Crowns.txt",
    ])
    #expect(read(local, "2026-11-21 1405 Mossy Stakes v Crooked Crowns.txt") == "first\n")
    // Deleting the first does not move the second into its name.
    mirror.sync([second], to: local)
    #expect(names(local) == ["2026-11-21 1405 Mossy Stakes v Crooked Crowns 2.txt"])
  }

  @Test func filesTheAppDidNotWriteAreLeftAlone() throws {
    try FileManager.default.createDirectory(at: local.folder, withIntermediateDirectories: true)
    let theirs = local.folder.appending(path: "2026-11-21 1405 Mossy Stakes v Crooked Crowns.txt")
    try Data("someone else's\n".utf8).write(to: theirs)
    let game = entry()
    mirror.sync([game], to: local)
    #expect(read(local, "2026-11-21 1405 Mossy Stakes v Crooked Crowns.txt") == "someone else's\n")
    #expect(read(local, "2026-11-21 1405 Mossy Stakes v Crooked Crowns 2.txt") == game.text)
    mirror.sync([], to: local)
    #expect(names(local) == ["2026-11-21 1405 Mossy Stakes v Crooked Crowns.txt"])
  }

  @Test func aChangedFileIsRewrittenAndAnUnchangedOneIsNot() throws {
    let id = UUID()
    mirror.sync([entry(id, text: "one\n")], to: local)
    #expect(mirror.sync([entry(id, text: "one\n")], to: local).written.isEmpty)
    let r = mirror.sync([entry(id, text: "two\n")], to: local)
    #expect(r.written.count == 1)
    #expect(read(local, names(local)[0]) == "two\n")
  }

  @Test func aRenamedTeamRenamesTheCopy() throws {
    let id = UUID()
    mirror.sync([entry(id)], to: local)
    let r = mirror.sync([entry(id, teams: "Mossy Stakes v Pine Kings")], to: local)
    #expect(r.moved == ["2026-11-21 1405 Mossy Stakes v Pine Kings.txt"])
    #expect(names(local) == ["2026-11-21 1405 Mossy Stakes v Pine Kings.txt"])
  }

  @Test func deletedInPitchsideIsRemovedAndDeletedInFilesComesBack() throws {
    let keep = entry(teams: "A v B")
    let gone = entry(teams: "C v D")
    mirror.sync([keep, gone], to: local)
    #expect(names(local).count == 2)
    mirror.sync([keep], to: local)
    #expect(names(local) == ["2026-11-21 1405 A v B.txt"])
    // The scorer deletes it in Files: the game is still in Pitchside, so it returns.
    try FileManager.default.removeItem(at: local.folder.appending(path: "2026-11-21 1405 A v B.txt"))
    mirror.sync([keep], to: local)
    #expect(names(local) == ["2026-11-21 1405 A v B.txt"])
  }

  @Test func aDraftAppearsOnlyOnceFinishedAndLeavesWhenReopened() throws {
    let store = try scratch()
    var game = try sampleGame(store)
    game.status = .playing
    mirror.sync(GameMirror.Entry.finished([game]) { _ in "draft\n" }, to: local)
    #expect(names(local).isEmpty)
    game.status = .finished
    mirror.sync(GameMirror.Entry.finished([game]) { _ in "final\n" }, to: local)
    #expect(names(local).count == 1)
    game.status = .playing
    mirror.sync(GameMirror.Entry.finished([game]) { _ in "draft\n" }, to: local)
    #expect(names(local).isEmpty)
  }

  @Test func aFolderThatDisappearsIsMadeAgain() throws {
    mirror.sync([entry()], to: local)
    try FileManager.default.removeItem(at: local.folder)
    let r = mirror.sync([entry()], to: local)
    #expect(r.problems.isEmpty)
    #expect(names(local).count == 1)
  }

  @Test func aBrokenFolderReportsAndKeepsTheRecord() throws {
    // The folder's path is a file: nothing can be written there.
    try FileManager.default.createDirectory(at: dir.appending(path: "local"), withIntermediateDirectories: true)
    try Data().write(to: local.folder)
    let r = mirror.sync([entry()], to: local)
    #expect(!r.problems.isEmpty)
    #expect(mirror.loadIndex()[.local] == nil)
  }

  @Test func movingBetweenICloudAndThePhoneNeitherLosesNorDuplicates() throws {
    let a = entry(teams: "A v B")
    let b = entry(teams: "C v D", at: Self.start.addingTimeInterval(3600))
    // iCloud off: on the phone.
    mirror.sync([a, b], to: local)
    #expect(names(local).count == 2)
    // iCloud on: the copies move to iCloud and leave the phone's folder.
    mirror.sync([a, b], to: cloud, retiring: [local])
    #expect(names(cloud) == ["2026-11-21 1405 A v B.txt", "2026-11-21 1505 C v D.txt"])
    #expect(names(local).isEmpty)
    // iCloud off again (the container's files are no longer on this phone): back on it.
    try FileManager.default.removeItem(at: cloud.folder)
    mirror.sync([a, b], to: local)
    #expect(names(local).count == 2)
    // And on again, with the cloud's copies still there: no "2" duplicates.
    try FileManager.default.createDirectory(at: cloud.folder, withIntermediateDirectories: true)
    for n in ["2026-11-21 1405 A v B.txt", "2026-11-21 1505 C v D.txt"] {
      try Data((n.contains("A v B") ? a : b).text.utf8).write(to: cloud.folder.appending(path: n))
    }
    mirror.sync([a, b], to: cloud, retiring: [local])
    #expect(names(cloud) == ["2026-11-21 1405 A v B.txt", "2026-11-21 1505 C v D.txt"])
    #expect(names(local).isEmpty)
  }

  @Test func aSlowOrFailingMirrorNeverHoldsUpTheJournal() throws {
    let store = try scratch()
    let game = try sampleGame(store)
    try store.save(game)
    let log = try store.log(game.id)
    let gate = DispatchSemaphore(value: 0)
    let service = GameMirrorService(
      mirror: mirror, local: dir.appending(path: "nowhere"),
      cloud: {
        gate.wait()  // iCloud taking its time
        return URL(fileURLWithPath: "/dev/null/Documents")  // and then failing
      })
    let before = Date()
    service.update([entry()])
    service.update([entry()])
    try log.append(kind: GameEvent.Kind.start, capture: Capture())
    try log.append(kind: "placeholder", capture: Capture())
    #expect(Date().timeIntervalSince(before) < 1)
    #expect(try store.log(game.id).events.count == 2)
    gate.signal()
    gate.signal()
    service.wait()
  }
}
