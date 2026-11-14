import XCTest

final class CinueUITests: XCTestCase {
    private let defaultTimeout: TimeInterval = 5
    private let stateTransitionTimeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchShowsMainTabs() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(tabExists("Now", in: app, timeout: 5))
        XCTAssertTrue(tabExists("Library", in: app))
        XCTAssertTrue(tabExists("Discover", in: app))
        XCTAssertTrue(tabExists("Lists", in: app))
        XCTAssertTrue(tabExists("Settings", in: app))
    }

    @MainActor
    func testSeededNowLibraryAndDetailActionsWork() throws {
        let app = seededApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Altered Carbon"].waitForExistence(timeout: defaultTimeout))

        tapButton(labelBeginning: "Mark 1x02 Fallen Angel watched", in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Mark 1x03 Fresh Upload watched")).firstMatch.waitForExistence(timeout: stateTransitionTimeout))

        tapButton(labelBeginning: "Recently Watched,", in: app)
        XCTAssertTrue(app.staticTexts["Recently Watched"].waitForExistence(timeout: defaultTimeout))

        tapButton(labelBeginning: "Recently Aired,", in: app)
        XCTAssertTrue(app.staticTexts["Recently Aired"].waitForExistence(timeout: defaultTimeout))

        tapButton(labelBeginning: "Upcoming,", in: app)
        XCTAssertTrue(app.staticTexts["Upcoming"].waitForExistence(timeout: defaultTimeout))

        tapButton(labelBeginning: "Up Next,", in: app)
        XCTAssertTrue(app.staticTexts["Up Next"].waitForExistence(timeout: defaultTimeout))

        tapTab("Library", in: app)
        XCTAssertTrue(app.staticTexts["Altered Carbon"].waitForExistence(timeout: defaultTimeout))

        tapButton(labelBeginning: "Sort by", in: app)
        tapButton(exactLabel: "Release", in: app)

        tapButton(labelBeginning: "Favorites,", in: app)
        XCTAssertTrue(app.staticTexts["Altered Carbon"].waitForExistence(timeout: defaultTimeout))

        tapButton(labelBeginning: "All,", in: app)
        XCTAssertTrue(app.staticTexts["Altered Carbon"].waitForExistence(timeout: defaultTimeout))

        tapButton(labelBeginning: "Movies,", in: app)
        XCTAssertTrue(app.staticTexts["(500) Days of Summer"].waitForExistence(timeout: defaultTimeout))

        tapButton(labelBeginning: "Unwatched,", in: app)
        XCTAssertTrue(app.staticTexts["(500) Days of Summer"].waitForExistence(timeout: defaultTimeout))

        tapButton(labelBeginning: "Watched,", in: app)
        XCTAssertTrue(app.staticTexts["Altered Carbon"].waitForExistence(timeout: defaultTimeout))

        tapButton(labelBeginning: "Shows,", in: app)
        XCTAssertTrue(app.staticTexts["Altered Carbon"].waitForExistence(timeout: defaultTimeout))

        tapButton(exactLabel: "More actions", in: app)
        tapButton(exactLabel: "Remove from Favorites", in: app)

        app.staticTexts["Altered Carbon"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Altered Carbon"].waitForExistence(timeout: defaultTimeout))

        tapButton(labelBeginning: "Add to Favorites", in: app, timeout: stateTransitionTimeout)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove from Favorites")).firstMatch.waitForExistence(timeout: stateTransitionTimeout))

        tapButton(labelBeginning: "Hide from Library", in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Show in Library")).firstMatch.waitForExistence(timeout: stateTransitionTimeout))

        tapTab("Library", in: app)
        tapButton(labelBeginning: "Hidden,", in: app)
        XCTAssertTrue(app.staticTexts["Altered Carbon"].waitForExistence(timeout: defaultTimeout))
        tapButton(exactLabel: "More actions", in: app)
        tapButton(exactLabel: "Show in Library", in: app)
        XCTAssertTrue(app.staticTexts["Altered Carbon"].waitForNonExistence(timeout: stateTransitionTimeout))
        tapButton(labelBeginning: "Shows,", in: app)
        XCTAssertTrue(app.staticTexts["Altered Carbon"].waitForExistence(timeout: stateTransitionTimeout))
    }

    @MainActor
    func testSeededEpisodeDetailOffersNextEpisodeAfterMarkingWatched() throws {
        let app = seededApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Altered Carbon"].waitForExistence(timeout: defaultTimeout))
        tapButton(labelBeginning: "Altered Carbon", in: app)
        XCTAssertTrue(app.staticTexts["1x02 Fallen Angel"].waitForExistence(timeout: defaultTimeout))

        tapButton(exactLabel: "Mark Watched", in: app)
        tapButton(exactLabel: "View Next Episode", in: app)
        XCTAssertTrue(app.staticTexts["1x03 Fresh Upload"].waitForExistence(timeout: defaultTimeout))
    }

    @MainActor
    func testSeededDiscoverSearchPreviewAndAddActionsWork() throws {
        let app = seededApp()
        app.launch()

        tapTab("Discover", in: app)
        let searchField = app.textFields["Search movies and shows"]
        XCTAssertTrue(searchField.waitForExistence(timeout: defaultTimeout))
        searchField.tap()
        searchField.typeText("Severance\n")

        XCTAssertTrue(app.staticTexts["Severance"].waitForExistence(timeout: defaultTimeout))

        app.staticTexts["Fight Club"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Add"].waitForExistence(timeout: defaultTimeout))
        tapButton(exactLabel: "Add to Watchlist", in: app)
        XCTAssertTrue(app.buttons["On Watchlist"].waitForExistence(timeout: stateTransitionTimeout))
        tapButton(exactLabel: "Done", in: app)

        tapButton(exactLabel: "Add to Library", in: app)
        XCTAssertTrue(app.buttons["Add to Library"].waitForNonExistence(timeout: stateTransitionTimeout))

        tapButton(exactLabel: "Clear search", in: app)
        XCTAssertTrue(app.staticTexts["Search by title to add it to your library or watchlist."].waitForExistence(timeout: defaultTimeout))

        tapTab("Library", in: app)
        XCTAssertTrue(app.staticTexts["Severance"].waitForExistence(timeout: defaultTimeout))
    }

    @MainActor
    func testSeededDiscoverBrowseCategoriesShowExpectedResults() throws {
        let app = seededApp()
        app.launch()

        tapTab("Discover", in: app)
        XCTAssertTrue(app.textFields["Search movies and shows"].waitForExistence(timeout: defaultTimeout))

        tapButton(exactLabel: "Popular Shows", in: app)
        XCTAssertTrue(app.staticTexts["Severance"].waitForExistence(timeout: defaultTimeout))

        tapButton(exactLabel: "Popular Movies", in: app)
        XCTAssertTrue(waitForDiscoverResult("Fight Club", in: app))

        tapButton(exactLabel: "Upcoming Movies", in: app)
        XCTAssertTrue(waitForDiscoverResult("Fight Club", in: app))
    }

    @MainActor
    func testSeededListsCreateRenameDeleteAndRemoveActionsWork() throws {
        let app = seededApp()
        app.launch()

        tapTab("Lists", in: app)
        XCTAssertTrue(app.staticTexts["Weekend"].waitForExistence(timeout: defaultTimeout))
        XCTAssertTrue(app.staticTexts["Altered Carbon"].waitForExistence(timeout: defaultTimeout))

        tapButton(exactLabel: "More actions", in: app)
        tapButton(exactLabel: "Remove from List", in: app)
        XCTAssertTrue(app.staticTexts["Altered Carbon"].waitForNonExistence(timeout: stateTransitionTimeout))
        XCTAssertTrue(app.staticTexts["Weekend"].exists)

        tapButton(exactLabel: "Create list", in: app)
        let newListAlert = app.alerts["New List"]
        XCTAssertTrue(newListAlert.waitForExistence(timeout: defaultTimeout))
        newListAlert.textFields["List name"].tap()
        newListAlert.textFields["List name"].typeText("Road Trip")
        newListAlert.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Road Trip"].waitForExistence(timeout: stateTransitionTimeout))
        XCTAssertTrue(app.staticTexts["List created."].waitForNonExistence(timeout: stateTransitionTimeout))

        tapButton(exactLabel: "Manage list", in: app)
        tapButton(exactLabel: "Rename", in: app)
        let renameAlert = app.alerts["Rename List"]
        XCTAssertTrue(renameAlert.waitForExistence(timeout: defaultTimeout))
        let renameField = renameAlert.textFields["List name"]
        renameField.tap()
        renameField.typeText(" Picks")
        renameAlert.buttons["Rename"].tap()
        XCTAssertTrue(app.staticTexts["Road Trip Picks"].waitForExistence(timeout: stateTransitionTimeout))
        XCTAssertFalse(app.staticTexts["Road Trip"].exists)
        XCTAssertTrue(app.staticTexts["List renamed."].waitForNonExistence(timeout: stateTransitionTimeout))

        tapButton(exactLabel: "Manage list", in: app)
        tapButton(exactLabel: "Delete", in: app)
        let deleteAlert = app.alerts["Delete List?"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: defaultTimeout))
        deleteAlert.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Road Trip Picks"].waitForNonExistence(timeout: stateTransitionTimeout))
        XCTAssertTrue(app.staticTexts["Weekend"].exists)
        tapTab("Library", in: app)
        XCTAssertTrue(app.staticTexts["Altered Carbon"].waitForExistence(timeout: stateTransitionTimeout))
    }

    @MainActor
    func testSeededSettingsNavigationAndProviderKeyActionsWork() throws {
        let app = seededApp()
        app.launch()

        tapTab("Settings", in: app)
        let routes = [
            ("Insights", "Insights"),
            ("Backup and Sync", "Backup and Sync"),
            ("Import and Export", "Import and Export"),
            ("Privacy", "Privacy"),
            ("Display", "Display"),
            ("Notifications", "Notifications"),
            ("Attribution", "Attribution"),
            ("Diagnostics", "Diagnostics"),
            ("About Cinue", "About Cinue")
        ]

        for route in routes {
            tapSettingsRoute(route.0, in: app)
            XCTAssertTrue(screenTitle(route.1, existsIn: app), "Missing screen title: \(route.1)")
            if route.0 == "Display" {
                let appearancePicker = app.segmentedControls["AppearanceModePicker"].firstMatch
                XCTAssertTrue(
                    appearancePicker.waitForExistence(timeout: defaultTimeout),
                    "Display settings should expose the System/Light/Dark appearance picker."
                )
            }
            tapTab("Settings", in: app)
        }

        tapSettingsRoute("Provider Keys", in: app)

        let tmdbField = app.secureTextFields["TMDB API key or read token"]
        XCTAssertTrue(tmdbField.waitForExistence(timeout: defaultTimeout))
        tmdbField.tap()
        tmdbField.typeText("ui-test-token")

        tapButton(exactLabel: "Save Credential", in: app)
        XCTAssertTrue(app.staticTexts["Configured"].waitForExistence(timeout: stateTransitionTimeout))

        let tmdbRemoveButton = app.buttons["Remove"].firstMatch
        XCTAssertTrue(tmdbRemoveButton.waitForExistence(timeout: defaultTimeout))
        tmdbRemoveButton.tap()
        XCTAssertTrue(app.staticTexts["Not Configured"].waitForExistence(timeout: stateTransitionTimeout))

        tapTab("Settings", in: app)
        XCTAssertTrue(app.buttons["Insights"].waitForExistence(timeout: defaultTimeout))
    }

    @MainActor
    func testSettingsBottomRowsScrollClearOfCustomTabBar() throws {
        let app = seededApp()
        app.launch()

        tapTab("Settings", in: app)
        scrollToSettingsRoute("About Cinue", in: app)

        let aboutRow = app.buttons["About Cinue"].firstMatch
        XCTAssertTrue(aboutRow.waitForExistence(timeout: defaultTimeout))

        let tabBar = app.descendants(matching: .any)["CinueTabBar"].firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: defaultTimeout))

        for _ in 0..<6 where aboutRow.frame.maxY > tabBar.frame.minY - 12 {
            app.swipeUp()
        }

        XCTAssertLessThanOrEqual(
            aboutRow.frame.maxY,
            tabBar.frame.minY - 12,
            "Bottom Settings rows should scroll above the custom tab bar."
        )
    }

    @MainActor
    private func tabExists(_ title: String, in app: XCUIApplication, timeout: TimeInterval = 0) -> Bool {
        if app.buttons[title].waitForExistence(timeout: timeout) {
            return true
        }

        if app.staticTexts[title].waitForExistence(timeout: timeout) {
            return true
        }

        return app.cells.containing(.staticText, identifier: title).element.waitForExistence(timeout: timeout)
    }

    @MainActor
    private func seededApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--cinue-ui-test-seed")
        return app
    }

    @MainActor
    private func tapTab(_ title: String, in app: XCUIApplication) {
        if app.buttons["Tab-\(title.lowercased())"].waitForExistence(timeout: 1) {
            app.buttons["Tab-\(title.lowercased())"].tap()
            return
        }

        tapButton(exactLabel: title, in: app)
    }

    @MainActor
    private func tapButton(exactLabel label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: defaultTimeout), "Missing button: \(label)")
        button.tap()
    }

    @MainActor
    private func tapSettingsRoute(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        scrollToSettingsRoute(label, in: app)

        XCTAssertTrue(button.waitForExistence(timeout: defaultTimeout), "Missing settings route: \(label)")
        XCTAssertTrue(button.isHittable, "Settings route is not hittable: \(label)")
        button.tap()
    }

    @MainActor
    private func scrollToSettingsRoute(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        let tabBar = app.descendants(matching: .any)["CinueTabBar"].firstMatch

        for _ in 0..<3 where button.exists == false || button.isHittable == false {
            app.swipeDown()
        }

        for _ in 0..<8 where button.exists == false
            || button.isHittable == false
            || (tabBar.exists && button.frame.maxY > tabBar.frame.minY - 12) {
            app.swipeUp()
        }
    }

    @MainActor
    private func tapButton(
        labelBeginning prefix: String,
        in app: XCUIApplication,
        timeout: TimeInterval? = nil
    ) {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        let button = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(
            button.waitForExistence(timeout: timeout ?? defaultTimeout),
            "Missing button beginning with: \(prefix)"
        )
        button.tap()
    }

    @MainActor
    private func waitForDiscoverResult(_ title: String, in app: XCUIApplication) -> Bool {
        let result = app.staticTexts[title].firstMatch
        if result.waitForExistence(timeout: defaultTimeout), result.isHittable {
            return true
        }

        let results = app.collectionViews.firstMatch
        guard results.waitForExistence(timeout: defaultTimeout) else {
            return false
        }

        let dragStart = results.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        let dragEnd = results.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))

        for _ in 0..<3 {
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
            if result.waitForExistence(timeout: 1), result.isHittable {
                return true
            }
        }

        return false
    }

    @MainActor
    private func screenTitle(_ title: String, existsIn app: XCUIApplication) -> Bool {
        app.navigationBars[title].waitForExistence(timeout: defaultTimeout)
            || app.staticTexts[title].waitForExistence(timeout: 1)
    }
}
