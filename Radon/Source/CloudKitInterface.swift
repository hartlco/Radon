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
    var modificationDate: Date? { get }
    func valuesDictionaryForKeys(_ keys: [String], syncableType: Syncable.Type) -> [String:Any]
}

extension CKRecord: Record {
    
}

public protocol CloudKitInterface {
    
    var container: CKContainer {get}
    var privateDatabase: CKDatabase {get}
    
    func saveRecordZone(_ zone: CKRecordZone, completionHandler: (CKRecordZone?, Error?) -> Void)
    
    func createRecord(_ record: CKRecord, onQueue queue: DispatchQueue, createRecordCompletionBlock: ((_ recordName:String?,_ error:Error?) -> Void))
    
    func fetchRecord(_ recordID: CKRecordID, onQueue queue: DispatchQueue, fetchRecordsCompletionBlock: ((CKRecord?, Error?) -> Void))
    
    func modifyRecord(_ record: CKRecord, onQueue queue: DispatchQueue, modifyRecordsCompletionBlock: (([CKRecord]?, [CKRecordID]?, Error?) -> Void))
    
    func deleteRecordWithID(_ recordID: CKRecordID, onQueue queue: DispatchQueue, modifyRecordsCompletionBlock: ((Error?) -> Void))
    
    func fetchRecordChanges(onQueue queue: DispatchQueue, previousServerChangeToken: CKServerChangeToken?, recordChangeBlock: ((Record) -> Void), recordWithIDWasDeletedBlock: ((CKRecordID, String) -> Void), fetchRecordChangesCompletionBlock: ((CKRecordZoneID, CKServerChangeToken?, Data?, Bool, Error?) -> Void))
}

open class RadonCloudKit: CloudKitInterface {
    
    open let container: CKContainer
    open let privateDatabase: CKDatabase
    open let syncableRecordZone: CKRecordZone
    
    init(cloudKitIdentifier: String, recordZoneName: String) {
        self.container = CKContainer(identifier: cloudKitIdentifier)
        self.privateDatabase = self.container.privateCloudDatabase
        self.syncableRecordZone = CKRecordZone(zoneName: recordZoneName)
    }
    
    open func saveRecordZone(_ zone: CKRecordZone, completionHandler: (CKRecordZone?, Error?) -> Void) {
        privateDatabase.save(syncableRecordZone) { (zone, error) -> Void in
            print("CloudKit error: \(error)")
        }
    }
    
    open func createRecord(_ record: CKRecord, onQueue queue: DispatchQueue, createRecordCompletionBlock modifyRecordsCompletionBlock: ((_ recordName:String?, _ error:Error?) -> Void)) {
        let createOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        createOperation.database = self.privateDatabase
        createOperation.rad_setModifyRecordsCompletionBlock(onQueue: queue, modifyRecordsCompletionBlock: { (records, recordIDs, error) in
            modifyRecordsCompletionBlock(records?.first?.recordID.recordName,error)
        })
        createOperation.start()
    }
    
    open func fetchRecord(_ recordID: CKRecordID, onQueue queue: DispatchQueue, fetchRecordsCompletionBlock: ((CKRecord?, Error?) -> Void)) {
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
    
    open func modifyRecord(_ record: CKRecord, onQueue queue: DispatchQueue, modifyRecordsCompletionBlock: (([CKRecord]?, [CKRecordID]?, Error?) -> Void)) {
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        modifyOperation.database = self.privateDatabase
        modifyOperation.savePolicy = .changedKeys
        modifyOperation.rad_setModifyRecordsCompletionBlock(onQueue: queue, modifyRecordsCompletionBlock: modifyRecordsCompletionBlock)
        modifyOperation.start()
    }
    
    open func deleteRecordWithID(_ recordID: CKRecordID, onQueue queue: DispatchQueue, modifyRecordsCompletionBlock: ((Error?) -> Void)) {
        let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID])
        deleteOperation.database = self.privateDatabase
        deleteOperation.rad_setModifyRecordsCompletionBlock(onQueue: queue) {records, deletedRecordIDs, error in
            modifyRecordsCompletionBlock(error)
        }
        
