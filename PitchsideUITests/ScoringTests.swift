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
    expectLandscape(screen == "scorer")
  }

  func expectLandscape(_ landscape: Bool, file: StaticString = #filePath, line: UInt = #line) {
    let window = app.windows.firstMatch
    let matches = NSPredicate { _, _ in
      guard window.exists else { return false }
      let frame = window.frame
      if !landscape { return frame.height > frame.width }
      guard frame.width > frame.height else { return false }
      let pitch = self.app.descendants(matching: .any)["pitch"]
      let history = self.app.scrollViews["turn-history"]
      return pitch.exists && history.exists && pitch.frame.maxX <= history.frame.minX + 1
    }
    let expectation = XCTNSPredicateExpectation(predicate: matches, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 6), .completed, app.debugDescription, file: file, line: line)
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

  // The runner can return a portrait pixel buffer even for a landscape window.
  // Choose one landscape direction so the gallery and colour sampling use
  // the same upright image, including when the simulator started in portrait.
  func screenImage() -> UIImage {
    let frame = app.windows.firstMatch.frame
    let landscape = frame.width > frame.height
    let direction: UIDeviceOrientation = landscape ? .landscapeLeft : .portrait
    if XCUIDevice.shared.orientation != direction { XCUIDevice.shared.orientation = direction }
    let image = XCUIScreen.main.screenshot().image
    guard landscape, let pixels = image.cgImage, pixels.width < pixels.height else { return image }
    let upright = UIImage(cgImage: pixels, scale: image.scale, orientation: .left)
    return UIGraphicsImageRenderer(size: upright.size, format: upright.imageRendererFormat).image { _ in
      upright.draw(at: .zero)
    }
  }

  func shot(_ name: String) {
    let attachment = XCTAttachment(data: screenImage().pngData()!, uniformTypeIdentifier: "public.png")
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Read the rendered rough at the side of the pitch to identify the actual appearance.
  func darkPitch() -> Bool {
    let pitch = app.descendants(matching: .any)["pitch"].frame
    let screenshot = screenImage()
    guard let pixels = screenshot.cgImage else { return false }
    let scale = CGFloat(pixels.width) / app.windows.firstMatch.frame.width
    let samplePoint = CGRect(x: (pitch.minX + 3) * scale, y: pitch.midY * scale, width: 1, height: 1)
    guard let sample = pixels.cropping(to: samplePoint) else { return false }
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

    // The turn changes after the second opening baton. The next entry belongs to Team B's inkaster.
    let turn = app.descendants(matching: .any)["entry-turn"]
    let player = app.buttons["Change who throws"]
    XCTAssertEqual(turn.label, "Turn 1")
    XCTAssertEqual(player.value as? String, "Kim")
    XCTAssertFalse(app.staticTexts["Inkast complete"].exists)
    tap("bB1")
    tap("1 down")
    XCTAssertEqual(turn.label, "Turn 1")
    XCTAssertEqual(player.value as? String, "Dana")
    tap("bB3")
    tap("1 down")
    XCTAssertEqual(turn.label, "Turn 2")
    XCTAssertEqual(player.value as? String, "Sam")
    XCTAssertTrue(app.staticTexts["entry-action"].label.hasPrefix("Inkast · "))
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
    let originalFile = app.staticTexts["The game file"].value as? String
    tap("Undo last event")
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label ==[c] 'King down'")).firstMatch
        .waitForExistence(timeout: 5))
    tap("Redo")
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label ==[c] 'Undo last event'")).firstMatch
        .waitForExistence(timeout: 5))
    let notation = app.staticTexts["The game file"].value as? String ?? ""
    XCTAssertEqual(notation, originalFile)
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
    let thrower = app.buttons["Change who throws"]
    let turn = app.descendants(matching: .any)["entry-turn"]
    let action = app.staticTexts["entry-action"]
    XCTAssertEqual(turn.label, "Turn 5")
    XCTAssertEqual(action.label, "Inkast · 3 left")
    // The strip reads across at standard sizes and down at accessibility sizes.
    XCTAssertTrue(turn.frame.maxX <= thrower.frame.minX || turn.frame.maxY <= thrower.frame.minY)
    XCTAssertTrue(thrower.frame.maxX <= action.frame.minX || thrower.frame.maxY <= action.frame.minY)
    XCTAssertEqual(thrower.value as? String, "Kim")
    XCTAssertGreaterThanOrEqual(thrower.frame.minX, pitch.frame.maxX - 1)
    tap("Change who throws")
    tap("Dana")
    XCTAssertEqual(thrower.value as? String, "Dana")
    let frame = pitch.frame
    let unit = min((frame.width - 68) / 5, (frame.height - 68) / 8)
    tap("Zoom in on pitch")
    // The one-handed 2× view centres Team B's half. Three taps in cell (1, 2)
    // must come back there after returning to the fitted pitch.
    let point = CGVector(dx: frame.midX - 2 * unit, dy: frame.midY - unit)
    let landing = app.coordinate(withNormalizedOffset: .zero).withOffset(point)
    for _ in 0..<2 { landing.tap() }
    XCTAssertEqual(action.label, "Inkast · 1 left")
    XCTAssertEqual(thrower.value as? String, "Dana")
    landing.tap()
    XCTAssertEqual(action.label, "Baton 1 of 6")
    XCTAssertTrue(app.staticTexts["Inkast complete"].exists)
    XCTAssertEqual(thrower.value as? String, "Kim")
    tap("Fit whole pitch")
    for i in 0..<3 {
      XCTAssertTrue(app.buttons["fB" + String(i)].label.contains("across 1, depth 2"))
    }
    tap("Miss")
    XCTAssertFalse(app.staticTexts["Inkast complete"].exists)
    XCTAssertEqual(turn.label, "Turn 5")
    XCTAssertEqual(thrower.value as? String, "Dana")
    tap("Undo")
    XCTAssertTrue(app.staticTexts["Inkast complete"].exists)
  }

  func testMiddleOfClusterSurvivesReopenAndReplay() {
    launch("scorer", after: 28)
    spot(2.14, 4.18)
    tap("Out")
    tap("More")
    tap("Play by play")
    XCTAssertTrue(app.staticTexts["Inkast · throw 2"].exists)
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'Kubb out'")).firstMatch.exists)
    XCTAssertFalse(app.buttons["Next"].isEnabled)
    tap("Back to Scoring")
    expectLandscape(true)
    spot(2.41, 4.42)
    spot(2.72, 4.69) // The rethrow.
    let fields = (0..<3).map { app.buttons["fB" + String($0)] }
    func tapLocation(_ button: XCUIElement) -> String {
      button.label.components(separatedBy: "tapped at ").last ?? ""
    }
    let places = fields.map(tapLocation)
    XCTAssertEqual(Set(places).count, 3)
    let centres = fields.map { $0.frame.midX }
    tap("fB1")
    tap("1 down")
    tap("Back to Games")
    expectLandscape(false)
    tap("Resume scoring, Wobbly Towers versus Birch Batons")
    expectLandscape(true)
    XCTAssertEqual(tapLocation(fields[0]), places[0])
    XCTAssertEqual(tapLocation(fields[1]), places[2])
    XCTAssertEqual(fields[0].frame.midX, centres[0], accuracy: 1)
    XCTAssertEqual(fields[1].frame.midX, centres[2], accuracy: 1)
    tap("More")
    tap("Play by play") // Opens at the latest recorded throw.
    tap("Jump to turn")
    tap("Turn 5")
    XCTAssertTrue(app.staticTexts["Inkast · throw 1"].exists)
    tap("Next")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'Kubb out'")).firstMatch.exists)
    tap("Next")
    tap("Next")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'Rethrow in'")).firstMatch.exists)
    tap("Zoom in on pitch")
    shot("Inkast-replay")
    tap("Fit whole pitch")
    tap("Details")
    func standing(_ count: Int) -> XCUIElement {
      app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Field · " + String(count) + " standing")).firstMatch
    }
    let all = standing(3).label
    XCTAssertTrue(places.allSatisfy { all.contains($0 + " (tapped)") }, all)
    tap("Back to Play by play")
    tap("Next") // Advantage
    tap("Next") // First baton
    tap("Zoom in on pitch")
    shot("Cluster-replay")
    tap("Details")
    let fallen = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Felled in Team'")).firstMatch.label
    XCTAssertTrue(fallen.contains(places[1] + " (tapped)"), fallen)
    XCTAssertTrue(standing(2).label.contains(places[0]) && standing(2).label.contains(places[2]))
    tap("Back to Play by play")
    tap("Previous")
    tap("Details")
    XCTAssertTrue(standing(3).label.contains(places[1]))
    tap("Back to Play by play")
    tap("Back to Scoring")
    expectLandscape(true)
    XCTAssertEqual(tapLocation(fields[1]), places[2])
  }

  func testChooseOneOfThreeCoincidentPlacements() {
    launch("scorer", after: 28)
    for _ in 0..<3 { spot(2.5, 5.25) }
    tap("fB1")
    tap("Field kubb 2")
    XCTAssertEqual(app.buttons["fB1"].value as? String, "marked down")
    XCTAssertEqual(app.buttons["fB0"].value as? String, "standing")
    tap("1 down")
    XCTAssertTrue(app.buttons["fB1"].exists)
    XCTAssertFalse(app.buttons["fB2"].exists)
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

  func testUndoRedoAcrossTurnAndNewThrow() {
    launch("scorer", after: 1)
    tap("Miss")
    XCTAssertTrue(app.buttons["Later"].exists)
    tap("Undo")
    XCTAssertFalse(app.buttons["Later"].exists)
    XCTAssertTrue(app.buttons["Redo"].isHittable)
    shot("Redo-throw")
    tap("Redo")
    XCTAssertTrue(app.buttons["Later"].exists)
    tap("Undo")
    tap("bB0")
    tap("1 down")
    XCTAssertFalse(app.buttons["Redo"].exists)
    tap("More")
    tap("Timeline")
    expectLandscape(false)
    let turn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Turn 1,'")).firstMatch
    XCTAssertTrue(turn.waitForExistence(timeout: 4))
    let beforeUndo = turn.label
    app.scrollViews.buttons["Undo"].tap()
    let changed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label != %@", beforeUndo), object: turn)
    XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 4), .completed)
    tap("Redo")
    XCTAssertEqual(turn.label, beforeUndo)
    tap("Back to Scoring")
    XCTAssertTrue(app.buttons["Later"].exists)
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
    XCTAssertEqual(app.staticTexts["entry-action"].label, "Place punishment kubb")
    XCTAssertFalse(app.staticTexts["Inkast complete"].exists)
    XCTAssertFalse(app.buttons["Change who throws"].exists)
    tap("Place it later")
    XCTAssertTrue(app.staticTexts["Inkast complete"].exists)
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
    app.switches.matching(NSPredicate(format: "label BEGINSWITH[c] 'Where kubbs stand'")).firstMatch
      .tap()
    app.switches.matching(NSPredicate(format: "label BEGINSWITH[c] 'Who threw'")).firstMatch.tap()
    tap("Done")
    XCTAssertFalse(app.buttons["Change who throws"].exists)
    XCTAssertEqual(app.staticTexts["entry-team"].label, "Wobbly Towers")
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
    tap("More")
    tap("Game called")
    tap("Wobbly Towers")
    let notes = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Scorer notes'")).firstMatch
    XCTAssertTrue(notes.waitForExistence(timeout: 4))
    app.terminate()
    app.launchArguments = ["-PitchsideDemo", "-PitchsideReopenDemo", "-PitchsideScreen", "sheet"]
    app.launch()
    XCTAssertTrue(notes.waitForExistence(timeout: 4))
    notes.tap()
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'file follows the count'")).firstMatch.exists)
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
    let original = app.staticTexts["The game file"].value as? String
    let row = app.buttons["editTurn5"]
    for _ in 0..<6 where !row.isHittable { app.swipeUp() }
    tap("editTurn5")
    tap("Baton 5 · a miss")
    tap("More options")
    tap("Edit thrower")
    tap("Unknown")
    tap("Save change")
    tap("Back to Score sheet")
    XCTAssertTrue(app.staticTexts["Wobbly Towers beat Birch Batons"].waitForExistence(timeout: 5))
    let notation = app.staticTexts["The game file"].value as? String ?? ""
    XCTAssertTrue(notation.contains(" = o:K"), notation)
    XCTAssertNotEqual(notation, original)
    app.terminate()
    app.launchArguments = ["-PitchsideDemo", "-PitchsideReopenDemo", "-PitchsideScreen", "sheet"]
    app.launch()
    XCTAssertEqual(app.staticTexts["The game file"].value as? String, notation)
    tap("Undo edit")
    XCTAssertTrue(app.staticTexts["Wobbly Towers beat Birch Batons"].exists)
    XCTAssertEqual(app.staticTexts["The game file"].value as? String, original)
    shot("Sheet-redo-edit")
    app.terminate()
    app.launch()
    tap("Redo edit")
    XCTAssertEqual(app.staticTexts["The game file"].value as? String, notation)
    XCTAssertTrue(app.buttons["editTurn5"].exists)
  }

  func testRemoveWinningThrowFromSheetAndRestoreIt() {
    launch("scorer", after: 37)
    tap("King down")
    let original = app.staticTexts["The game file"].value as? String
    let row = app.buttons["editTurn5"]
    for _ in 0..<6 where !row.isHittable { app.swipeUp() }
    tap("editTurn5")
    tap("Baton 6 · king down")
    tap("Other edits")
    tap("Remove this observation")
    XCTAssertTrue(app.staticTexts["The game would still be on the pitch."].exists)
    tap("Keep original")
    tap("Baton 6 · king down")
    tap("Other edits")
    tap("Remove this observation")
    tap("Change, review turn 5")
    tap("Back to Scoring")
    XCTAssertTrue(app.buttons["King down"].exists)
    tap("Undo")
    XCTAssertEqual(app.staticTexts["The game file"].value as? String, original)
    tap("Redo edit")
    XCTAssertTrue(app.buttons["King down"].exists)
    tap("King down")
    XCTAssertTrue(app.buttons["Undo last event"].exists)
    XCTAssertFalse(app.buttons["Redo edit"].exists)
  }

  func testBrowseTurnsBesideThePitchWhileScoring() {
    XCUIDevice.shared.orientation = .portrait
    defer { XCUIDevice.shared.orientation = .portrait }
    launch("scorer", after: 31)
    tap("Change who throws")
    tap("Ole")
    tap("fB0")
    let history = app.scrollViews["turn-history"]
    XCTAssertTrue(history.waitForExistence(timeout: 5))
    let pitch = app.descendants(matching: .any)["pitch"]
    XCTAssertLessThanOrEqual(pitch.frame.maxX, history.frame.minX + 1)
    XCTAssertEqual(app.buttons["Change who throws"].value as? String, "Ole")
    XCTAssertEqual(app.buttons["fB0"].value as? String, "marked down")
    XCTAssertFalse(app.buttons["Show latest turn"].exists)
    let older = app.buttons["history-turn-2"]
    for _ in 0..<8 where !older.isHittable { history.swipeUp() }
    older.tap()
    let firstBaton = app.staticTexts["Baton 1 · Sam · 2 down"]
    for _ in 0..<4 where !firstBaton.isHittable { history.swipeUp() }
    XCTAssertTrue(firstBaton.isHittable)
    let record = app.buttons["1 down"]
    XCTAssertTrue(record.isHittable)
    XCTAssertLessThanOrEqual(record.frame.maxY, app.windows.firstMatch.frame.maxY)
    shot("Landscape-turn-history")
    tap("1 down")
    tap("Show latest turn")
    XCTAssertTrue(app.staticTexts["Baton 1 · Ole · 1 down"].waitForExistence(timeout: 4))
    tap("Undo")
    XCTAssertFalse(app.staticTexts["Baton 1 · Ole · 1 down"].exists)
    tap("Redo")
    XCTAssertTrue(app.staticTexts["Baton 1 · Ole · 1 down"].exists)
    XCUIDevice.shared.orientation = .landscapeRight
    expectLandscape(true)
    XCUIDevice.shared.orientation = .portrait
    expectLandscape(true)
    XCTAssertTrue(history.isHittable)
    XCTAssertEqual(app.buttons["Change who throws"].value as? String, "Dana")
    XCTAssertTrue(app.buttons["Miss"].isHittable)
  }

  func testScoringUsesTheWholeScreenAndResumesFromGames() {
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }
    launch("home", after: 31)
    tap("Resume scoring, Wobbly Towers versus Birch Batons")
    expectLandscape(true)
    let games = app.buttons["section-Games"]
    let roster = app.buttons["section-Roster"]
    let stats = app.buttons["section-Stats"]
    XCTAssertFalse(games.exists)
    XCTAssertFalse(roster.exists)
    XCTAssertFalse(stats.exists)
    tap("fB0")
    tap("1 down")
    tap("Change who throws")
    tap("Ole")
    tap("fB0")
    tap("More")
    tap("Timeline")
    expectLandscape(false)
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Turn 5,'")).firstMatch.tap()
    tap("section-Roster")
    tap("section-Games")
    XCTAssertTrue(app.buttons["Baton 1 · 1 down"].exists)
    tap("Back to Scoring")
    expectLandscape(true)
    tap("More")
    tap("Play by play")
    expectLandscape(false)
    XCTAssertTrue(games.isSelected)
    tap("Back to Scoring")
    expectLandscape(true)
    XCTAssertEqual(app.buttons["Change who throws"].value as? String, "Ole")
    XCTAssertEqual(app.buttons["fB0"].value as? String, "marked down")
    tap("Back to Games")
    expectLandscape(false)
    XCTAssertTrue(games.isSelected)
    tap("section-Roster")
    expectLandscape(false)
    XCTAssertTrue(roster.isSelected)
    tap("section-Stats")
    expectLandscape(false)
    XCTAssertTrue(stats.isSelected)
    tap("section-Games")
    tap("Resume scoring, Wobbly Towers versus Birch Batons")
    XCTAssertFalse(games.exists)
    XCTAssertEqual(app.buttons["Change who throws"].value as? String, "Dana")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Baton 2 of 6'")).firstMatch.exists)
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
    XCTAssertFalse(app.buttons["editTurn1"].exists)
    XCTAssertFalse(app.buttons["Edit timeline"].exists)
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
    expectLandscape(true)
    XCTAssertTrue(app.buttons["bB0"].waitForExistence(timeout: 5))
    for _ in 0..<5 {
      tap("bB0")
      tap("1 down")
    }
    tap("King down")
    XCTAssertTrue(app.staticTexts["Mossy Stakes beat Crooked Crowns"].waitForExistence(timeout: 5))
    expectLandscape(false)
    XCTAssertTrue(app.buttons["section-Games"].isSelected)
  }
}
