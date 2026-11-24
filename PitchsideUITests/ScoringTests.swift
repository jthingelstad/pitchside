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

  /// Exercise real two-finger input, one-finger pan, and physical taps on neighbours
  /// that share a recorded cell. The navigation gestures must never score an event.
  func testPinchPanAndScoreADrilledCluster() {
    launch("scorer", after: 28)
    let pitch = app.descendants(matching: .any).matching(identifier: "pitch").firstMatch
    let overview = pitch.frame
    pitch.pinch(withScale: 2.5, velocity: 2)
    XCTAssertTrue(app.buttons["Fit whole pitch"].exists)
    tap("Fit whole pitch")
    // All three placements are still due after the pinch.
    spot(2.24, 4.33)
    spot(2.31, 4.48)
    spot(2.43, 4.42)
    let field = (0..<3).map { app.buttons["fB" + String($0)] }
    XCTAssertTrue(field.allSatisfy { $0.exists && $0.label.contains("of 3 in this cell") })
    func separation() -> CGFloat {
      hypot(field[0].frame.midX - field[1].frame.midX, field[0].frame.midY - field[1].frame.midY)
    }
    func touch(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
      app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }
    for orientation in ["Behind Team A", "Sideline", "Behind Team B"] {
      XCTAssertEqual(app.buttons["Change view"].value as? String, orientation)
      let before = separation()
      pitch.pinch(withScale: 2.5, velocity: 2)
      XCTAssertGreaterThan(separation(), before * 1.3)
      let x = field[0].frame.midX
      touch(overview.midX, overview.midY).press(forDuration: 0.08, thenDragTo: touch(overview.midX + 40, overview.midY + 20))
      XCTAssertGreaterThan(field[0].frame.midX, x + 10)
      XCTAssertTrue(field.allSatisfy { $0.value as? String == "standing" })
      for i in [1, 2] {
        touch(field[i].frame.midX, field[i].frame.midY).tap()
        XCTAssertEqual(field[i].value as? String, "marked down")
      }
      XCTAssertEqual(field[0].value as? String, "standing")
      if orientation == "Behind Team B" {
        shot("Zoomed-cluster")
        tap("2 down")
        XCTAssertTrue(app.buttons["Fit whole pitch"].exists)
        tap("Fit whole pitch")
        XCTAssertEqual(app.buttons["fB0"].value as? String, "standing")
        XCTAssertFalse(app.buttons["fB1"].exists)
      } else {
        touch(field[1].frame.midX, field[1].frame.midY).tap()
        touch(field[2].frame.midX, field[2].frame.midY).tap()
        tap("Change view")
        XCTAssertTrue(app.buttons["Zoom in on pitch"].exists)
      }
    }
  }

  func testPlaceInkastOnZoomedPitch() {
    launch("scorer", after: 28)
    let pitch = app.descendants(matching: .any).matching(identifier: "pitch").firstMatch
    let frame = pitch.frame
    let unit = min((frame.width - 68) / 5, (frame.height - 68) / 8)
    tap("Zoom in on pitch")
    // The one-handed 2× view centres Team B's half. Three taps in cell (1, 2)
    // must come back there after returning to the fitted pitch.
    let point = CGVector(dx: frame.midX - 2 * unit, dy: frame.midY - unit)
    for _ in 0..<3 { app.coordinate(withNormalizedOffset: .zero).withOffset(point).tap() }
    tap("Fit whole pitch")
    for i in 0..<3 {
      XCTAssertTrue(app.buttons["fB" + String(i)].label.contains("across 1, depth 2"))
    }
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

  func testResumeAnOlderUnfinishedGame() {
    launch("thisgame", after: 28)
    let start = app.buttons.matching(NSPredicate(format: "label ==[c] 'Start scoring'")).firstMatch
    for _ in 0..<5 where !start.isHittable { app.swipeUp() }
    tap("Start scoring")
    tap("Back to Games")
    let older = app.buttons.matching(NSPredicate(format: "label ==[c] 'Resume scoring, Wobbly Towers versus Birch Batons'")).firstMatch
    XCTAssertTrue(older.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label ==[c] 'Resume scoring, Mossy Stakes versus Crooked Crowns'")).firstMatch.exists)
    for _ in 0..<4 where !older.isHittable { app.swipeUp() }
    older.tap()
    XCTAssertTrue(app.buttons["Change view"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label ==[c] 'Later'")).firstMatch.exists)
  }

  func testCorrectACompletedGameWithoutUndoingTheResult() {
    launch("scorer", after: 37)
    tap("King down")
    tap("Edit timeline")
    let turn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Turn 5,'")).firstMatch
    turn.tap()
    tap("Baton 5 · a miss")
    tap("More options")
    tap("Edit thrower")
    tap("Unknown")
    tap("Save change")
    tap("Back to Score sheet")
    XCTAssertTrue(app.staticTexts["Wobbly Towers beat Birch Batons"].waitForExistence(timeout: 5))
    let notation = app.staticTexts["The game file"].value as? String ?? ""
    XCTAssertTrue(notation.contains(" = o:K"), notation)
  }

  func testSectionsKeepScoringAndTimelineInPlace() {
    launch("scorer", after: 31)
    let field = app.buttons["fB0"]
    tap("fB0")
    tap("section-Stats")
    XCTAssertTrue(app.buttons["section-Stats"].isSelected)
    tap("section-Roster")
    XCTAssertTrue(app.buttons["section-Roster"].isSelected)
    tap("section-Games")
    XCTAssertEqual(field.value as? String, "marked down")
    tap("1 down")
    tap("More")
    tap("Timeline")
    let turn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Turn 5,'")).firstMatch
    turn.tap()
    tap("section-Roster")
    tap("section-Games")
    XCTAssertTrue(app.buttons["Baton 1 · 1 down"].exists)
    tap("Back to Scoring")
    XCTAssertEqual(app.buttons["fB0"].value as? String, "standing")
    tap("Back to Games")
    XCTAssertTrue(app.buttons["New game"].exists)
  }

  func testSectionsKeepDraftAndNameEditor() {
    launch("teams", after: 0)
    let name = app.textFields["Side A team name"]
    name.tap()
    name.typeText(" II")
    let draft = name.value as? String
    XCTAssertTrue(draft?.contains("II") == true)
    tap("section-Roster")
    let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Wren'")).firstMatch
    row.tap()
    XCTAssertTrue(app.textFields["Name"].exists)
    tap("section-Stats")
    tap("section-Roster")
    XCTAssertTrue(app.textFields["Name"].exists)
    tap("section-Games")
    XCTAssertEqual(name.value as? String, draft)
  }

  func testStepThroughAnImportedGame() {
    launch("imported", after: 0)
    tap("Play by play")
    let previous = app.buttons.matching(NSPredicate(format: "label ==[c] 'Previous'")).firstMatch
    XCTAssertFalse(previous.isEnabled)
    let pitch = app.descendants(matching: .any).matching(identifier: "replayPitch").firstMatch
    let start = pitch.label
    tap("Next")
    tap("Next")
    XCTAssertNotEqual(pitch.label, start)
    tap("Previous")
    tap("Previous")
    XCTAssertEqual(pitch.label, start)
    tap("Jump to turn")
    tap("Turn 2")
    tap("Next")
    tap("Details")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Field ·'")).firstMatch.exists)
    tap("section-Stats")
    tap("section-Games")
    XCTAssertTrue(app.staticTexts["Pitch details"].exists)
    tap("Back to Play by play")
    XCTAssertEqual(app.buttons["Jump to turn"].value as? String, "Turn 2")
    shot("Play-by-play")
    tap("Change view")
    XCTAssertEqual(app.buttons["Change view"].value as? String, "Sideline")
    tap("Zoom in on pitch")
    tap("Fit whole pitch")
    tap("Jump to turn")
    tap("Last play")
    XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label ==[c] 'Next'")).firstMatch.isEnabled)
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'won ·'")).firstMatch.exists)
    tap("Back to Score sheet")
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label ==[c] 'Play by play'")).firstMatch.exists)
    tap("Game stats")
    XCTAssertTrue(app.buttons["section-Games"].isSelected)
    tap("section-Stats")
    XCTAssertTrue(app.buttons["section-Stats"].isSelected)
    tap("section-Games")
    tap("Back to Score sheet")
    XCTAssertTrue(app.buttons["Game stats"].exists)
  }

  func testPrintableScoreSheet() {
    launch("sheet", after: 0)
    let export = app.buttons.matching(NSPredicate(format: "label ==[c] 'Score sheet PDF'")).firstMatch
    for _ in 0..<6 where !export.isHittable { app.swipeUp() }
    tap("Score sheet PDF")
    XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 8), app.debugDescription)
    let page = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS[c] 'Score sheet · Page 1' OR label CONTAINS[c] '1 of 1' OR value CONTAINS[c] '1 of 1'")
    ).firstMatch
    XCTAssertTrue(page.waitForExistence(timeout: 15), app.debugDescription)
    shot("Printable-score-sheet")
  }

  /// Starts in setup, picks the opening, then scores every throw through the live controls.
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
