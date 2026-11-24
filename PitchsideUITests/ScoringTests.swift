import XCTest

@MainActor
final class ScoringTests: XCTestCase {
  let app = XCUIApplication()

  override func setUp() { continueAfterFailure = false }

  func launch(_ screen: String, after events: Int) {
    app.launchArguments = [
      "-PitchsideDemo", "-PitchsideScreen", screen, "-PitchsideDemoAt", "\(events)",
    ]
    app.launch()
  }

  func tap(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
    let button = app.buttons.matching(
      NSPredicate(format: "label ==[c] %@ OR identifier == %@", label, label)
    ).firstMatch
    XCTAssertTrue(
      button.exists || button.waitForExistence(timeout: 4),
      "Missing \(label)\n\(app.debugDescription)", file: file, line: line)
    button.tap()
  }

  func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Read the rendered rough at the side of the pitch to identify the actual appearance.
  func darkPitch() -> Bool {
    guard let image = app.screenshot().image.cgImage,
      let sample = image.cropping(to: CGRect(x: 4, y: image.height / 2, width: 1, height: 1))
    else { return false }
    var pixel = [UInt8](repeating: 0, count: 4)
    return pixel.withUnsafeMutableBytes { bytes in
      guard
        let context = CGContext(
          data: bytes.baseAddress, width: 1, height: 1,
          bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      return bytes[1] < 96
    }
  }

  func spot(_ x: Double, _ y: Double) {
    let pitch = app.descendants(matching: .any).matching(identifier: "pitch").firstMatch
    let frame = pitch.frame
    let scale = min((frame.width - 68) / 5, (frame.height - 68) / 8)
    let point = CGVector(dx: frame.midX + (x - 2.5) * scale, dy: frame.midY + (4 - y) * scale)
    app.coordinate(withNormalizedOffset: .zero).withOffset(point).tap()
  }

  func testWorkedGameAndViews() {
    launch("scorer", after: 0)

    // Establish the first four turns of the design through the same controls as turn five.
    tap("bB1")
    tap("1 down")
    tap("bB3")
    tap("1 down")
    spot(1.2, 1.6)
    spot(3.6, 2.9)
    tap("fA0")
    tap("fA1")
    tap("2 down")
    tap("bA0")
    tap("1 down")
    tap("bA1")
    tap("1 down")
    tap("Miss")
    spot(0.4, 5.5)
    spot(2.2, 4.6)
    spot(2.8, 4.9)
    spot(4.1, 6.2)
    tap("fB1")
    tap("fB2")
    tap("2 down")
    tap("fB0")
    tap("1 down")
    tap("fB0")
    tap("1 down")
    tap("Miss")
    tap("Miss")
    tap("Miss")
    spot(0.7, 3.2)
    spot(1.9, 2.8)
    tap("Change who throws")
    tap("Lee")
    spot(3.4, 2.7)
    spot(4.4, 3.5)
    tap("fA0")
    tap("1 down")
    tap("fA0")
    tap("1 down")
    tap("fA1")
    tap("1 down")
    tap("Miss")
    tap("Miss")
    tap("Miss")
    shot("Scorer-light")
    spot(1.4, 5.6)
    shot("Inkast-light")
    spot(2.3, 5.2)
    spot(2.6, 5.7)
    tap("fB0")
    tap("fB1")
    tap("fB2")
    shot("Baton-marked-light")
    tap("3 down")
    spot(3.9, 2.5)
    tap("bB0")
    shot("Thrown-from-light")
    tap("1 down")
    tap("Change who throws")
    shot("Who-threw-light")
    tap("Ole")
    tap("Change view")
    shot("Sideline-light")
    tap("Change view")
    tap("bB0")
    tap("1 down")
    tap("bB0")
    tap("1 down")
    tap("Change view")  // behind A again
    spot(2.7, 0.12)
    shot("King-shot-light")
    tap("Miss")
    tap("King down")
    XCTAssertTrue(app.staticTexts["Wobbly Towers beat Birch Batons"].waitForExistence(timeout: 5))
    tap("Undo last event")
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label ==[c] 'King down'")).firstMatch
        .waitForExistence(timeout: 5))
    tap("King down")
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label ==[c] 'Undo last event'")).firstMatch
        .waitForExistence(timeout: 5))
    let notation = app.staticTexts["The game file"].value as? String ?? ""
    XCTAssertTrue(notation.contains("5. k:3I A k:3F d:B o:B k:B d:= o:K"))
    XCTAssertTrue(notation.contains(#"[Scored by "Kubb: Pitchside "#))
    let export = XCTAttachment(string: notation)
    export.name = "Scored-game"
    export.lifetime = .keepAlways
    add(export)
  }

  func testEarlierEdit() {
    launch("scorer", after: 33)
    tap("More")
    tap("Timeline")
    let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Turn 4,'")).firstMatch
    row.tap()
    tap("Baton 4 · a miss")
    tap("1 field")
    let impact = app.staticTexts.matching(
      NSPredicate(format: "label ==[c] 'This changes what came after'")
    ).firstMatch
    XCTAssertTrue(impact.waitForExistence(timeout: 4))
    shot("Timeline-edit-light")
    tap("Keep original")
    tap("Baton 4 · a miss")
    tap("1 field")
    tap("Change, review turn 5")
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Needs a look'")).firstMatch.exists)
    tap("Back to Scoring")
    XCTAssertTrue(app.buttons["Change view"].exists)
  }

  /// The screenshot command runs this journey with the simulator itself in dark mode.
  func testMarkedPitchInSystemAppearance() {
    launch("scorer", after: 31)
    tap("fB0")
    tap("fB1")
    tap("fB2")
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label ==[c] '3 down'")).firstMatch.exists)
    shot(darkPitch() ? "Scorer-dark" : "Marked-pitch")
  }

  func testRareInkastAndBatonEvents() {
    launch("scorer", after: 28)
    tap("More")
    tap("Failed rescue")
    spot(2.4, 5.5)
    tap("More")
    tap("King hit early")
    XCTAssertTrue(app.staticTexts["Birch Batons beat Wobbly Towers"].waitForExistence(timeout: 4))
    let file = app.staticTexts["The game file"]
    let inkast = (file.value as? String)?.components(separatedBy: "\n").first {
      $0.hasPrefix("5. ")
    }
    XCTAssertTrue(inkast?.contains("Y") == true)
    XCTAssertTrue(inkast?.contains("E") == true)
    tap("Undo last event")
    tap("Later")
    tap("More")
    tap("Illegal throw")
    tap("More")
    tap("Game called")
    tap("Wobbly Towers")
    XCTAssertTrue(app.staticTexts["Wobbly Towers beat Birch Batons"].waitForExistence(timeout: 4))
    let called = (file.value as? String)?.components(separatedBy: "\n").first {
      $0.hasPrefix("5. ")
    }
    XCTAssertTrue(called?.contains(":Z") == true)
    XCTAssertTrue(called?.split(separator: " ").contains("W") == true)
  }

  func testRethrowPunishmentAndDeferredPlacement() {
    launch("scorer", after: 28)
    tap("Out")
    tap("Later")
    tap("Out again")
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label ==[c] 'Place it later'")).firstMatch.exists)
    tap("Place it later")
    XCTAssertTrue(app.buttons["bB0"].exists)
    let unknown = app.buttons.matching(NSPredicate(format: "label ==[c] 'Count field kubbs'")).firstMatch
    XCTAssertTrue(unknown.waitForExistence(timeout: 3), app.debugDescription)
    tap("Miss")
    for _ in 0..<5 { tap("Miss") }
    tap("Place 3")
    spot(1.4, 5.5)
    spot(2.4, 6.1)
    spot(3.4, 6.2)
    XCTAssertFalse(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Place '")).firstMatch.exists)
    tap("More")
    tap("Timeline")
    XCTAssertTrue(
      app.buttons.matching(
        NSPredicate(format: "label BEGINSWITH 'Turn 5,' AND label CONTAINS 'RP'")
      ).firstMatch.exists)
  }

  func testCountsAndObservedAdvantageWarning() {
    launch("scorer", after: 28)
    tap("More")
    tap("What to record")
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Where kubbs stand'")).firstMatch
      .tap()
    tap("Done")
    tap("All 3 in")
    tap("Count field kubbs")
    tap("Count field kubbs")
    tap("Count field kubbs")
    tap("3 down")
    tap("More")
    tap("Advantage line")
    tap("Baseline")
    tap("Read engine warning")
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'file follows the count'"))
        .firstMatch.exists)
    tap("Done")
    tap("Miss")
  }

  /// Starts in setup, picks the opening, then scores every throw through the live controls.
  func testResumeAnOlderUnfinishedGame() {
    launch("thisgame", after: 28)
    let start = app.buttons.matching(NSPredicate(format: "label ==[c] 'Start scoring'")).firstMatch
    for _ in 0..<5 where !start.isHittable { app.swipeUp() }
    tap("Start scoring")
    tap("More")
    tap("Home")
    let older = app.buttons["Carry on, Wobbly Towers versus Birch Batons"]
    XCTAssertTrue(older.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Carry on, Mossy Stakes versus Crooked Crowns"].exists)
    for _ in 0..<4 where !older.isHittable { app.swipeUp() }
    older.tap()
    XCTAssertTrue(app.buttons["Change view"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label ==[c] 'Later'")).firstMatch.exists)
  }

  func testPrintableScoreSheet() {
    launch("sheet", after: 0)
    let export = app.buttons.matching(NSPredicate(format: "label ==[c] 'Score sheet PDF'")).firstMatch
    for _ in 0..<6 where !export.isHittable { app.swipeUp() }
    tap("Score sheet PDF")
    XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 8), app.debugDescription)
    shot("Printable-score-sheet")
  }

  func testWholeGame() {
    launch("thisgame", after: 0)
    tap("Six batons")
    let start = app.buttons.matching(NSPredicate(format: "label ==[c] 'Start scoring'")).firstMatch
    for _ in 0..<5 where !start.isHittable { app.swipeUp() }
    tap("Start scoring")
    XCTAssertTrue(app.buttons["bB0"].waitForExistence(timeout: 5))
    for _ in 0..<5 {
      tap("bB0")
      tap("1 down")
    }
    tap("King down")
    XCTAssertTrue(app.staticTexts["Mossy Stakes beat Crooked Crowns"].waitForExistence(timeout: 5))
  }
}
