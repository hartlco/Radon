//
//  MockDefaultsStoreable.swift
//  Radon
//
//  Created by mhaddl on 08/05/16.
//  Copyright © 2016 Martin Hartl. All rights reserved.
//

import Foundation
@testable import Radon_iOS

class MockDefaultsStoreable: DefaultsStoreable {
    
    fileprivate var store: [String:Any] = [:]
    
    func loadObjectForKey(_ key: String) -> Any? {
        return store[key]
    }
    
    func saveObject(_ object: Any?, forKey key: String) {
        store[key] = object
    }
}
