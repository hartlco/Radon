//
//  TestClass.swift
//  Radon
//
//  Created by Martin Hartl on 05/11/15.
//  Copyright © 2015 Martin Hartl. All rights reserved.
//

import Foundation

class TestClass: Syncable {
    var string: String
    var int: Int
    var double: Double
    var internRecordID: String?
    var internSyncStatus: Bool
    
    var internModificationDate: NSDate = NSDate()
    
    required init() {
        self.string = ""
        self.int = 0
        self.double = 0
        self.internModificationDate = NSDate()
        self.internSyncStatus = false
    }
    
    required init(string: String, int: Int, double: Double) {
        self.string = string
        self.int = int
        self.double = double
        self.internModificationDate = NSDate()
        self.internSyncStatus = false
    }
    
    required init?(dictionary: [String : Any]) {
        if  let string = dictionary["string"] as? String,
            let int = dictionary["int"] as? Int,
            let double = dictionary["double"] as? Double {
                self.string = string
                self.int = int
                self.double = double
                self.internSyncStatus = true
        } else {
            self.string = ""
            self.int = 0
            self.double = 0
            self.internModificationDate = NSDate()
            self.internSyncStatus = false
            return nil
        }
    }

    
    func setRecordID(recordID: String?) {
        self.internRecordID = recordID
    }
    
    func recordID() -> String? {
        return self.internRecordID
    }
    
    class func internRecordIDPropertyName() -> String {
        return "internRecordID"
    }
    
    func syncStatus() -> Bool {
        return self.internSyncStatus
    }
    
    class func internSyncStatusPropertyName() -> String {
        return "internSyncStatus"
    }
    
    func modificationDate() -> NSDate {
        return self.internModificationDate
    }
    
    
    func updateWithDictionary(dictionary: [String:Any]) {
        if  let string = dictionary["string"] as? String,
            let int = dictionary["int"] as? Int,
            let double = dictionary["double"] as? Double {
                self.string = string
                self.int = int
                self.double = double
        }
    }
    
    class func propertyNamesToSync() -> [String] {
        return ["string","int","double"]
    }
}

extension TestClass {

}

extension TestClass: Equatable {}

func ==(lhs: TestClass, rhs: TestClass) -> Bool {
    if lhs.string == rhs.string && lhs.int == rhs.int && lhs.double == rhs.double {
        return true
    }
    return false
}