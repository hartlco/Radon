//
//  CloudKit+Radon.swift
//  Radon
//
//  Created by Martin Hartl on 25/08/16.
//  Copyright © 2016 Martin Hartl. All rights reserved.
//

import Foundation
import CloudKit

extension CKRecord {
    
    internal convenience init(dictionary: [String:Any], recordType: String, zoneName: String) {
        self.init(recordType: recordType, zoneID: CKRecordZone(zoneName: zoneName).zoneID)
        self.updateWithDictionary(dictionary)
    }
    
    public func updateWithDictionary(_ dictionary: [String:Any]) {
        for (key, value) in dictionary {
            if let value = value as? CKRecordValue {
                self.setObject(value, forKey: key)
            }
        }
    }
    
    public func valuesDictionaryForKeys(_ keys: [String], syncableType: Syncable.Type) -> [String:Any] {
        var allValues = [String:Any]()
        allValues["modificationDate"] = self.modificationDate
        for key in keys {
            if let valuesFromRecord = self.value(forKey: key) {
                allValues[key] = valuesFromRecord
            } else {
                assert(true, "Requested key: \(key) has no value in CKRecord instance")
            }
        }
        
        return allValues
    }
}
