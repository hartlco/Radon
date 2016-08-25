//
//  RadonStore.swift
//  Radon
//
//  Created by Martin Hartl on 25/08/16.
//  Copyright © 2016 Martin Hartl. All rights reserved.
//

import Foundation

public protocol RadonStore {
    associatedtype T:Syncable
    
    func allPropertiesForObject(object: T) -> [String:Any]
    func recordNameForObject(object: T) -> String?
    func newObject(newObjectBlock: ((newObject: T) -> (T))) -> () -> (T)
    
    /// local update, values come from user, local modification date needs to be updated
    func updateObject(objectUpdateBlock: () -> (T)) -> (() -> (T))
    func objectWithIdentifier(identifier: String?) -> T?
    func newObjectFromDictionary(dictionary: [String:Any]) -> T
    func deleteObject(object: T)
    func allUnsyncedObjects() -> [T]
    
    /// external update, new values come from server and need to update local model
    func updateObject(object: T, withDictionary dictionary: [String:Any])
    func setRecordName(recordName: String?, forObject object: T)
    func setSyncStatus(syncStatus: Bool, forObject object: T)
    func setModificationDate(modificationDate: NSDate?, forObject object: T)
    func modificationDateForObject(object: T) -> NSDate
}