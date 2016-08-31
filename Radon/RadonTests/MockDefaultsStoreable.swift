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
    
    private var store: [String:AnyObject] = [:]
    
    func loadObjectForKey(key: String) -> AnyObject? {
        return store[key]
    }
    
    func saveObject(object: AnyObject?, forKey key: String) {
        store[key] = object
    }
}