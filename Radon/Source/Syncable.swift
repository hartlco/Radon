//
//  Syncable.swift
//  Radon
//
//  Created by Martin Hartl on 25/08/16.
//  Copyright © 2016 Martin Hartl. All rights reserved.
//

public protocol Syncable {
    static func propertyNamesToSync() -> [String]
}
