import Testing
@testable import CinueFeature

struct CinueVisualSystemTests {
    @Test
    func acceptedScreenHeaderMetricsStayStable() {
        #expect(CinueScreenHeaderMetrics.canopyHeight == 176)
        #expect(CinueScreenHeaderMetrics.compactBottomSpacing == -56)
        #expect(CinueScreenHeaderMetrics.regularBottomSpacing == -28)
    }

    @Test
    func glassControlsPreserveMinimumTouchTargetsAndCurrentDetailActionHeight() {
        #expect(CinueGlassMetrics.minimumTouchTarget >= 44)
        #expect(CinueGlassMetrics.detailActionMinHeight == 48)
    }

    @Test
    func detailArtworkBackgroundStaysFullScreenAndVisiblyCinematic() {
        #expect(CinueArtworkBackgroundMetrics.usesFullScreenArtwork)
        #expect(CinueArtworkBackgroundMetrics.darkArtworkOpacity >= 0.82)
        #expect(CinueArtworkBackgroundMetrics.lightArtworkOpacity >= 0.46)
        #expect(CinueArtworkBackgroundMetrics.darkTopScrimOpacity <= 0.32)
        #expect(CinueArtworkBackgroundMetrics.darkBottomScrimOpacity <= 0.74)
    }

    @Test
    func tabBarUsesSingleGlassCapsuleWithFloatingIcons() {
        #expect(CinueTabBarMetrics.usesSingleGlassCapsule)
        #expect(CinueTabBarMetrics.usesFloatingIcons)
        #expect(CinueTabBarMetrics.usesTintedGlassCapsule)
        #expect(CinueTabBarMetrics.selectedStateUsesFloatingHalo)
        #expect(!CinueTabBarMetrics.selectedStateUsesIconPlate)
        #expect(CinueTabBarMetrics.iconPlateWidth == 0)
        #expect(CinueTabBarMetrics.selectedIndicatorHeight <= 4)
        #expect(CinueTabBarMetrics.minimumButtonHeight >= CinueGlassMetrics.minimumTouchTarget)
        #expect(CinueTabBarMetrics.unselectedIconMinimumOpacity >= 0.78)
    }

    @Test
    func aggressiveLiquidGlassAvoidsCharcoalCardsAndTiles() {
        #expect(CinueGlassSurfaceMetrics.contentSurfacesUseNativeLiquidGlass)
        #expect(CinueGlassSurfaceMetrics.darkSurfaceTintOpacity <= 0.10)
        #expect(CinueGlassSurfaceMetrics.darkElevatedSurfaceTintOpacity <= 0.12)
        #expect(CinueGlassSurfaceMetrics.darkReflectionOpacity <= 0.16)
        #expect(CinueIconMetrics.usesLiquidGlassPlates)
        #expect(CinueIconMetrics.darkPlateTintOpacity <= 0.10)
    }

    @Test
    func iPadSidebarUsesAppleLikeLiquidGlass() {
        #expect(CinueSidebarMetrics.usesLiquidGlassColumn)
        #expect(CinueSidebarMetrics.usesFullHeightMaterialColumn)
        #expect(!CinueSidebarMetrics.usesInsetRoundedPanel)
        #expect(CinueSidebarMetrics.usesGlassNavigationRows)
        #expect(CinueSidebarMetrics.selectedRowTintOpacity <= 0.10)
        #expect(CinueSidebarMetrics.darkPanelTintOpacity <= 0.08)
        #expect(CinueSidebarMetrics.darkPanelReflectionOpacity <= 0.14)
        #expect(CinueSidebarMetrics.minimumRowHeight >= CinueGlassMetrics.minimumTouchTarget)
    }

    @Test
    func listsScreenMatchesTopLevelPageLayoutRhythm() {
        #expect(CinueListsLayoutMetrics.usesSiblingHeaderAndScrollableBody)
        #expect(CinueListsLayoutMetrics.usesSummaryTileRow)
        #expect(!CinueListsLayoutMetrics.createActionIsInlineCommand)
        #expect(CinueListsLayoutMetrics.summaryTileCount == 4)
    }

    @Test
    func insightsScreenMatchesTopLevelPageLayoutRhythm() {
        #expect(CinueInsightsLayoutMetrics.usesSiblingHeaderAndScrollableBody)
        #expect(CinueInsightsLayoutMetrics.hidesSystemNavigationChrome)
        #expect(CinueInsightsLayoutMetrics.bodyTopPadding == CinueSpacing.lg)
    }
}
