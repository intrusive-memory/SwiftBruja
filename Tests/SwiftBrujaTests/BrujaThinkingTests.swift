import XCTest

@testable import SwiftBruja

final class BrujaThinkingTests: XCTestCase {

  func testModelDefaultPassesNoAdditionalContext() {
    XCTAssertNil(BrujaThinking.modelDefault.additionalContext)
  }

  func testOffPassesEnableThinkingFalse() throws {
    let context = try XCTUnwrap(BrujaThinking.off.additionalContext)
    XCTAssertEqual(context.count, 1)
    XCTAssertEqual(context["enable_thinking"] as? Bool, false)
  }
}
