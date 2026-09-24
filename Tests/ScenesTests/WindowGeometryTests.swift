import CoreGraphics
import Testing
@testable import Scenes

@Test func centeredFrameHandlesNonzeroDisplayOrigin() {
    let visibleFrame = CGRect(x: 1440, y: 25, width: 1920, height: 1055)

    let result = WindowGeometry.centeredFrame(in: visibleFrame)

    #expect(result == CGRect(x: 1728, y: 183.5, width: 1344, height: 738))
}
