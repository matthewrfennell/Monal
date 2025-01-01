//
//  MLPromise.swift
//  monalxmpp
//
//  Created by Matthew Fennell on 29/12/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import Foundation
import PromiseKit

private enum State {
    case unresolved
    case fulfilled(argument: Any?)
    case rejected(error: NSError, node: XMPPStanza?, accountID: NSNumber?)
}

@objcMembers
public class MLPromise : NSObject {
    private static var _resolvers: Dictionary<String, ((Any) -> ())> = Dictionary();

    public let uuid = UUID().uuidString;

    private var state: State = .unresolved;
    private var anyPromise: Promise<Any>? = nil;
    private var isStale = false
    
    public override init() {
        super.init()
        self.serialize()
        NotificationCenter.default.addObserver(self, selector: #selector(self.deserialize), name: NSNotification.Name("kMonalUnfrozen"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func fulfill(_ arg: Any?) {
        resolve(withState: .fulfilled(argument: arg))
    }

    public func reject(_ error: NSError) {
        resolve(withState: .rejected(error: error, node: nil, accountID: nil))
    }

    public func toAnyPromise() -> AnyPromise {
        if let promise = self.anyPromise {
            return AnyPromise(promise)
        }
        self.anyPromise = Promise { seal in
            Self._resolvers[self.uuid] = seal.fulfill
        }
        return AnyPromise(anyPromise!)
    }

    public static func consumeStalePromises() {
        
    }

    private func resolve(withState state: State) {
        self.state = state
        self.serialize()
        self.attemptConsume()
    }
    
    private func attemptConsume() {

    }

    private func serialize() {
        MLDataLayer.sharedInstance().add(self)
    }

    @objc private func deserialize() {
        
    }
}
