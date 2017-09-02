//
//  CloudKitInterface.swift
//  Radon
//
//  Created by mhaddl on 25/10/2016.
//  Copyright © 2016 Martin Hartl. All rights reserved.
//

import Foundation
import CloudKit

extension CKServerChangeToken: ServerChangeToken { }

extension CKRecord: Record {
    public var recordName: String {
        get {
            return recordID.recordName
        }
    }
}

open class RadonCloudKit: CloudInterface {
    
    public typealias RecordType = CKRecord
    public typealias ChangeToken = CKServerChangeToken
    
    open let container: CKContainer
    open let privateDatabase: CKDatabase
    open let syncableRecordZone: CKRecordZone
    private let syncableName: String
    
    init(cloudKitIdentifier: String, recordZoneName: String, syncableName: String) {
        self.container = CKContainer(identifier: cloudKitIdentifier)
        self.privateDatabase = self.container.privateCloudDatabase
        self.syncableRecordZone = CKRecordZone(zoneName: recordZoneName)
        self.syncableName = syncableName
    }
    
    public func setup(completion: (Error?) -> Void) {
        privateDatabase.save(syncableRecordZone) { (zone, error) -> Void in
            print("CloudKit error: \(error.debugDescription)")
        }
        
        subscribeToItemUpdates()
    }
    
    public func createRecord(withDictionary dictionary: [String : Any], onQueue queue: DispatchQueue, createRecordCompletionBlock: (@escaping (String?, Error?) -> Void)) {
        let record = CKRecord(dictionary: dictionary, recordType: syncableName, zoneName: syncableName)
        let createOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        createOperation.database = self.privateDatabase
        createOperation.rad_setModifyRecordsCompletionBlock(onQueue: queue, modifyRecordsCompletionBlock: { (records, recordIDs, error) in
            createRecordCompletionBlock(records?.first?.recordID.recordName,error)
        })
        createOperation.start()
    }
    
    open func fetchRecord(_ recordName: String, onQueue queue: DispatchQueue, fetchRecordsCompletionBlock: @escaping ((RecordType?, Error?) -> Void)) {
        let recordID = CKRecordID(recordName: recordName, zoneID: self.syncableRecordZone.zoneID)
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
    
    open func modifyRecord(_ record: RecordType, onQueue queue: DispatchQueue, modifyRecordsCompletionBlock: @escaping (([RecordType]?, [String]?, Error?) -> Void)) {
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        modifyOperation.database = self.privateDatabase
        modifyOperation.savePolicy = .changedKeys
        modifyOperation.rad_setModifyRecordsCompletionBlock(onQueue: queue) { (records, recordIDs, error) in
            let recordNames = recordIDs?.map { return $0.recordName }
            modifyRecordsCompletionBlock(records, recordNames, error)
        }
        modifyOperation.start()
    }
    
    open func deleteRecordWithName(_ recordName: String, onQueue queue: DispatchQueue, modifyRecordsCompletionBlock: @escaping ((Error?) -> Void)) {
        let recordID = CKRecordID(recordName: recordName, zoneID: self.syncableRecordZone.zoneID)
        let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID])
        deleteOperation.database = self.privateDatabase
        deleteOperation.rad_setModifyRecordsCompletionBlock(onQueue: queue) {records, deletedRecordIDs, error in
            modifyRecordsCompletionBlock(error)
        }
        
