//
//  MockCloudKitInterface.swift
//  Radon
//
//  Created by mhaddl on 06/05/16.
//  Copyright © 2016 Martin Hartl. All rights reserved.
//

import Foundation
import CloudKit
@testable import Radon_iOS

class MockRecord: Record {
    var recordID: CKRecordID
    var modificationDate: NSDate?
    
    var string:String
    var int: Int
    var double: Double
    
    func valuesDictionaryForKeys(keys: [String], syncableType: Syncable.Type) -> [String : Any] {
        return [
            "string":string,
            "int":int,
            "double":double
        ]
    }
    
    init(recordID: CKRecordID, modificationDate: NSDate, string: String, int: Int, double: Double) {
        self.recordID = recordID
        self.modificationDate = modificationDate
        self.string = string
        self.int = int
        self.double = double
    }
}

class MockCloudKitInterface: CloudKitInterface {
    
    init() {
        self.container = CKContainer(identifier: "Mock")
        self.privateDatabase = self.container.publicCloudDatabase
    }
    
    var container: CKContainer
    var privateDatabase: CKDatabase
    
    var failsSaveRecordZone = false
    var failsCreateRecord = false
    var failsFetchRecord = false
    var failsModifyRecord = false
    var failsDeleteRecord = false
    var syncRecordChangeHasNewObject = false
    var syncOlderObject = false
    
    func saveRecordZone(zone: CKRecordZone, completionHandler: (CKRecordZone?, NSError?) -> Void) {
        if failsSaveRecordZone {
            completionHandler(nil, NSError(domain: "Fail", code: 1, userInfo: nil))
        } else {
            completionHandler(CKRecordZone(zoneName: "Mock"), nil)
        }
    }
    
    func createRecord(record: CKRecord, onQueue queue: dispatch_queue_t, createRecordCompletionBlock modifyRecordsCompletionBlock: ((recordName: String?, error: NSError?) -> Void)) {
        
        if failsCreateRecord {
            modifyRecordsCompletionBlock(recordName:nil, error: NSError(domain: "Fail", code: 1, userInfo: nil))
        } else {
            modifyRecordsCompletionBlock(recordName: "Mock", error: nil)
            
        }
    }
    
    func fetchRecord(recordID: CKRecordID, onQueue queue: dispatch_queue_t, fetchRecordsCompletionBlock: ((CKRecord?, NSError?) -> Void)) {
        
        let mockStore = ExampleRadonStore()
        let object = TestClass(string: "Mock", int: 1, double: 2)
        
        if failsFetchRecord {
            fetchRecordsCompletionBlock(nil, NSError(domain: "Fail", code: 1, userInfo: nil))
        } else {
            let record = CKRecord(recordType: "Mock", recordID: CKRecordID(recordName: "Mock"))
            record.updateWithDictionary(mockStore.allPropertiesForObject(object))
            fetchRecordsCompletionBlock(record, nil)
        }
    }
    
    func modifyRecord(record: CKRecord, onQueue queue: dispatch_queue_t, modifyRecordsCompletionBlock: (([CKRecord]?, [CKRecordID]?, NSError?) -> Void)) {
        
        if failsModifyRecord {
            modifyRecordsCompletionBlock(nil, nil, NSError(domain: "Fail", code: 1, userInfo: nil))
        } else {
            modifyRecordsCompletionBlock([record],nil,nil)
        }
    }
    
    func deleteRecordWithID(recordID: CKRecordID, onQueue queue: dispatch_queue_t, modifyRecordsCompletionBlock: ((NSError?) -> Void)) {
        if failsDeleteRecord {
            modifyRecordsCompletionBlock(NSError(domain: "Fail", code: 1, userInfo: nil))
        } else {
            modifyRecordsCompletionBlock(nil)
        }
    }
    
    func fetchRecordChanges(onQueue queue: dispatch_queue_t, previousServerChangeToken: CKServerChangeToken?, recordChangeBlock: ((Record) -> Void), recordWithIDWasDeletedBlock: ((CKRecordID) -> Void), fetchRecordChangesCompletionBlock: ((CKServerChangeToken?, NSData?, NSError?) -> Void)) {
        
        if syncRecordChangeHasNewObject {
            
            let date: NSDate
            if syncOlderObject {
                date = NSDate(timeIntervalSince1970: 0)
            } else {
                date = NSDate()
            }
            
            let record = MockRecord(recordID: CKRecordID(recordName: "Mock"), modificationDate: date, string: "ServerUpdated", int: 4, double: 5)
            recordChangeBlock(record)
        }
        
        fetchRecordChangesCompletionBlock(nil, nil, nil)
        
    }
    
}