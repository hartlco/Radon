//
//  CloudKitInterface.swift
//  Radon
//
//  Created by mhaddl on 06/05/16.
//  Copyright © 2016 Martin Hartl. All rights reserved.
//

import Foundation
import CloudKit

public protocol Record {
    var recordID: CKRecordID {get}
    var modificationDate: NSDate? { get }
    func valuesDictionaryForKeys(keys: [String], syncableType: Syncable.Type) -> [String:Any]
}

extension CKRecord: Record {
    
}

public protocol CloudKitInterface {
    
    var container: CKContainer {get}
    var privateDatabase: CKDatabase {get}
    
    func saveRecordZone(zone: CKRecordZone, completionHandler: (CKRecordZone?, NSError?) -> Void)
    
    func createRecord(record: CKRecord, onQueue queue: dispatch_queue_t, createRecordCompletionBlock: ((recordName:String?,error:NSError?) -> Void))
    
    func fetchRecord(recordID: CKRecordID, onQueue queue: dispatch_queue_t, fetchRecordsCompletionBlock: ((CKRecord?, NSError?) -> Void))
    
    func modifyRecord(record: CKRecord, onQueue queue: dispatch_queue_t, modifyRecordsCompletionBlock: (([CKRecord]?, [CKRecordID]?, NSError?) -> Void))
    
    func deleteRecordWithID(recordID: CKRecordID, onQueue queue: dispatch_queue_t, modifyRecordsCompletionBlock: ((NSError?) -> Void))
    
    func fetchRecordChanges(onQueue queue: dispatch_queue_t, previousServerChangeToken: CKServerChangeToken?, recordChangeBlock: ((Record) -> Void), recordWithIDWasDeletedBlock: ((CKRecordID) -> Void), fetchRecordChangesCompletionBlock: ((CKServerChangeToken?, NSData?, NSError?) -> Void))
}

public class RadonCloudKit: CloudKitInterface {
    
    public let container: CKContainer
    public let privateDatabase: CKDatabase
    public let syncableRecordZone: CKRecordZone
    
    init(cloudKitIdentifier: String, recordZoneName: String) {
        self.container = CKContainer(identifier: cloudKitIdentifier)
        self.privateDatabase = self.container.privateCloudDatabase
        self.syncableRecordZone = CKRecordZone(zoneName: recordZoneName)
    }
    
    public func saveRecordZone(zone: CKRecordZone, completionHandler: (CKRecordZone?, NSError?) -> Void) {
        privateDatabase.saveRecordZone(syncableRecordZone) { (zone, error) -> Void in
            print("CloudKit error: \(error)")
        }
    }
    
    public func createRecord(record: CKRecord, onQueue queue: dispatch_queue_t, createRecordCompletionBlock modifyRecordsCompletionBlock: ((recordName:String?, error:NSError?) -> Void)) {
        let createOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        createOperation.database = self.privateDatabase
        createOperation.rad_setModifyRecordsCompletionBlock(onQueue: queue, modifyRecordsCompletionBlock: { (records, recordIDs, error) in
            modifyRecordsCompletionBlock(recordName:records?.first?.recordID.recordName,error: error)
        })
        createOperation.start()
    }
    
    public func fetchRecord(recordID: CKRecordID, onQueue queue: dispatch_queue_t, fetchRecordsCompletionBlock: ((CKRecord?, NSError?) -> Void)) {
        let fetchOperation = CKFetchRecordsOperation(recordIDs: [recordID])
        fetchOperation.database = self.privateDatabase
        fetchOperation.rad_setFetchRecordsCompletionBlock(inQueue: queue, fetchRecordsCompletionBlock: { (recordsDictionary, error) in
            if let record = recordsDictionary?[recordID] {
                fetchRecordsCompletionBlock(record, nil)
                return
            }
            fetchRecordsCompletionBlock(nil, error)
            
        })
        fetchOperation.start()
    }
    
    public func modifyRecord(record: CKRecord, onQueue queue: dispatch_queue_t, modifyRecordsCompletionBlock: (([CKRecord]?, [CKRecordID]?, NSError?) -> Void)) {
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        modifyOperation.database = self.privateDatabase
        modifyOperation.savePolicy = .ChangedKeys
        modifyOperation.rad_setModifyRecordsCompletionBlock(onQueue: queue, modifyRecordsCompletionBlock: modifyRecordsCompletionBlock)
        modifyOperation.start()
    }
    
