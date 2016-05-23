//
//  Radon.swift
//  Radon
//
//  Created by mhaddl on 01/11/15.
//  Copyright © 2015 Martin Hartl. All rights reserved.
//

import Foundation
import CloudKit

private let RadonTokenConstant = "RadonToken"
private let RadoniCloudUserConstant = "RadoniCloudUserConstant"

extension NSDate {
    /**
     Basic comparison if the date self is smaller than the date given as the argument.
     
     - parameter date: NSDate optional used to compare.
     
     - returns: Boolean value indicating if the date self is smaller than the date in the argument. If the argument is nil, `false` is returned.
     */
    func isEarlierThan(date: NSDate?) -> Bool {
        guard let date = date else {
            return false
        }
        
        return self.compare(date) == .OrderedAscending
    }
}

public protocol Syncable {
    static func propertyNamesToSync() -> [String]
}

public protocol RadonStore {
    associatedtype T:Syncable
    
    func allPropertiesForObject(object: T) -> [String:Any]
    func recordNameForObject(object: T) -> String?
    func newObject(newObjectBlock: ((newObject: T) -> (T))) -> () -> (T)
    
    /// local update, values come from user, local modification date needs to be updated
    func updateObject(objectUpdateBlock: () -> (T)) -> (() -> (T))
    func objectWithIdentifier(identifier: String?) -> T?
    func newObjectFromDictionary(dictionary: [String:Any]) -> T?
    func deleteObject(object: T)
    func allUnsyncedObjects() -> [T]
    
    /// external update, new values come from server and need to update local model
    func updateObject(object: T, withDictionary dictionary: [String:Any])
    func setRecordName(recordName: String?, forObject object: T)
    func setSyncStatus(syncStatus: Bool, forObject object: T)
    func setModificationDate(modificationDate: NSDate?, forObject object: T)
    func modificationDateForObject(object: T) -> NSDate
}

public extension CKRecord {
    
    public convenience init(dictionary: [String:Any], recordType: String, zoneName: String) {
        self.init(recordType: recordType, zoneID: CKRecordZone(zoneName: zoneName).zoneID)
        self.updateWithDictionary(dictionary)
    }
    
    public func updateWithDictionary(dictionary: [String:Any]) {
        for (key, value) in dictionary {
            if let value = value as? CKRecordValue {
                self.setObject(value, forKey: key)
            }
        }
    }
    
    public func valuesDictionaryForKeys(keys: [String], syncableType: Syncable.Type) -> [String:Any]? {
        var allValues = [String:Any]()
        allValues["modificationDate"] = self.modificationDate
        for key in keys {
            if let valuesFromRecord = self.valueForKey(key) {
                allValues[key] = valuesFromRecord
            } else {
                return nil
            }
        }
        
        return allValues
    }
}

public enum RadoniCloudUserState {
    case FirstSync
    case AlreadySynced
    case Changed
}

public protocol DefaultsStoreable {
    func saveObject(object: AnyObject?, forKey key: String)
    func loadObjectForKey(key: String) -> AnyObject?
}

extension NSUserDefaults: DefaultsStoreable {
    public func saveObject(object: AnyObject?, forKey key: String) {
        self.setObject(object, forKey: key)
        self.synchronize()
    }
    
    public func loadObjectForKey(key: String) -> AnyObject? {
        return self.objectForKey(key)
    }
}

public class Radon<S: RadonStore, T:Syncable> {
    
    /// CompletionBlock: Simple typealias for a completionBlock taking an NSError optional.
    public typealias CompletionBlock = (error: NSError?) -> ()
    public typealias ErrorBlock = (error: NSError) -> ()
    
    /// queue: Defines the `dispatch_queue_t`object on which all `RadonStore` and general completion operations are executed.
    public var queue: dispatch_queue_t = dispatch_get_main_queue()
    
    public var externInsertBlock: ((syncable: S.T) -> ())? = nil
    public var internInsertBlock: ((syncable: S.T) -> ())? = nil
    
    public var externUpdateBlock: ((syncable: S.T) -> ())? = nil
    public var internUpdateBlock: ((syncable: S.T) -> ())? = nil
    
    public var externDeletionBlock: ((deletedRecordID: String?) -> ())? = nil
    public var internDeletionBlock: ((deletedRecordID: String?) -> ())? = nil
    
    public var defaultsStoreable: DefaultsStoreable = NSUserDefaults.standardUserDefaults()
    
