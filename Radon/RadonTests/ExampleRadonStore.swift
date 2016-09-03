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
    let userDeaults = UserDefaults.standard
    
    init() {
        let allObjects = [TestClass]()
        userDeaults.set(allObjects, forKey: storeKey)
        userDeaults.synchronize()
    }
    
    func allObjects() -> [T] {
        return internAllObjects
    }
    
    func recordNameForObject(_ object: T) -> String? {
        return object.internRecordID
    }
    
    func setRecordName(_ recordName: String?, forObject object: T) {
        object.internRecordID = recordName
    }
    
    func newObject(_ newObjectBlock: ((_ newObject: T) -> (T))) -> () -> (T) {
        return {
            srandom(UInt32(time(nil)))
            let newObject = TestClass(string: String(Int(arc4random())), int: Int(arc4random()), double: 323432.234)
            _ = newObjectBlock(newObject)
            self.addObject(newObject)
            return newObject
        }
    }
    
    func updateObject(_ objectUpdateBlock: @escaping () -> T) -> (() -> T) {
        return {
            return objectUpdateBlock()
        }
    }
    
    func newObjectFromDictionary(_ dictionary: [String : Any]) -> T {
        let newObject = T(dictionary: dictionary)
        guard let object = newObject else { fatalError("Can't initializes object from dictionary") }
        self.addObject(object)
        return object
    }
    
    func objectWithIdentifier(_ identifier: String?) -> T? {
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
    
    func addObject(_ object: T) {
        internAllObjects.append(object)
    }
    
    func updateObject(_ object: T) {
        let oldObjet = objectWithIdentifier(object.recordID())
        self.deleteObject(oldObjet!)
        self.addObject(object)
    }
    
    func deleteObject(_ object: T) {
        let objectToDeleteInDatabase = objectWithIdentifier(object.recordID())
        let index = self.internAllObjects.index(of: objectToDeleteInDatabase!)
        self.internAllObjects.remove(at: index!)
        
    }
    
    func allUnsyncedObjects() -> [T] {
        return self.internAllObjects.filter {
            if $0.syncStatus() == false {
                return true
            }
            return false
        }
    }
    
    func updateObject(_ object: T, withDictionary dictionary: [String : Any]) {
        object.updateWithDictionary(dictionary)
    }
    
    func setSyncStatus(_ syncStatus: Bool, forObject object: T) {
        object.internSyncStatus = syncStatus
    }
    
    func setRecordID(_ recordID: String?, forObject object: T) {
        object.internRecordID = recordID
    }
    
    func modificationDateForObject(_ object: T) -> Date {
        return object.internModificationDate as Date
    }
    
    func setModificationDate(_ modificationDate: Date?, forObject object: T) {
        if let modificationDate = modificationDate {
            object.internModificationDate = modificationDate
        }
    }
    
    func allPropertiesForObject(_ object: T) -> [String : Any] {
        return [
            "string":object.string,
            "int":object.int,
            "double":object.double
        ]
    }
    
    func recordIDForObject(_ object: T) -> String? {
        return object.internRecordID
    }
    
}
