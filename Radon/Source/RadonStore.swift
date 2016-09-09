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
    
    func allPropertiesForObject(_ object: T) -> [String:Any]
    func recordNameForObject(_ object: T) -> String?
    func newObject(_ newObjectBlock: @escaping ((_ newObject: T) -> (T))) -> () -> (T)
    
    /// local update, values come from user, local modification date needs to be updated
    func updateObject(_ objectUpdateBlock: @escaping () -> (T)) -> (() -> (T))
    func objectWithIdentifier(_ identifier: String?) -> T?
    func newObjectFromDictionary(_ dictionary: [String:Any]) -> T
    func deleteObject(_ object: T)
    func allUnsyncedObjects() -> [T]
    
    /// external update, new values come from server and need to update local model
    func updateObject(_ object: T, withDictionary dictionary: [String:Any])
    func setRecordName(_ recordName: String?, forObject object: T)
    func setSyncStatus(_ syncStatus: Bool, forObject object: T)
    func setModificationDate(_ modificationDate: Date?, forObject object: T)
    func modificationDateForObject(_ object: T) -> Date
}