    /// The token from the previous sync operation. It is used to determine the changes from the server since the last sync. If all data from the server should the synced, nil out this property. The token is stored in the standard `NSUserDefaults` with the key `RadonToken`.
    public var syncToken: CKServerChangeToken? {
        get {
            guard let tokenData = defaultsStoreable.loadObjectForKey(RadonTokenConstant) as? NSData,
                let token = NSKeyedUnarchiver.unarchiveObjectWithData(tokenData) as? CKServerChangeToken else  {
                    return nil
            }
            return token
        }
        
        set {
            guard let token = newValue else {
                return
            }
            
            let data = NSKeyedArchiver.archivedDataWithRootObject(token)
            defaultsStoreable.saveObject(data, forKey: RadonTokenConstant)
            
        }
    }
    
    public private(set) var isSyncing = false
    
    private let privateDatabase: CKDatabase
    private let store: S
    private let syncableName = String(T)
    private let syncableRecordZone = CKRecordZone(zoneName: String(T))
    private let container: CKContainer
    private let interface: CloudKitInterface
    
    //TODO: Initiliazer can fail, handle with throw or optional
    public init(store: S, interface: CloudKitInterface, recordZoneErrorBlock: ((error: NSError) -> ())?) {
        
        self.privateDatabase = interface.privateDatabase
        self.container = interface.container
        self.interface = interface
        
        interface.saveRecordZone(syncableRecordZone) { (zone, error) -> Void in
            if let error = error { recordZoneErrorBlock?(error: error) }
        }
        
        self.store = store
        self.subscribeToItemUpdates()
    }
    
    convenience init(store: S, cloudKitIdentifier: String) {
        self.init(store: store, interface: RadonCloudKit(cloudKitIdentifier: cloudKitIdentifier, recordZoneName: String(T)), recordZoneErrorBlock: nil)
    }
    
    
    /**
     Sync starts the general sync process. It loads recent changes and deletions from the backend and upload previously not synced objects to the backend.
     
     - parameter completion: The completionBlock, containing an optional NSError object, that is triggered when the operation finishes
     */
    public func sync(error: ErrorBlock, completion: CompletionBlock) {
        self.syncWithToken(self.syncToken, errorBlock: error, completion: completion)
    }
    
