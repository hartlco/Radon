//
//  UserDefaultsRadonStore.swift
//  Radon
//
//  Created by Martin Hartl on 05/11/15.
//  Copyright © 2015 Martin Hartl. All rights reserved.
//

import Foundation
@testable import Radon_iOS

class ExampleRadonStore: RadonStore {
    
    typealias T = TestClass
    
    var internAllObjects = [T]()
    let storeKey = "radonObjects"
    let userDeaults = NSUserDefaults.standardUserDefaults()
    
    init() {
        let allObjects = [TestClass]()
        userDeaults.setObject(allObjects, forKey: storeKey)
        userDeaults.synchronize()
    }
    
    func allObjects() -> [T] {
        return internAllObjects
    }
    
    func recordNameForObject(object: T) -> String? {
        return object.internRecordID
    }
    
    func setRecordName(recordName: String?, forObject object: T) {
        object.internRecordID = recordName
    }
    
    func newObject(newObjectBlock: ((newObject: T) -> (T))) -> () -> (T) {
        return {
            srandom(UInt32(time(nil)))
            let newObject = TestClass(string: String(random()), int: random(), double: 323432.234)
            newObjectBlock(newObject: newObject)
            self.addObject(newObject)
            return newObject
        }
    }
    
    func updateObject(objectUpdateBlock: () -> (T)) -> (() -> (T)) {
        return {
            return objectUpdateBlock()
        }
    }
    
    func newObjectFromDictionary(dictionary: [String : Any]) -> T {
        let newObject = T(dictionary: dictionary)
        guard let object = newObject else { fatalError("Can't initializes object from dictionary") }
        self.addObject(object)
        return object
    }
    
    func objectWithIdentifier(identifier: String?) -> T? {
        if let identifier = identifier {
            for object in allObjects() {
                if let recID = object.internRecordID {
                    print(identifier)
                    print(recID)
                    if identifier == recID {
                        return object
                    }
                }
            }
            return nil
        }
        return nil
        
    }
    
    func addObject(object: T) {
        internAllObjects.append(object)
    }
    
    func updateObject(object: T) {
        let oldObjet = objectWithIdentifier(object.recordID())
        self.deleteObject(oldObjet!)
        self.addObject(object)
    }
    
    func deleteObject(object: T) {
        let objectToDeleteInDatabase = objectWithIdentifier(object.recordID())
        let index = self.internAllObjects.indexOf(objectToDeleteInDatabase!)
        self.internAllObjects.removeAtIndex(index!)
        
    }
    
    func allUnsyncedObjects() -> [T] {
        return self.internAllObjects.filter {
            if $0.syncStatus() == false {
                return true
            }
            return false
        }
    }
    
    func updateObject(object: T, withDictionary dictionary: [String : Any]) {
        object.updateWithDictionary(dictionary)
    }
    
    func setSyncStatus(syncStatus: Bool, forObject object: T) {
        object.internSyncStatus = syncStatus
    }
    
    func setRecordID(recordID: String?, forObject object: T) {
        object.internRecordID = recordID
    }
    
    func modificationDateForObject(object: T) -> NSDate {
        return object.internModificationDate
    }
    
    func setModificationDate(modificationDate: NSDate?, forObject object: T) {
        if let modificationDate = modificationDate {
            object.internModificationDate = modificationDate
        }
    }
    
    func allPropertiesForObject(object: T) -> [String : Any] {
        return [
            "string":object.string,
            "int":object.int,
            "double":object.double
        ]
    }
    
    func recordIDForObject(object: T) -> String? {
        return object.internRecordID
    }
    
}