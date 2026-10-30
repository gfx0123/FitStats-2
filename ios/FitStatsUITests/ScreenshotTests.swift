import XCTest

/// Walks through every screen with fixture data and saves screenshots.
/// CI passes FITSTATS_FIXTURES and SCREENSHOT_DIR via TEST_RUNNER_ environment variables.
final class ScreenshotTests: XCTestCase {
    private var outDir: URL?

    override func setUpWithError() throws {
        continueAfterFailure = true
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            outDir = url
        }
    }

    private func shot(_ name: String) {
        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let outDir {
            try? screenshot.pngRepresentation.write(to: outDir.appendingPathComponent("\(name).png"))
        }
    }

    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        if button.exists { button.tap() }
    }

    private func open(_ app: XCUIApplication, _ id: String, _ names: [String]) {
        let element = app.buttons[id]
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("missing \(id)")
            return
        }
        element.tap()
        for (index, name) in names.enumerated() {
            if index > 0 { app.swipeUp() }
            shot(name)
        }
        back(app)
        _ = app.buttons["ring-recovery"].waitForExistence(timeout: 5)
    }

    /// Swipes up until the element is on screen, then drags its top up under the navigation bar
    /// so the whole card is in the shot.
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<10 where !onScreen(app, element) { app.swipeUp() }
        guard onScreen(app, element) else { return }
        let window = app.windows.firstMatch.frame
        let distance = element.frame.minY - (window.minY + window.height * 0.14)
        guard distance > 20 else { return }
        scrollPage(app, by: distance)
    }

    /// Drags the page by about `dy` points (positive goes further down the page) and holds
    /// still before lifting, so it doesn't fling. It starts left of the middle, clear of edit
    /// mode's remove buttons and resize handles, which a swipe from the middle can catch.
    private func scrollPage(_ app: XCUIApplication, by dy: CGFloat) {
        let window = app.windows.firstMatch.frame
        let d = Swift.max(-window.height * 0.45, Swift.min(window.height * 0.45, dy))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: d > 0 ? 0.75 : 0.3))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -d)),
                    withVelocity: .default, thenHoldForDuration: 0.3)
    }

    /// Back to the top of Home in edit mode, where the time-of-day switch is.
    private func editTop(_ app: XCUIApplication) {
        let toggle = app.switches["home-time-of-day"]
        let window = app.windows.firstMatch.frame
        for _ in 0..<25 where !(toggle.exists && toggle.frame.minY > window.minY + 100) {
            scrollPage(app, by: -window.height)
        }
    }

    private func describe(_ element: XCUIElement) -> String {
        "\(element.identifier): exists \(element.exists), frame \(element.frame)"
    }

    /// Scrolls until `element` is on screen, or with `near`, until its middle is within 90
    /// points of that fraction of the screen's height.
    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement, near: CGFloat? = nil) {
        let window = app.windows.firstMatch.frame
        let target = window.minY + window.height * (near ?? 0.45)
        func placed() -> Bool {
            onScreen(app, element) && (near == nil || abs(element.frame.midY - target) < 90)
        }
        for _ in 0..<40 where !placed() {
            if element.exists, !element.frame.isEmpty {
                let before = element.frame.midY
                let dy = before - target
                scrollPage(app, by: dy)
                trace("scroll \(element.identifier) by \(Int(dy)): midY \(Int(before)) -> \(Int(element.frame.midY))")
            } else {
                scrollPage(app, by: window.height * 0.4)
            }
        }
        trace("scrolled to \(describe(element)), on screen \(onScreen(app, element))")
    }

    /// Scroll diagnostics, saved next to the screenshots (scroll-log.txt).
    private func trace(_ line: String) {
        guard let outDir else { return }
        let url = outDir.appendingPathComponent("scroll-log.txt")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Its middle is between the navigation bar and the tab bar (isHittable also holds for an
    /// element mostly under the navigation bar, where a press opens Notification Center).
    private func onScreen(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let window = app.windows.firstMatch.frame
        let f = element.frame
        return !f.isEmpty && f.midY > window.minY + 120 && f.midY < window.maxY - 120
    }

    private func middle(_ element: XCUIElement, dy: CGFloat = 0.5) -> XCUICoordinate {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy))
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Trends opens full screen from the chart button at the top of Today.
    private func openTrends(_ app: XCUIApplication) {
        app.tabBars.buttons["Today"].tap()
        let button = app.buttons["today-trends"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no Trends button on Today")
        button.tap()
        XCTAssertTrue(app.buttons["trends-done"].waitForExistence(timeout: 5), "Trends did not open")
    }

    private func closeTrends(_ app: XCUIApplication) {
        let done = app.buttons["trends-done"]
        if done.waitForExistence(timeout: 3) { done.tap() }
    }

    func test01ConnectScreen() {
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = ""
        app.launch()
        _ = app.buttons["Connect Google Health"].waitForExistence(timeout: 10)
        shot("00-connect")
        app.terminate()
    }

    func test02AllScreens() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        shot("01-today")
        app.swipeUp()
        shot("02-today-2")
        app.swipeUp()
        shot("03-today-3")
        for _ in 0..<5 { app.swipeDown() }

        // Live heart rate (fixture mode simulates the band; the simulator has no Bluetooth).
        let liveButton = app.buttons["open-live-hr"]
        if liveButton.waitForExistence(timeout: 5) {
            liveButton.tap()
            _ = app.descendants(matching: .any).matching(identifier: "live-hr").firstMatch.waitForExistence(timeout: 5)
            sleep(2)
            shot("46-live-hr")
            back(app)
            _ = app.buttons["ring-recovery"].waitForExistence(timeout: 5)
        } else {
            XCTFail("missing open-live-hr")
        }

        open(app, "ring-recovery", ["05-recovery", "06-recovery-2"])
        open(app, "ring-sleep", ["07-sleep", "08-sleep-2", "09-sleep-3"])
        open(app, "ring-strain", ["10-strain", "11-strain-2"])
        // Stress, then a tap on its day-by-day chart shows that day's value in a bubble.
        let stress = app.buttons["ring-stress"]
        if stress.waitForExistence(timeout: 5) {
            stress.tap()
            shot("12-stress")
            let chart = app.descendants(matching: .any)["trend-chart"].firstMatch
            if chart.waitForExistence(timeout: 5) {
                if !chart.isHittable { app.swipeUp() }
                chart.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
                XCTAssertTrue(app.descendants(matching: .any)["chart-bubble"].firstMatch.waitForExistence(timeout: 3), "no bubble on the stress chart")
                shot("12-stress-bubble")
            } else {
                XCTFail("missing trend-chart")
            }
            back(app)
            _ = app.buttons["ring-recovery"].waitForExistence(timeout: 5)
        } else {
            XCTFail("missing ring-stress")
        }

        openTrends(app)
        shot("13-trends")
        app.swipeUp()
        shot("14-trends-2")
        for _ in 0..<3 { app.swipeDown() }
        let hrv = app.buttons["metric-hrv_rmssd"]
        if hrv.waitForExistence(timeout: 5) {
            hrv.tap()
            shot("15-metric-hrv")
            app.swipeUp()
            shot("16-metric-hrv-2")
            back(app)
        }

        // Insights, from the top of Trends.
        let insights = app.buttons["open-insights"]
        if insights.waitForExistence(timeout: 5) {
            insights.tap()
            shot("17-insights")
            app.swipeUp()
            shot("18-insights-2")
            back(app)
        } else {
            XCTFail("missing open-insights")
        }
        closeTrends(app)

        app.tabBars.buttons["Coach"].tap()
        shot("19-coach")
        app.swipeUp()
        shot("20-coach-2")
        let history = app.buttons["coach-history"]
        if history.waitForExistence(timeout: 5) {
            history.tap()
            let thread = app.buttons["coach-thread"].firstMatch
            if thread.waitForExistence(timeout: 5) {
                thread.tap()
                shot("21-coach-chat")
            } else {
                XCTFail("no coach conversation in the history sheet")
            }
        }

        app.tabBars.buttons["Settings"].tap()
        shot("22-settings")
        app.swipeUp()
        shot("23-settings-2")
        app.swipeUp()
        shot("24-settings-3")

        // Journal sheet, then the nearest day with a workout and its detail.
        app.tabBars.buttons["Today"].tap()
        let edit = app.buttons["journal-edit"]
        if edit.waitForExistence(timeout: 5) {
            edit.tap()
            shot("25-journal")
            app.buttons["Cancel"].tap()
        } else {
            XCTFail("missing journal-edit")
        }
        let workout = app.buttons["workout-row"].firstMatch
        for _ in 0..<6 where !workout.exists {
            app.buttons["Previous day"].tap()
            sleep(1)
        }
        if workout.exists {
            // A past day: no Tonight card, a "Log day" journal (make-fixtures leaves this day unlogged).
            shot("04-today-past-day")
            for _ in 0..<6 where !workout.isHittable { app.swipeUp() }
            shot("28-today-workouts")
            workout.tap()
            shot("26-workout")
            app.swipeUp()
            shot("27-workout-2")
            back(app)
        } else {
            XCTFail("no workout in the last 7 days of fixtures")
        }
    }

    /// Every Home card (FITSTATS_HOME_CARDS=all) at its default size and a Smart Stack swiped,
    /// then edit mode opened by holding a card: the wobbling grid, a resize by dragging the
    /// corner handle, a Metric card's and a stack's settings, a card dropped on another to
    /// stack them, time-of-day layouts, the Add cards previews, an add.
    /// Then every card small and every card medium (FITSTATS_HOME_SIZE).
    func test03HomeCards() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        app.launchEnvironment["FITSTATS_HOME_CARDS"] = "all"
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        shot("30-home-all")
        for index in 1...6 {
            app.swipeUp()
            shot("3\(index)-home-all-\(index + 1)")
        }
        // A Smart Stack pages sideways to its next card.
        let stack = element(app, "home-card-stack-fixture")
        reveal(app, stack)
        if stack.exists {
            shot("65-home-stack")
            stack.swipeLeft()
            sleep(1)
            shot("66-home-stack-swiped")
        } else {
            XCTFail("missing home-card-stack-fixture")
        }
        for _ in 0..<16 { app.swipeDown() }

        let card = element(app, "home-card-scores")
        guard card.waitForExistence(timeout: 5) else {
            XCTFail("missing home-card-scores")
            return
        }
        card.press(forDuration: 0.8)
        let done = app.buttons["home-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "edit mode did not start")
        shot("38-home-edit")
        // Dragging Tonight's corner handle to the right stretches it to medium when released.
        let handle = element(app, "home-resize-tonight")
        if handle.waitForExistence(timeout: 3) {
            let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 200, dy: 10)))
            sleep(1)
            shot("47-home-edit-resized")
        } else {
            XCTFail("missing home-resize-tonight")
        }
        // Holding Vitals and dragging it onto the lower part of Activity moves it below Activity.
        let vitals = element(app, "home-card-vitals")
        let activity = element(app, "home-card-activity")
        scrollTo(app, vitals, near: 0.35)
        if onScreen(app, vitals), onScreen(app, activity) {
            middle(vitals).press(forDuration: 0.6, thenDragTo: middle(activity, dy: 0.88),
                                 withVelocity: .default, thenHoldForDuration: 0.8)
            sleep(1)
            shot("70-home-reordered")
            XCTAssertGreaterThan(vitals.frame.minY, activity.frame.minY, "Vitals did not move below Activity")
        } else {
            XCTFail("vitals or activity not reachable for reordering: \(describe(vitals)); \(describe(activity))")
        }
        // Tapping a card while editing opens its settings: the Metric card switches to HRV.
        let metric = element(app, "home-card-metric-fixture")
        scrollTo(app, metric)
        if onScreen(app, metric) {
            middle(metric).tap()
            let settingsDone = app.buttons["card-settings-done"]
            if settingsDone.waitForExistence(timeout: 5) {
                shot("61-card-settings-metric")
                let pick = app.buttons["card-settings-metric"]
                if pick.waitForExistence(timeout: 3) {
                    pick.tap()
                    sleep(1)
                    shot("62-metric-picker")
                    // HRV is under Heart, further down the list.
                    let hrv = app.buttons["metric-pick-hrv_rmssd"]
                    let list = app.collectionViews.firstMatch
                    for _ in 0..<6 where !(hrv.exists && hrv.isHittable) { list.swipeUp() }
                    if hrv.exists, hrv.isHittable { hrv.tap() } else { XCTFail("missing metric-pick-hrv_rmssd") }
                    sleep(1)
                    // Back to the settings if the list is still open.
                    let back = app.navigationBars["Metric"].buttons.firstMatch
                    if back.exists { back.tap() }
                    sleep(1)
                } else {
                    XCTFail("missing card-settings-metric")
                }
                if settingsDone.exists { settingsDone.tap() }
                sleep(1)
                shot("63-home-metric-hrv")
            } else {
                XCTFail("Metric card settings did not open")
            }
        } else {
            XCTFail("missing home-card-metric-fixture: \(describe(metric))")
        }
        let stackCell = element(app, "home-card-stack-fixture")
        scrollTo(app, stackCell)
        if onScreen(app, stackCell) {
            middle(stackCell).tap()
            let settingsDone = app.buttons["card-settings-done"]
            if settingsDone.waitForExistence(timeout: 5) {
                shot("64-stack-settings")
                settingsDone.tap()
                sleep(1)
            } else {
                XCTFail("Smart Stack settings did not open")
            }
        } else {
            XCTFail("missing home-card-stack-fixture in edit mode: \(describe(stackCell))")
        }
        // Dropping a card on the middle of another makes a Smart Stack of the two.
        editTop(app)
        let source = element(app, "home-card-recoveryTrend")
        let destination = element(app, "home-card-hrvTrend")
        scrollTo(app, source)
        if onScreen(app, source), onScreen(app, destination) {
            // Straight to the middle, then held there until it offers the stack.
            middle(source).press(forDuration: 1.2, thenDragTo: middle(destination),
                                 withVelocity: .default, thenHoldForDuration: 1.0)
            sleep(2)
            shot("67-home-stacked")
            XCTAssertFalse(source.exists || destination.exists, "recoveryTrend and hrvTrend did not become a stack")
        } else {
            XCTFail("recoveryTrend or hrvTrend not reachable for stacking: \(describe(source)); \(describe(destination))")
        }
        // Time-of-day layouts: each part of the day starts as a copy and can be edited apart.
        editTop(app)
        let timeOfDay = app.switches["home-time-of-day"]
        if timeOfDay.waitForExistence(timeout: 3) {
            timeOfDay.tap()
            sleep(1)
            shot("68-home-time-of-day")
            let evening = app.buttons["Evening"]
            if evening.waitForExistence(timeout: 3) {
                evening.tap()
                sleep(1)
                shot("69-home-evening-layout")
            } else {
                XCTFail("missing the Evening layout button")
            }
        } else {
            XCTFail("missing home-time-of-day")
        }
        // Every card is on Home in this mode, so Add cards is empty. Reset (kept in memory only
        // in this mode, nothing is stored) fills it with previews.
        let reset = app.buttons["home-reset"]
        scrollTo(app, reset)
        if onScreen(app, reset) {
            reset.tap()
            sleep(1)
            let addCards = app.buttons["home-add-cards"]
            if addCards.exists { addCards.tap() }
            shot("39-home-add-previews")
            // Last night is the first card in the list after a reset, so it's on screen here.
            let add = app.buttons["home-add-lastNight"]
            if add.waitForExistence(timeout: 3), add.isHittable { add.tap() } else { XCTFail("home-add-lastNight not reachable") }
            sleep(1)
            app.swipeUp()
            shot("48-home-add-previews-2")
            app.swipeUp()
            shot("49-home-add-previews-3")
        } else {
            XCTFail("home-reset not reachable: \(describe(reset))")
        }
        if done.exists { done.tap() }
        sleep(1)
        shot("50-home-after-edit")
        app.terminate()

        // Mid-resize (FITSTATS_HOLD_RESIZE keeps the stretch after the finger lifts): Journal, the
        // right card of a small pair, grows to the left, and Tonight stretches past its footprint.
        app.launchEnvironment["FITSTATS_HOLD_RESIZE"] = "1"
        app.launch()
        let scores = element(app, "home-card-scores")
        if scores.waitForExistence(timeout: 15) {
            scores.press(forDuration: 0.8)
            for (id, offset, name) in [("journal", CGVector(dx: -110, dy: 40), "71-home-resize-held-left"),
                                       ("tonight", CGVector(dx: 60, dy: 70), "72-home-resize-held")] {
                let handle = element(app, "home-resize-\(id)")
                if handle.waitForExistence(timeout: 5) {
                    let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    start.press(forDuration: 0.05, thenDragTo: start.withOffset(offset))
                    shot(name)
                } else {
                    XCTFail("missing home-resize-\(id)")
                }
            }
        } else {
            XCTFail("Today (held resize) did not load")
        }
        app.terminate()
        app.launchEnvironment["FITSTATS_HOLD_RESIZE"] = nil

        for (size, first, count) in [("small", 51, 3), ("medium", 55, 5)] {
            app.launchEnvironment["FITSTATS_HOME_SIZE"] = size
            app.launch()
            XCTAssertTrue(element(app, "home-card-scores").waitForExistence(timeout: 15), "Today (\(size)) did not load")
            sleep(1)
            shot("\(first)-home-\(size)")
            for index in 1...count {
                app.swipeUp()
                shot("\(first + index)-home-\(size)-\(index + 1)")
            }
            app.terminate()
        }
    }

    /// A swipe to the right from the middle of a pushed screen goes back, the Sleep screen lists
    /// the day's naps, and a tap outside the Coach's text field hides the keyboard.
    func test05Gestures() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        // The app's gesture notes, saved next to the screenshots (the simulator can write there).
        if let outDir { app.launchEnvironment["FITSTATS_DEBUG_LOG"] = outDir.appendingPathComponent("app-log.txt").path }
        app.launch()
        let ring = app.buttons["ring-recovery"]
        XCTAssertTrue(ring.waitForExistence(timeout: 15), "Today screen did not load")

        ring.tap()
        sleep(1)
        XCTAssertFalse(ring.isHittable, "Recovery did not open")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 250, dy: 0)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
        shot("73-swiped-back")
        XCTAssertTrue(ring.isHittable, "a swipe from the middle of Recovery did not go back to Today")
        if !ring.isHittable {
            // Back to Today for the rest: the system's own edge swipe, else the back button.
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.55))
            edge.press(forDuration: 0.05, thenDragTo: edge.withOffset(CGVector(dx: 250, dy: 0)),
                       withVelocity: .fast, thenHoldForDuration: 0)
            sleep(1)
            if !ring.isHittable { back(app) }
            sleep(1)
        }

        // Today's nap (the fixtures add one, 13:20–14:05) has its own section on the Sleep screen.
        let sleepRing = app.buttons["ring-sleep"]
        if sleepRing.waitForExistence(timeout: 5) {
            sleepRing.tap()
            let naps = element(app, "sleep-naps")
            scrollTo(app, naps, near: 0.4)
            shot("76-sleep-naps")
            XCTAssertTrue(onScreen(app, naps), "no Naps section on the Sleep screen: \(describe(naps))")
        } else {
            XCTFail("missing ring-sleep")
        }

        app.tabBars.buttons["Coach"].tap()
        let input = element(app, "coach-input")
        guard input.waitForExistence(timeout: 5) else {
            XCTFail("missing coach-input")
            return
        }
        input.tap()
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else {
            // A simulator with a hardware keyboard attached never shows one.
            XCTFail("no keyboard appeared after tapping the Coach's text field")
            return
        }
        app.typeText("Hi")
        shot("74-coach-keyboard")
        // The "Your coach" heading: not a button.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)).tap()
        sleep(1)
        shot("75-coach-keyboard-hidden")
        XCTAssertFalse(keyboard.exists, "tapping outside the text field did not hide the keyboard")

        app.terminate()
    }

    /// A sideways swipe on Today changes the day, the bedtime reminder turns on once iOS asks,
    /// and Home at extra-large text, where the cards grow rather than cut text off.
    func test06DaysRemindersLargeText() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        if let outDir { app.launchEnvironment["FITSTATS_DEBUG_LOG"] = outDir.appendingPathComponent("app-log.txt").path }
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        // To the right: the day before. To the left: back to today.
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.6))
        left.press(forDuration: 0.05, thenDragTo: left.withOffset(CGVector(dx: 230, dy: 0)),
                   withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
        shot("77-day-swiped")
        XCTAssertTrue(app.staticTexts["Yesterday"].waitForExistence(timeout: 3), "a swipe to the right did not open yesterday")
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.6))
        right.press(forDuration: 0.05, thenDragTo: right.withOffset(CGVector(dx: -230, dy: 0)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
        XCTAssertFalse(app.staticTexts["Yesterday"].exists, "a swipe to the left did not come back to today")

        // The bedtime reminder: iOS asks first.
        app.tabBars.buttons["Settings"].tap()
        let toggle = app.switches["toggle-reminders.bedtime"]
        for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { app.swipeUp() }
        if toggle.exists, toggle.isHittable {
            // On the switch itself: the element is the whole row, and a tap on its label does
            // nothing (the last run tapped the middle and the switch never moved).
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
            if allow.waitForExistence(timeout: 5) { allow.tap() }
            sleep(2)
            shot("78-reminders-on")
            XCTAssertEqual(toggle.value as? String, "1", "the bedtime reminder did not stay on")
        } else {
            XCTFail("missing the bedtime reminder switch")
        }
        app.terminate()

        // Extra-large text (Settings → Display & Brightness → Text Size, the largest without
        // Larger Accessibility Sizes): the default Home, then every card.
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        for (cards, first) in [("", 79), ("all", 83)] {
            app.launchEnvironment["FITSTATS_HOME_CARDS"] = cards.isEmpty ? nil : cards
            app.launch()
            XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today (XXXL) did not load")
            sleep(1)
            shot("\(first)-home-xxxl")
            for index in 1...3 {
                app.swipeUp()
                shot("\(first + index)-home-xxxl-\(index + 1)")
            }
            app.terminate()
        }
    }

    /// The Training tab: a routine, logging it set by set and saving it, a new routine, and an
    /// "Ask coach" button that opens the Coach with the question typed in.
    func test07Training() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        if let outDir { app.launchEnvironment["FITSTATS_DEBUG_LOG"] = outDir.appendingPathComponent("app-log.txt").path }
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        app.tabBars.buttons["Training"].tap()
        let legs = app.buttons["routine-Legs"]
        guard legs.waitForExistence(timeout: 5) else {
            XCTFail("no Legs routine in Training")
            return
        }
        shot("90-training")
        app.swipeUp()
        shot("91-training-2")
        app.swipeUp()
        shot("92-training-3")
        for _ in 0..<4 { app.swipeDown() }

        // Legs (done 3 times in the fixtures), then logging it.
        scrollTo(app, legs)
        legs.tap()
        let start = app.buttons["routine-start"]
        guard start.waitForExistence(timeout: 5) else {
            XCTFail("missing routine-start")
            return
        }
        shot("93-routine")
        start.tap()
        let firstDone = app.buttons["set-1-done"].firstMatch
        guard firstDone.waitForExistence(timeout: 5) else {
            XCTFail("the workout logger did not open")
            return
        }
        shot("94-logger")
        firstDone.tap()
        let kg = app.textFields["set-2-kg"].firstMatch
        if kg.waitForExistence(timeout: 3) {
            // At its right edge, so the cursor goes after the weight already in it.
            kg.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            kg.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "85")
            // What the field reports can lag a moment behind the typing.
            let took = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "85"), object: kg)
            if XCTWaiter.wait(for: [took], timeout: 3) != .completed {
                XCTFail("the weight field didn't take 85: \(kg.value ?? "nil")")
            }
            let done = app.toolbars.buttons["Done"].firstMatch
            if done.exists { done.tap() }
        } else {
            XCTFail("missing set-2-kg")
        }
        app.buttons["set-2-done"].firstMatch.tap()
        shot("95-logger-sets")
        // The weight typed counts, not only shows: 5 × 80 + 5 × 85.
        XCTAssertTrue(app.staticTexts["825 kg"].waitForExistence(timeout: 3), "the typed weight didn't reach the workout (no 825 kg)")

        app.buttons["logger-finish"].tap()
        let effort = app.buttons["effort-7"]
        guard effort.waitForExistence(timeout: 5) else {
            XCTFail("the finish sheet did not open")
            return
        }
        effort.tap()
        shot("96-finish")
        app.buttons["finish-save"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5), "saving did not close the logger")
        XCTAssertTrue(app.staticTexts["DONE 4 TIMES"].waitForExistence(timeout: 5), "the saved workout is not with the routine")
        shot("97-routine-logged")

        // The saved workout's own screen.
        let saved = app.buttons["history-log"].firstMatch
        back(app)
        scrollTo(app, saved)
        if saved.exists {
            saved.tap()
            sleep(1)
            shot("98-log-detail")
            app.swipeUp()
            shot("99-log-detail-2")
            back(app)
        } else {
            XCTFail("no logged workout in the history")
        }

        // A new routine with one exercise.
        for _ in 0..<6 { app.swipeDown() }
        app.buttons["training-new-routine"].tap()
        let name = app.textFields["routine-name"]
        guard name.waitForExistence(timeout: 5) else {
            XCTFail("the routine editor did not open")
            return
        }
        name.tap()
        name.typeText("Push day")
        // Add exercise opens the library: find Dips, then its targets.
        app.buttons["routine-add-exercise"].tap()
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Dips")
            let dips = app.buttons["library-Dips"]
            if dips.waitForExistence(timeout: 5) {
                shot("100-exercise-picker")
                dips.tap()
            } else {
                XCTFail("Dips is not in the library search")
            }
        } else {
            XCTFail("the exercise library did not open")
        }
        let exercise = app.textFields["exercise-name"]
        if exercise.waitForExistence(timeout: 5) {
            XCTAssertEqual(exercise.value as? String, "Dips")
            shot("100-exercise-editor")
            // The sheet's own back button (the Training screen's bar is still there under the sheet).
            app.navigationBars["Dips"].buttons.element(boundBy: 0).tap()
        } else {
            XCTFail("the exercise editor did not open")
        }
        shot("101-routine-editor")
        app.buttons["routine-save"].tap()
        XCTAssertTrue(app.buttons["routine-Push day"].waitForExistence(timeout: 5), "the new routine is not in Training")

        // "Make me a routine" opens the Coach and sends it at once.
        let ask = app.buttons["ask-coach-Make me a routine"]
        scrollTo(app, ask)
        ask.tap()
        let sent = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Make me a routine")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 5), "the question wasn't sent to the coach")
        shot("102-ask-coach")
        app.terminate()
    }

    /// The three coaches and their picker, a screenshot in a conversation, the muscles card,
    /// the exercise library and an exercise's page, and a routine's muscles.
    func test08CoachesAndMuscles() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        // The coach is chosen in Settings → Coach.
        func pick(_ persona: String, shotName: String?) {
            app.tabBars.buttons["Settings"].tap()
            let row = app.buttons["settings-coach"]
            for _ in 0..<8 where !(row.exists && row.isHittable) { app.swipeUp() }
            guard row.exists, row.isHittable else {
                XCTFail("missing the coach row in Settings")
                return
            }
            row.tap()
            let card = app.buttons["coach-pick-\(persona)"]
            guard card.waitForExistence(timeout: 5) else {
                XCTFail("the coach picker did not open")
                return
            }
            if let shotName { shot(shotName) }
            card.tap()
            app.tabBars.buttons["Coach"].tap()
        }
        pick("ace", shotName: "103-coach-picker")
        XCTAssertTrue(app.staticTexts["Ace"].waitForExistence(timeout: 5), "picking Ace didn't change the coach")
        XCTAssertFalse(app.buttons["coach-switch"].exists, "the Coach screen still has a switch button")
        shot("104-coach-ace")
        pick("kai", shotName: nil)
        XCTAssertTrue(app.staticTexts["Kai"].waitForExistence(timeout: 5))
        shot("105-coach-kai")
        // Back to Nova for the other tests.
        pick("nova", shotName: nil)
        XCTAssertTrue(app.staticTexts["Nova"].waitForExistence(timeout: 5))

        // The fixture conversation has a screenshot in it.
        app.buttons["coach-history"].tap()
        let thread = app.buttons["coach-thread"].firstMatch
        if thread.waitForExistence(timeout: 5) {
            thread.tap()
            let thumbs = element(app, "coach-attachments")
            XCTAssertTrue(thumbs.waitForExistence(timeout: 5), "the screenshot isn't in the conversation")
            scrollTo(app, thumbs)
            shot("106-coach-screenshot")
            app.buttons["New conversation"].tap()
        } else {
            XCTFail("no coach conversation in the history sheet")
        }

        // Training: muscles of the last 7 days, the library, an exercise.
        app.tabBars.buttons["Training"].tap()
        let card = element(app, "muscles-week")
        guard card.waitForExistence(timeout: 5) else {
            XCTFail("missing the muscles card")
            return
        }
        reveal(app, card)
        shot("107-muscles-week")
        let library = app.buttons["training-library"]
        if library.exists {
            library.tap()
            sleep(1)
            shot("108-library")
            // The list only builds rows near the screen: find Squat by searching.
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 5) {
                search.tap()
                search.typeText("Squat")
            }
            let squat = app.buttons["library-Squat"]
            if squat.waitForExistence(timeout: 5) {
                shot("108-library-search")
                squat.tap()
                XCTAssertTrue(element(app, "body-map").waitForExistence(timeout: 5))
                shot("109-exercise-squat")
                app.swipeUp()
                shot("110-exercise-squat-2")
                back(app)
            } else {
                XCTFail("Squat is not in the library")
            }
            // The open search hides the back button: close it first.
            let cancel = app.navigationBars.buttons["Cancel"]
            if cancel.waitForExistence(timeout: 2) { cancel.tap() }
            back(app)
        } else {
            XCTFail("missing the library link")
        }
        for _ in 0..<6 { app.swipeDown() }
        let legs = app.buttons["routine-Legs"]
        scrollTo(app, legs)
        legs.tap()
        let muscles = element(app, "workout-muscles")
        if muscles.waitForExistence(timeout: 5) {
            reveal(app, muscles)
            shot("111-routine-muscles")
        } else {
            XCTFail("the routine has no muscles card")
        }
        app.terminate()
    }

    /// Wake-up times set by hand: Monday on and copied to the other weekdays, Saturday later,
    /// Sunday free; saved, they show in Settings.
    func test09WakeTimes() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        app.tabBars.buttons["Settings"].tap()
        let row = app.buttons["settings-wake-times"]
        for _ in 0..<8 where !(row.exists && row.isHittable) { app.swipeUp() }
        guard row.exists, row.isHittable else {
            XCTFail("missing the wake-up times row in Settings")
            return
        }
        row.tap()
        let monday = app.switches["wake-toggle-0"]
        guard monday.waitForExistence(timeout: 5) else {
            XCTFail("the wake-up times screen did not open")
            return
        }
        shot("112-wake-times-empty")
        // On the switch itself (see test05's reminder switch).
        func flip(_ toggle: XCUIElement) { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        flip(monday)
        XCTAssertEqual(monday.value as? String, "1", "Monday's wake-up time did not switch on")
        XCTAssertTrue(element(app, "wake-time-0").waitForExistence(timeout: 3), "no time to set for Monday")
        app.buttons["wake-copy-weekdays"].tap()
        flip(app.switches["wake-toggle-5"])
        XCTAssertEqual(app.switches["wake-toggle-4"].value as? String, "1", "Monday's time wasn't copied to Friday")
        shot("113-wake-times-set")
        let save = app.buttons["wake-save"]
        for _ in 0..<4 where !(save.exists && save.isHittable) { app.swipeUp() }
        shot("114-wake-times-saving")
        save.tap()
        // The button says "Saved" once the times are saved.
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Saved"), object: save)
        if XCTWaiter.wait(for: [saved], timeout: 4) != .completed {
            XCTFail("saving the wake-up times didn't finish: button \(save.isEnabled ? "enabled" : "disabled"), value \(save.value ?? "nil")")
        }
        back(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let summary = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Mon–")).firstMatch
        XCTAssertTrue(row.label.contains("Mon–") || summary.waitForExistence(timeout: 3), "the saved wake-up times aren't in Settings: \(row.label)")
        shot("115-settings-wake-times")
        app.terminate()
    }

    /// A coach tab under a Home card sends its question at once: the coach thinks, then talks
    /// while the (sample) answer streams in. A workout file in a conversation.
    func test10CoachTabs() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        let tab = app.buttons["coach-tab"].firstMatch
        guard tab.waitForExistence(timeout: 5) else {
            XCTFail("no coach tab under a Home card")
            return
        }
        scrollTo(app, tab, near: 0.6)
        shot("116-home-coach-tab")
        tab.tap()
        let sent = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "About my scores")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 5), "the card's question wasn't sent")
        shot("117-coach-thinking")
        let answer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "This is a sample answer")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 6), "no answer came in")
        shot("118-coach-talking")
        sleep(4)
        shot("119-coach-answered")
        XCTAssertFalse(app.staticTexts["Thinking…"].exists, "the thinking row is still there after the answer")

        // The fixture conversation ends with a workout file.
        app.buttons["coach-history"].tap()
        let thread = app.buttons["coach-thread"].firstMatch
        if thread.waitForExistence(timeout: 5) {
            thread.tap()
            sleep(1)
            app.swipeUp()
            shot("120-coach-file")
        } else {
            XCTFail("no coach conversation in the history sheet")
        }
        XCTAssertTrue(app.buttons["coach-attach-file"].exists, "no file button in the composer")
        app.terminate()
    }

    /// The sync line on Today, the bedtime consistency chart, the weekly summary and its reminder,
    /// and a logged workout with the band's recording of it.
    func test11WeekAndSleep() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")
        XCTAssertTrue(element(app, "today-sync-status").exists, "no sync status at the top of Today")
        shot("121-today-sync-line")

        app.buttons["ring-sleep"].tap()
        let consistency = element(app, "bedtime-consistency")
        for _ in 0..<8 where !onScreen(app, consistency) { app.swipeUp() }
        XCTAssertTrue(consistency.exists, "no bedtime consistency chart on the Sleep screen")
        scrollTo(app, consistency, near: 0.5)
        shot("122-bedtime-consistency")
        back(app)

        app.tabBars.buttons["Coach"].tap()
        let weekly = element(app, "coach-weekly")
        for _ in 0..<6 where !onScreen(app, weekly) { app.swipeUp() }
        XCTAssertTrue(weekly.exists, "no weekly summary card on the Coach screen")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Next week")).firstMatch.exists, "the fixture summary isn't shown")
        reveal(app, weekly)
        shot("123-coach-weekly")

        app.tabBars.buttons["Settings"].tap()
        let toggle = app.switches["toggle-reminders.weekly"]
        for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { app.swipeUp() }
        XCTAssertTrue(toggle.exists, "no weekly summary reminder in Settings")

        // The fixtures' Upper body A on a Wednesday overlaps the band's run that day: one row.
        app.tabBars.buttons["Training"].tap()
        let log = app.buttons.matching(identifier: "history-log").matching(NSPredicate(format: "label CONTAINS %@", "Logged + band")).firstMatch
        scrollTo(app, log)
        if log.exists {
            shot("124-history-paired")
            log.tap()
            let band = element(app, "log-band-workout")
            XCTAssertTrue(band.waitForExistence(timeout: 5), "the logged workout doesn't show the band's recording")
            scrollTo(app, band, near: 0.4)
            shot("125-log-with-band")
        } else {
            XCTFail("no logged workout paired with a band workout in the history")
        }
        app.terminate()
    }

    /// The Body age tab: the number, a factor opened, what would lower it, the history and the method.
    func test13BodyAge() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        app.tabBars.buttons["Body age"].tap()
        let hero = element(app, "bodyage-hero")
        XCTAssertTrue(hero.waitForExistence(timeout: 5), "no body age in the fixtures")
        XCTAssertTrue(hero.label.contains("years"), "body age hero: \(hero.label)")
        sleep(2)
        shot("131-body-age")
        let fitness = app.buttons["bodyage-factor-fitness"]
        for _ in 0..<4 where !(fitness.exists && fitness.isHittable) { app.swipeUp() }
        if fitness.waitForExistence(timeout: 3) {
            fitness.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Source:")).firstMatch.waitForExistence(timeout: 3),
                          "the fitness factor didn't open")
            shot("132-body-age-factor")
        } else {
            XCTFail("missing the fitness factor")
        }
        app.swipeUp()
        shot("133-body-age-2")
        let method = app.buttons["bodyage-method"]
        for _ in 0..<4 where !(method.exists && method.isHittable) { app.swipeUp() }
        shot("134-body-age-3")
        guard method.exists, method.isHittable else {
            XCTFail("missing How it's calculated")
            return
        }
        method.tap()
        XCTAssertTrue(app.navigationBars["How it's calculated"].waitForExistence(timeout: 5))
        shot("135-body-age-method")
        app.swipeUp()
        shot("136-body-age-method-2")
        back(app)

        // The questions, from Edit your answers.
        let edit = app.buttons["bodyage-edit-answers"]
        for _ in 0..<4 where !(edit.exists && edit.isHittable) { app.swipeUp() }
        guard edit.exists, edit.isHittable else {
            XCTFail("missing Edit your answers")
            return
        }
        edit.tap()
        XCTAssertTrue(app.buttons["q-smoking-never"].waitForExistence(timeout: 5), "the questions didn't open")
        app.buttons["q-smoking-former"].tap()
        XCTAssertTrue(app.buttons["q-quit-under40"].waitForExistence(timeout: 3), "no quit-age question for former smokers")
        shot("137-body-age-questions")
        app.buttons["q-quit-under40"].tap()
        app.buttons["q-save"].tap()
        XCTAssertTrue(element(app, "bodyage-hero").waitForExistence(timeout: 5), "saving the answers didn't close the sheet")
        app.terminate()
    }

    /// Settings → Widgets: the widget previews with today's numbers and the sharing status.
    func test12Widgets() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        app.tabBars.buttons["Settings"].tap()
        let row = app.buttons["settings-widgets"]
        for _ in 0..<8 where !(row.exists && row.isHittable) { app.swipeUp() }
        guard row.exists, row.isHittable else {
            XCTFail("missing the widgets row in Settings")
            return
        }
        row.tap()
        XCTAssertTrue(element(app, "widget-previews").waitForExistence(timeout: 5), "the widgets screen did not open")
        shot("126-widgets-small")
        app.swipeUp()
        shot("127-widgets-small-2")
        // The other sizes, from the switch at the top.
        for (size, name) in [("Medium", "128-widgets-medium"), ("Large", "130-widgets-large")] {
            let segment = app.segmentedControls.buttons[size]
            for _ in 0..<4 where !(segment.exists && segment.isHittable) { app.swipeDown() }
            guard segment.exists, segment.isHittable else {
                XCTFail("no \(size) button on the widgets screen")
                return
            }
            segment.tap()
            shot(name)
            app.swipeUp()
            shot(name + "-2")
            app.swipeUp()
            shot(name + "-3")
        }
        let sharing = element(app, "widget-sharing")
        for _ in 0..<4 where !(sharing.exists && sharing.isHittable) { app.swipeUp() }
        XCTAssertTrue(sharing.waitForExistence(timeout: 5), "no sharing status")
        XCTAssertTrue(sharing.label.contains("Working"), "sharing status: \(sharing.label)")
        app.terminate()
    }

    /// Training load and best bedtime on Insights, the calendar and compare periods from Trends,
    /// and a workout's heart-rate recovery.
    func test04InsightsPack() {
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        XCTAssertFalse(fixtures.isEmpty, "FITSTATS_FIXTURES is not set")
        let app = XCUIApplication()
        app.launchEnvironment["FITSTATS_FIXTURES"] = fixtures
        app.launch()
        XCTAssertTrue(app.buttons["ring-recovery"].waitForExistence(timeout: 15), "Today screen did not load")

        openTrends(app)
        let insights = app.buttons["open-insights"]
        if insights.waitForExistence(timeout: 5) {
            insights.tap()
            for (id, name) in [("training-load", "40-insights-load"), ("bedtime-card", "41-insights-bedtime")] {
                let card = element(app, id)
                if card.waitForExistence(timeout: 5) {
                    reveal(app, card)
                    shot(name)
                } else {
                    XCTFail("missing \(id)")
                }
            }
            back(app)
        } else {
            XCTFail("missing open-insights")
        }

        for (button, screen, name) in [("open-calendar", "calendar-heatmap", "42-calendar"), ("open-compare", "compare-periods", "43-compare")] {
            let link = app.buttons[button]
            guard link.waitForExistence(timeout: 5) else {
                XCTFail("missing \(button)")
                continue
            }
            link.tap()
            XCTAssertTrue(element(app, screen).waitForExistence(timeout: 5), "\(screen) did not open")
            shot(name)
            back(app)
        }
        closeTrends(app)

        // The nearest day with a workout, then its heart-rate recovery card.
        app.tabBars.buttons["Today"].tap()
        let workout = app.buttons["workout-row"].firstMatch
        for _ in 0..<6 where !workout.exists {
            app.buttons["Previous day"].tap()
            sleep(1)
        }
        guard workout.exists else {
            XCTFail("no workout in the last 7 days of fixtures")
            return
        }
        for _ in 0..<6 where !workout.isHittable { app.swipeUp() }
        workout.tap()
        let recovery = element(app, "hr-recovery")
        if recovery.waitForExistence(timeout: 5) {
            reveal(app, recovery)
            shot("44-workout-hrr")
        } else {
            XCTFail("missing hr-recovery")
        }
        back(app)
    }
}
