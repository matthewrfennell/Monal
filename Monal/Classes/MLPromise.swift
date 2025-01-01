//
//  MLPromise.swift
//  monalxmpp
//
//  Created by Matthew Fennell on 01/01/2025.
//  Copyright © 2025 monal-im.org. All rights reserved.
//

import Foundation
import PromiseKit

@objcMembers
public class MLPromise : NSObject {
    public let uuid: NSUUID = NSUUID()

    public func fulfill(_ argument: Any?) {}

    public func reject(_ argument: Any?) {}

    public func toAnyPromise() -> AnyPromise {
        let promise = Promise<Any> { seal in }
        return AnyPromise(promise)
    }

    public static func removeStalePromises() {}

    private func serialize() {
        DataLayer.sharedInstance().add(self)
    }
}