    public func deleteRecordWithID(recordID: CKRecordID, onQueue queue: dispatch_queue_t, modifyRecordsCompletionBlock: ((NSError?) -> Void)) {
        let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID])
        deleteOperation.database = self.privateDatabase
        deleteOperation.rad_setModifyRecordsCompletionBlock(onQueue: queue) {records, deletedRecordIDs, error in
            modifyRecordsCompletionBlock(error)
        }
        
        deleteOperation.start()
    }
    
    public func fetchRecordChanges(onQueue queue: dispatch_queue_t, previousServerChangeToken: CKServerChangeToken?, recordChangeBlock: ((Record) -> Void), recordWithIDWasDeletedBlock: ((CKRecordID) -> Void), fetchRecordChangesCompletionBlock: ((CKServerChangeToken?, NSData?, NSError?) -> Void)) {
        
        let fetchRecordChangesOperation = CKFetchRecordChangesOperation(recordZoneID: syncableRecordZone.zoneID, previousServerChangeToken: previousServerChangeToken)
        fetchRecordChangesOperation.database = self.privateDatabase
        
        fetchRecordChangesOperation.rad_setRecordChangedBlock(onQueue: queue, recordChangedBlock: recordChangeBlock)
        
        fetchRecordChangesOperation.rad_setRecordWithIDWasDeletedBlock(onQueue: queue, recordWithIDWasDeletedBlock: recordWithIDWasDeletedBlock)
        
        fetchRecordChangesOperation.rad_setFetchRecordChangesCompletionBlock(onQueue: queue, fetchRecordChangesCompletionBlock: fetchRecordChangesCompletionBlock)
        
        fetchRecordChangesOperation.start()
        
    }
}

// MARK: - Private CKDatabaseOperation extensions

internal extension CKFetchRecordChangesOperation {
    func rad_setRecordChangedBlock(onQueue queue: dispatch_queue_t, recordChangedBlock: ((CKRecord) -> Void)) {
        self.recordChangedBlock = { record in
            return dispatch_sync(queue) {
                recordChangedBlock(record)
            }
        }
    }
    
    func rad_setRecordWithIDWasDeletedBlock(onQueue queue: dispatch_queue_t, recordWithIDWasDeletedBlock: ((CKRecordID) -> Void)) {
        self.recordWithIDWasDeletedBlock = { record in
            return dispatch_sync(queue) {
                recordWithIDWasDeletedBlock(record)
            }
        }
    }
    
    func rad_setFetchRecordChangesCompletionBlock(onQueue queue: dispatch_queue_t, fetchRecordChangesCompletionBlock: ((CKServerChangeToken?, NSData?, NSError?) -> Void)) {
        self.fetchRecordChangesCompletionBlock = { token, data, error in
            return dispatch_sync(queue) {
                fetchRecordChangesCompletionBlock(token, data, error)
            }
        }
        
    }
}

internal extension CKModifyRecordsOperation {
    func rad_setPerRecordProgressBlock(onQueue queue: dispatch_queue_t, perRecordProgressBlock: ((CKRecord, Double) -> Void)) {
        self.perRecordProgressBlock = { record, double in
            return dispatch_async(queue) {
                perRecordProgressBlock(record, double)
            }
        }
    }
    
    func rad_setPerRecordCompletionBlock(onQueue queue: dispatch_queue_t, perRecordCompletionBlock: ((CKRecord?, NSError?) -> Void)) {
        self.perRecordCompletionBlock = { record, error in
            return dispatch_async(queue) {
                perRecordCompletionBlock(record, error)
            }
        }
    }
    
    func rad_setModifyRecordsCompletionBlock(onQueue queue: dispatch_queue_t, modifyRecordsCompletionBlock: (([CKRecord]?, [CKRecordID]?, NSError?) -> Void)) {
        self.modifyRecordsCompletionBlock = { records, recordID, error in
            return dispatch_async(queue) {
                modifyRecordsCompletionBlock(records, recordID, error)
            }
        }
    }
}

internal extension CKFetchRecordsOperation {
    func rad_setFetchRecordsCompletionBlock(inQueue queue: dispatch_queue_t, fetchRecordsCompletionBlock: (([CKRecordID : CKRecord]?, NSError?) -> Void)) {
        self.fetchRecordsCompletionBlock = { recordsDictionary, error in
            return dispatch_async(queue) {
                fetchRecordsCompletionBlock(recordsDictionary, error)
            }
        }
    }
}
