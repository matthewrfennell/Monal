//
//  MonalUITests.swift
//  MonalUITests
//
//  Created by Friedrich Altheide on 06.03.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

import XCTest

class MonalUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["MONAL_UI_TESTS_USE_REAL_SERVER"] == "YES" || ProcessInfo.processInfo.environment["CI"] == "true" else {
            throw XCTSkip("""
                Set MONAL_UI_TESTS_USE_REAL_SERVER to YES to run these tests.
                The UI tests run against a real remote server; to avoid exposing your IP without your consent, they are disabled by default.
                For XCode, go to Monal -> Edit Scheme -> Test -> Arguments -> Environment Variables and set MONAL_UI_TESTS_USE_REAL_SERVER to YES.
                For xcodebuild, set the environment variable MONAL_UI_TESTS_USE_REAL_SERVER=YES.
                """)
        }
    }

    let server = "ephemeral-xmpp-server.org"

}