        deleteOperation.start()
    }
    
    public func fetchRecordChanges(onQueue queue: DispatchQueue, previousServerChangeToken: ServerChangeToken?, recordChangeBlock: (@escaping (Record) -> Void), recordWithNameWasDeletedBlock: (@escaping (String) -> Void), fetchRecordChangesCompletionBlock: (@escaping (ServerChangeToken?, Bool, Error?, Bool) -> Void)) {
        
        let options = CKFetchRecordZoneChangesOptions()
        //TODO: make it nicer
        options.previousServerChangeToken = (previousServerChangeToken as? ChangeToken)
        
        let fetchRecordZoneChangesOperation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [self.syncableRecordZone.zoneID], optionsByRecordZoneID: [self.syncableRecordZone.zoneID:options])
        
        fetchRecordZoneChangesOperation.database = self.privateDatabase
        
        fetchRecordZoneChangesOperation.rad_setRecordChangedBlock(onQueue: queue, recordChangedBlock: recordChangeBlock)
        
        fetchRecordZoneChangesOperation.rad_setRecordWithIDWasDeletedBlock(onQueue: queue) { (recordID, string) in
            recordWithNameWasDeletedBlock(recordID.recordName)
        }
        
        fetchRecordZoneChangesOperation.rad_setFetchRecordChangesCompletionBlock(onQueue: queue) { (zoneID, serverChangeToken, data, moreComing, error) in
            if let ckerror = error as? CKError , ckerror.code == CKError.changeTokenExpired {
                fetchRecordChangesCompletionBlock(serverChangeToken, moreComing, error, true)
            }
            
            fetchRecordChangesCompletionBlock(serverChangeToken, moreComing, error, false)
        }
        
        
        fetchRecordZoneChangesOperation.start()
    }
    
    public func fetchUserRecordNameWithCompletionHandler(_ completionHandler: @escaping (String?, Error?) -> Void) {
        self.container.fetchUserRecordID { (recordID, error) in
            completionHandler(recordID?.recordName, error)
        }
    }
    
    public func queryNotificationReason(for userInfo: [AnyHashable : Any]) -> QueryNotificationReason {
        //TODO: handle possible crash
        let notification =  CKQueryNotification(fromRemoteNotificationDictionary: userInfo as! [String: NSObject])
        guard let recordName = notification.recordID?.recordName else { return .invalid }
        switch notification.queryNotificationReason {
        case .recordCreated:
            return .recordCreated(recordName: recordName)
        case .recordUpdated:
            return .recordUpdated(recordName: recordName)
        case .recordDeleted:
            return .recordDeleted(recordName: notification.recordID?.recordName)
        }
    }
    
    // MARK: - Private notification handling methods
    
    fileprivate func notificationInfo() -> CKNotificationInfo {
        let notificationInfo = CKNotificationInfo()
        notificationInfo.shouldBadge = false
        notificationInfo.shouldSendContentAvailable = true
        return notificationInfo
    }
    
    fileprivate func subscribeToItemUpdates() {
        self.saveSubscriptionWithIdent("create", options: .firesOnRecordCreation)
        self.saveSubscriptionWithIdent("update", options: .firesOnRecordUpdate)
        self.saveSubscriptionWithIdent("delete", options: .firesOnRecordDeletion)
    }
    
    fileprivate func saveSubscriptionWithIdent(_ ident: String, options: CKQuerySubscriptionOptions) {
        let subscription = CKQuerySubscription(recordType: syncableName, predicate: NSPredicate(value: true), subscriptionID: ident, options: options)
        subscription.notificationInfo = self.notificationInfo();
        self.privateDatabase.save(subscription) { (subscription, error) -> Void in
            //TODO: handle error
        }
    }
}

// MARK: - Private CKDatabaseOperation extensions

internal extension CKFetchRecordZoneChangesOperation {
    func rad_setRecordChangedBlock(onQueue queue: DispatchQueue, recordChangedBlock: @escaping ((CKRecord) -> Void)) {
        self.recordChangedBlock = { record in
            return queue.sync {
                recordChangedBlock(record)
            }
        }
    }
    
    func rad_setRecordWithIDWasDeletedBlock(onQueue queue: DispatchQueue, recordWithIDWasDeletedBlock: @escaping ((CKRecordID, String) -> Void)) {
        self.recordWithIDWasDeletedBlock = { record, string in
            return queue.sync { recordWithIDWasDeletedBlock(record, string) }
        }
    }
    
    func rad_setFetchRecordChangesCompletionBlock(onQueue queue: DispatchQueue, fetchRecordChangesCompletionBlock: @escaping ((CKRecordZoneID, CKServerChangeToken?, Data?, Bool, Error?) -> Void)) {
        
        self.recordZoneFetchCompletionBlock = { zoneID, token, data, moreComing, error in
            return queue.sync {
                fetchRecordChangesCompletionBlock(zoneID,token, data, moreComing, error)
            }
        }
        
    }
}

internal extension CKModifyRecordsOperation {
    func rad_setPerRecordProgressBlock(onQueue queue: DispatchQueue, perRecordProgressBlock: @escaping ((CKRecord, Double) -> Void)) {
        self.perRecordProgressBlock = { record, double in
            return queue.async {
                perRecordProgressBlock(record, double)
            }
        }
    }
    
    func rad_setPerRecordCompletionBlock(onQueue queue: DispatchQueue, perRecordCompletionBlock: @escaping ((CKRecord?, Error?) -> Void)) {
        self.perRecordCompletionBlock = { (record, error) -> () in
            return queue.async {
                perRecordCompletionBlock(record, error)
            }
        }
    }
    
    func rad_setModifyRecordsCompletionBlock(onQueue queue: DispatchQueue, modifyRecordsCompletionBlock: @escaping (([CKRecord]?, [CKRecordID]?, Error?) -> Void)) {
        self.modifyRecordsCompletionBlock = { records, recordID, error in
            return queue.async {
                modifyRecordsCompletionBlock(records, recordID, error)
            }
        }
    }
}

internal extension CKFetchRecordsOperation {
    func rad_setFetchRecordsCompletionBlock(inQueue queue: DispatchQueue, fetchRecordsCompletionBlock: @escaping (([CKRecordID : CKRecord]?, Error?) -> Void)) {
        self.fetchRecordsCompletionBlock = { recordsDictionary, error in
            return queue.async {
                fetchRecordsCompletionBlock(recordsDictionary, error)
            }
        }
    }
}