        deleteOperation.start()
    }
    
    open func fetchRecordChanges(onQueue queue: DispatchQueue, previousServerChangeToken: CKServerChangeToken?, recordChangeBlock: ((Record) -> Void), recordWithIDWasDeletedBlock: ((CKRecordID, String) -> Void), fetchRecordChangesCompletionBlock: ((CKRecordZoneID, CKServerChangeToken?, Data?, Bool, Error?) -> Void)) {
        
        let options = CKFetchRecordZoneChangesOptions()
        options.previousServerChangeToken = previousServerChangeToken
        
        let fetchRecordZoneChangesOperation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [self.syncableRecordZone.zoneID], optionsByRecordZoneID: [self.syncableRecordZone.zoneID:options])
        
        fetchRecordZoneChangesOperation.database = self.privateDatabase
        
        fetchRecordZoneChangesOperation.rad_setRecordChangedBlock(onQueue: queue, recordChangedBlock: recordChangeBlock)
        
        fetchRecordZoneChangesOperation.rad_setRecordWithIDWasDeletedBlock(onQueue: queue, recordWithIDWasDeletedBlock: recordWithIDWasDeletedBlock)
        
        fetchRecordZoneChangesOperation.rad_setFetchRecordChangesCompletionBlock(onQueue: queue, fetchRecordChangesCompletionBlock: fetchRecordChangesCompletionBlock)
        
        fetchRecordZoneChangesOperation.start()
        
    }
}

// MARK: - Private CKDatabaseOperation extensions

internal extension CKFetchRecordZoneChangesOperation {
    func rad_setRecordChangedBlock(onQueue queue: DispatchQueue, recordChangedBlock: ((CKRecord) -> Void)) {
        self.recordChangedBlock = { record in
            return queue.sync {
                recordChangedBlock(record)
            }
        }
    }
    
    func rad_setRecordWithIDWasDeletedBlock(onQueue queue: DispatchQueue, recordWithIDWasDeletedBlock: ((CKRecordID, String) -> Void)) {
        self.recordWithIDWasDeletedBlock = { record, string in
            return queue.sync {
                recordWithIDWasDeletedBlock(record, string)
            }
        }
    }
    
    func rad_setFetchRecordChangesCompletionBlock(onQueue queue: DispatchQueue, fetchRecordChangesCompletionBlock: ((CKRecordZoneID, CKServerChangeToken?, Data?, Bool, Error?) -> Void)) {
        
        self.recordZoneFetchCompletionBlock = { zoneID, token, data, moreComing, error in
            return queue.sync {
                fetchRecordChangesCompletionBlock(zoneID,token, data, moreComing, error)
            }
        }
        
    }
}

internal extension CKModifyRecordsOperation {
    func rad_setPerRecordProgressBlock(onQueue queue: DispatchQueue, perRecordProgressBlock: ((CKRecord, Double) -> Void)) {
        self.perRecordProgressBlock = { record, double in
            return queue.async {
                perRecordProgressBlock(record, double)
            }
        }
    }
    
    func rad_setPerRecordCompletionBlock(onQueue queue: DispatchQueue, perRecordCompletionBlock: ((CKRecord?, Error?) -> Void)) {
        self.perRecordCompletionBlock = { (record, error) -> () in
            return queue.async {
                perRecordCompletionBlock(record, error)
            }
        }
    }
    
    func rad_setModifyRecordsCompletionBlock(onQueue queue: DispatchQueue, modifyRecordsCompletionBlock: (([CKRecord]?, [CKRecordID]?, Error?) -> Void)) {
        self.modifyRecordsCompletionBlock = { records, recordID, error in
            return queue.async {
                modifyRecordsCompletionBlock(records, recordID, error)
            }
        }
    }
}

internal extension CKFetchRecordsOperation {
    func rad_setFetchRecordsCompletionBlock(inQueue queue: DispatchQueue, fetchRecordsCompletionBlock: (([CKRecordID : CKRecord]?, Error?) -> Void)) {
        self.fetchRecordsCompletionBlock = { recordsDictionary, error in
            return queue.async {
                fetchRecordsCompletionBlock(recordsDictionary, error)
            }
        }
    }
}
