//
//  Tests_macOS.swift
//  Tests macOS
//
//  Created by Arkadiusz Fal on 09/06/2021.
//

import XCTest

class Tests_macOS: XCTestCase {
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