    private func syncWithToken(token: CKServerChangeToken?, errorBlock:ErrorBlock, completion: CompletionBlock) {
        isSyncing = true
        let dispatchGroup = dispatch_group_create()
        let fetchRecordChangesOperation = CKFetchRecordChangesOperation(recordZoneID: syncableRecordZone.zoneID, previousServerChangeToken: token)
        fetchRecordChangesOperation.database = self.privateDatabase
        
        fetchRecordChangesOperation.rad_setRecordChangedBlock(onQueue: self.queue) { record in
            
            if  let offlineObject = self.store.objectWithIdentifier(record.recordID.recordName) {
                if let dict = record.valuesDictionaryForKeys(T.propertyNamesToSync(), syncableType:T.self) where self.store.modificationDateForObject(offlineObject).isEarlierThan(record.modificationDate)  {
                    // Local obect needs to be updated with server record
                    self.store.setModificationDate(record.modificationDate, forObject: offlineObject)
                    self.store.setSyncStatus(true, forObject: offlineObject)
                    self.store.updateObject(offlineObject, withDictionary: dict)
                    self.externUpdateBlock?(syncable: offlineObject)
                } else  {
                    // Local version of the object is newer than the server version, update server record instead of local object.
                    dispatch_group_enter(dispatchGroup)
                    self.updateObject({ () -> S.T in
                        return offlineObject
                    }, completion: { (error) in
                        if let error = error { errorBlock(error: error) }
                        dispatch_group_leave(dispatchGroup)
                    })
                }
                
                
            } else {
                // Create local version as it is not yet present on the device
                if let dict = record.valuesDictionaryForKeys(T.propertyNamesToSync(), syncableType:T.self),
                    let newObject = self.store.newObjectFromDictionary(dict) {
                        self.store.setModificationDate(record.modificationDate, forObject: newObject)
                        self.store.setRecordName(record.recordID.recordName, forObject: newObject)
                        self.store.setSyncStatus(true, forObject: newObject)
                        self.externInsertBlock?(syncable: newObject)
                }
            }
        }
        
        fetchRecordChangesOperation.rad_setRecordWithIDWasDeletedBlock(onQueue: self.queue) { id in
            guard let offlineObject = self.store.objectWithIdentifier(id.recordName) else {
                return
            }
            
            let recordName = String(id.recordName)
            self.store.deleteObject(offlineObject)
            self.externDeletionBlock?(deletedRecordID: recordName)
        }
        
        fetchRecordChangesOperation.rad_setFetchRecordChangesCompletionBlock(onQueue: self.queue) { token, data, error in
            
            let allUnsyncedObjects = self.store.allUnsyncedObjects()
            for object in allUnsyncedObjects {
                dispatch_group_enter(dispatchGroup)
                if self.store.recordNameForObject(object) == nil {
                    // Record was not yet transfered to the server and will now be created
                    
                    self.createRecord(object, completion: { (error) -> () in
                        if let error = error { errorBlock(error: error) }
                        dispatch_group_leave(dispatchGroup)
                    })
                } else {
                    // Object was marked unsyned during an update, the server record will now be updated with new data
                    
                    self.updateObject({ () -> S.T in
                        return object
                    }, completion: { (error) -> () in
                        if let error = error { errorBlock(error: error) }
                        dispatch_group_leave(dispatchGroup)
                    })
                }
            }
            
            dispatch_group_notify(dispatchGroup, self.queue, {
                self.syncToken = token
                if error?.code == CKErrorCode.ChangeTokenExpired.rawValue {
                    self.syncToken = nil
                    //Delay execution for 3 seconds to not trigger execution limition of iCloud
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(3.0 * Double(NSEC_PER_SEC))), self.queue) { () -> Void in
                        self.syncWithToken(nil,errorBlock: errorBlock, completion: completion)
                    }
                    
                } else {
                    self.isSyncing = false
                    completion(error: error)
                    return
                }
            })
        }
        
        fetchRecordChangesOperation.start()

    }
    
    public func createObject(newObjectBlock: ((newObject: S.T) -> (S.T)), syncCompletion: CompletionBlock) {
        let newObject = self.store.newObject(newObjectBlock)()
        self.internInsertBlock?(syncable: newObject)
        self.createRecord(newObject, completion: syncCompletion)
    }
    
    private func createRecord(object: S.T, completion: CompletionBlock) {
        let dictionary = self.store.allPropertiesForObject(object)
        let record = CKRecord(dictionary: dictionary, recordType: syncableName, zoneName: syncableName)
        
        self.interface.createRecord(record, onQueue: self.queue) { (recordName, error) in
            if let recordName = recordName {
                self.store.setRecordName(recordName, forObject: object)
                self.store.setSyncStatus(true, forObject: object)
            }
            completion(error: error)
        }
    }
    
    private func recordForObject(object: S.T, success: (record: CKRecord) -> (), failure: (error: NSError) -> ()) {
        dispatch_async(self.queue) { () -> Void in
            guard let recordName = self.store.recordNameForObject(object) else {
                self.store.setSyncStatus(false, forObject: object)
                self.store.setRecordName(nil, forObject: object)
                failure(error: NSError(domain: "Radon", code: 1, userInfo: [
                    "description":"Object has not yet been synced, it will be uploaded by the next snyc"
                    ]))
                return
            }
            
            let recordID = CKRecordID(recordName: recordName, zoneID: self.syncableRecordZone.zoneID)

            self.interface.fetchRecord(recordID, onQueue: self.queue, fetchRecordsCompletionBlock: { (record, error) in
                if let record = record {
                    success(record: record)
                    return
                }
                if let error = error {
                    if error.code == CKErrorCode.UnknownItem.rawValue || error.code == CKErrorCode.PartialFailure.rawValue {
                        self.store.setSyncStatus(false, forObject: object)
                        self.store.setRecordName(nil, forObject: object)
                    }
                    failure(error: error)
                    return
                }
            })
        }

    }
    
    private func recordForRecordName(recordName: String, success: (record: CKRecord) -> (), failure: (error: NSError) -> ()) {
        let recordID = CKRecordID(recordName: recordName, zoneID: syncableRecordZone.zoneID)
        
        let fetchOperation = CKFetchRecordsOperation(recordIDs: [recordID])
        fetchOperation.database = self.privateDatabase
        fetchOperation.rad_setFetchRecordsCompletionBlock(inQueue: self.queue, fetchRecordsCompletionBlock: { recordsDictionary, error in
            if let record = recordsDictionary?[recordID] {
                success(record: record)
                return
            }
            if let error = error {
                failure(error: error)
                return
            }
        })
        
        fetchOperation.start()
    }
    
    public func updateObject(updateBlock: () -> (S.T), completion: CompletionBlock) {
        dispatch_async(self.queue) { () -> Void in
            let updatedObject = self.store.updateObject(updateBlock)()
            self.store.setModificationDate(NSDate(), forObject: updatedObject)
            self.internUpdateBlock?(syncable: updatedObject)
            self.store.setSyncStatus(false, forObject: updatedObject)
            self.recordForObject(updatedObject, success: { (record) -> () in
                let dictionary = self.store.allPropertiesForObject(updatedObject)
                record.updateWithDictionary(dictionary)
                self.interface.modifyRecord(record, onQueue: self.queue, modifyRecordsCompletionBlock: { (records, recordIDs, error) in
                    if let _ = records {
                        self.store.setSyncStatus(true, forObject: updatedObject)
                    }
                    
                    completion(error: error)
                })
                
            }) { (error) -> () in
                completion(error: error)
            }
        }
    }
    
    public func deleteObject(object: S.T, completion: CompletionBlock) {
        let recordName = self.store.recordNameForObject(object)
        self.store.deleteObject(object)
        self.internDeletionBlock?(deletedRecordID: recordName)
        if let recordName = recordName {
            self.deleteRecord(recordName, completion: completion)
        }
        
    }
    
    private func deleteRecord(recordName: String, completion: CompletionBlock) {
        let recordID = CKRecordID(recordName: recordName, zoneID: self.syncableRecordZone.zoneID)
        interface.deleteRecordWithID(recordID, onQueue: self.queue) { (error) in
            completion(error: error)
        }
    }
    
    public func handleQueryNotification(queryNotification: CKQueryNotification) {
        
        guard let recordName = queryNotification.recordID?.recordName else {
            return
        }
        
        switch queryNotification.queryNotificationReason {
        case .RecordCreated:
            self.recordForRecordName(recordName, success: { (record) -> () in
                if let dictionary = record.valuesDictionaryForKeys(T.propertyNamesToSync(), syncableType: S.T.self),
                   let syncable = self.store.newObjectFromDictionary(dictionary) {
                    self.store.setRecordName(record.recordID.recordName, forObject: syncable)
                    self.store.setSyncStatus(true, forObject: syncable)
                    self.externInsertBlock?(syncable: syncable)
                }
            }, failure: { (error) -> () in
                
            })
            
            
            return
        case .RecordUpdated:
            self.recordForRecordName(recordName, success: { (record) -> () in
                if  let syncable = self.store.objectWithIdentifier(recordName),
                    let dictionary = record.valuesDictionaryForKeys(T.propertyNamesToSync(), syncableType:T.self) {
                        self.store.updateObject(syncable, withDictionary: dictionary)
                        self.externUpdateBlock?(syncable: syncable)
                }
                
            }, failure: { (error) -> () in
                
            })
            
            return
            
            
        case .RecordDeleted:
            if let syncable = self.store.objectWithIdentifier(recordName) {
                self.store.deleteObject(syncable)
                self.externDeletionBlock?(deletedRecordID: recordName)
            }
            return
        }
    }
    
    
    public func checkIfiCloudUserChanged(success: (userStatus: RadoniCloudUserState) -> ()) {
        self.container.fetchUserRecordIDWithCompletionHandler { (recordID, error) -> Void in
            guard let currentUserID = self.loadUserID() else {
                self.saveUserID(recordID?.recordName)
                success(userStatus: .FirstSync)
                return
            }
            
            if let recordID = recordID?.recordName where recordID == currentUserID {
                success(userStatus: .AlreadySynced)
                return
            } else {
                self.saveUserID(recordID?.recordName)
                success(userStatus: .Changed)
                return
            }
        }
    }
    
    
    // MARK: - Private notification handling methods
    
    private func notificationInfo() -> CKNotificationInfo {
        let notificationInfo = CKNotificationInfo()
        notificationInfo.shouldBadge = false
        notificationInfo.shouldSendContentAvailable = true
        return notificationInfo
    }
    
    private func subscribeToItemUpdates() {
        self.saveSubscriptionWithIdent("create", options: CKSubscriptionOptions.FiresOnRecordCreation)
        self.saveSubscriptionWithIdent("update", options: CKSubscriptionOptions.FiresOnRecordUpdate)
        self.saveSubscriptionWithIdent("delete", options: CKSubscriptionOptions.FiresOnRecordDeletion)
    }
    
    private func saveSubscriptionWithIdent(ident: String, options: CKSubscriptionOptions) {
        let subscription = CKSubscription(recordType: syncableName, predicate: NSPredicate(value: true), subscriptionID: ident, options: options)
        subscription.notificationInfo = self.notificationInfo();
        self.privateDatabase.saveSubscription(subscription) { (subscription, error) -> Void in
            //TODO: handle error
        }
    }
    
    // MARK: - Private user and token handling methods
    
    private func saveUserID(userID: String?) {
        defaultsStoreable.saveObject(userID, forKey: RadoniCloudUserConstant)
    }
    
    private func loadUserID() -> String? {
        return defaultsStoreable.loadObjectForKey(RadoniCloudUserConstant) as? String
    }
    
}




