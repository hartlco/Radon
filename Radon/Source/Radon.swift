//
//  Radon.swift
//  Radon
//
//  Created by hartlco on 01/11/15.
//  Copyright © 2015 Martin Hartl. All rights reserved.
//

import Foundation
import CloudKit

private let RadonTokenConstant = "RadonToken"
private let RadoniCloudUserConstant = "RadoniCloudUserConstant"

extension Date {
    /**
     Basic comparison if the date self is smaller than the date given as the argument.
     
     - parameter date: NSDate optional used to compare.
     
     - returns: Boolean value indicating if the date self is smaller than the date in the argument. If the argument is nil, `false` is returned.
     */
    func isEarlierThan(_ date: Date?) -> Bool {
        guard let date = date else {
            return false
        }
        
        return self.compare(date) == .orderedAscending
    }
}

public enum RadoniCloudUserState {
    case firstSync
    case alreadySynced
    case changed
}

public protocol DefaultsStoreable {
    func saveObject(_ object: Any?, forKey key: String)
    func loadObjectForKey(_ key: String) -> Any?
}

extension UserDefaults: DefaultsStoreable {
    public func saveObject(_ object: Any?, forKey key: String) {
        self.set(object, forKey: key)
        self.synchronize()
    }
    
    public func loadObjectForKey(_ key: String) -> Any? {
        return self.object(forKey: key)
    }
}

open class Radon<S: RadonStore, T:Syncable, InterfaceType: CloudKitInterface> {
    
    /// CompletionBlock: Simple typealias for a completionBlock taking an NSError optional.
    public typealias CompletionBlock = (_ error: Error?) -> ()
    public typealias ErrorBlock = (_ error: Error) -> ()
    
    
    /// queue: Defines the `dispatch_queue_t`object on which all `RadonStore` and general completion operations are executed.
    open var queue: DispatchQueue = DispatchQueue.main
    
    
    /// externInsertBlock: If this block is set, it's triggered every time a new, unkown object was inserted from the backend
    open var externInsertBlock: ((_ syncable: S.T) -> ())? = nil
    
    
    /// externUpdateBlock: If this block is set, it's triggered every time a already existing object received an update from the backend.
    open var externUpdateBlock: ((_ syncable: S.T) -> ())? = nil
    
    
    /// externDeletionBlock: If this block is set, it's triggered every time a existing object was deleted from the backend and got deleted by Radion
    open var externDeletionBlock: ((_ deletedRecordName: String?) -> ())? = nil
    
    
    open var defaultsStoreable: DefaultsStoreable = UserDefaults.standard
    
    /// The token from the previous sync operation. It is used to determine the changes from the server since the last sync. If all data from the server should the synced, nil out this property. The token is stored in the standard `NSUserDefaults` with the key `RadonToken`.
    open var syncToken: ServerChangeToken? {
        get {
            //TODO: Test if token is correctly saved and loaded
            guard let tokenData = defaultsStoreable.loadObjectForKey(RadonTokenConstant) as? Data,
                let token = NSKeyedUnarchiver.unarchiveObject(with: tokenData) as? ServerChangeToken else  {
                    return nil
            }
            return token
        }
        
        set {
            guard let token = newValue else {
                return
            }
            
            let data = NSKeyedArchiver.archivedData(withRootObject: token)
            defaultsStoreable.saveObject(data as AnyObject?, forKey: RadonTokenConstant)
            
        }
    }
    
    open fileprivate(set) var isSyncing = false
    
    fileprivate let store: S
    fileprivate let syncableName = String(describing: T.self)
    fileprivate let interface: InterfaceType
    
    //TODO: Initiliazer can fail, handle with throw or optional
    public init(store: S, interface: InterfaceType, recordZoneErrorBlock: ((_ error: Error) -> ())?) {
        
        self.interface = interface
        
        interface.setup { (error) in
            if let error = error { recordZoneErrorBlock?(error) }
        }
        
        self.store = store
    }
    
    public convenience init(store: S, cloudKitIdentifier: String) {
        //TODO: fix cast
        let interface: InterfaceType = RadonCloudKit(cloudKitIdentifier: cloudKitIdentifier, recordZoneName: String(describing: T.self), syncableName: String(describing: T.self)) as! InterfaceType
        self.init(store: store, interface: interface, recordZoneErrorBlock: nil)
    }
    
    
    // MARK: - Public methods
    
    
    /**
     Sync starts the general sync process. It loads recent changes and deletions from the backend and upload previously not synced objects to the backend.
     
     - parameter error: Error block that may execute if an error during the sync occurs
     - parameter completion: The completionBlock, containing an optional NSError object, that is triggered when the operation finishes
     */
    open func sync(_ error: @escaping ErrorBlock, completion: @escaping CompletionBlock) {
        self.syncWithToken(self.syncToken, errorBlock: error, completion: completion)
    }
    
    
    /**
     Creates a new object that is available in the 'newObjectBlock'. Changes made to the object in this block are stored in the local store and
        uploaded to the CloudKit server.
     
     - parameter newObjectBlock: Block that provides a  new object. After changing the object in needs to be return in the block
     - parameter completion: Block that is executed after the object was sucessfully created in the CloudKit backend
 
     */
    open func createObject(_ newObjectBlock: @escaping ((_ newObject: S.T) -> (S.T)), completion: @escaping CompletionBlock) {
        let newObject = self.store.newObject(newObjectBlock)()
        self.createRecord(newObject, completion: completion)
    }
    
    
    /**
     
 
     */
    open func updateObject(_ updateBlock: @escaping () -> (S.T), completion: @escaping CompletionBlock) {
        self.queue.async { () -> Void in
            let updatedObject = self.store.updateObject(updateBlock)()
            self.store.setModificationDate(Date(), forObject: updatedObject)
            self.store.setSyncStatus(false, forObject: updatedObject)
            self.recordForObject(updatedObject, success: { (record) -> () in
                let dictionary = self.store.allPropertiesForObject(updatedObject)
                record.updateWithDictionary(dictionary)
                self.interface.modifyRecord(record, onQueue: self.queue, modifyRecordsCompletionBlock: { (records, recordIDs, error) in
                    if let _ = records {
                        self.store.setSyncStatus(true, forObject: updatedObject)
                    }
                    
                    completion(error)
                })
                
            }) { (error) -> () in
                completion(error)
            }
        }
    }
    
    open func deleteObject(_ object: S.T, completion: @escaping CompletionBlock) {
        let recordName = self.store.recordNameForObject(object)
        self.store.deleteObject(object)
        if let recordName = recordName {
            self.deleteRecord(recordName, completion: completion)
        }
    }
    
    open func handleQueryNotification(_ queryNotification: CKQueryNotification) {
        guard let recordID = queryNotification.recordID else { return }
        self.handleQueryNotificationReason(queryNotification.queryNotificationReason, forRecordName: recordID.recordName)
    }
    
    open func checkIfiCloudUserChanged(_ success: @escaping (_ userStatus: RadoniCloudUserState) -> ()) {
        self.interface.fetchUserRecordNameWithCompletionHandler { (recordName, error) in
            guard let currentUserID = self.loadUserRecordName() else {
                self.saveUserRecordName(recordName)
                success(.firstSync)
                return
            }
            
            if let recordID = recordName , recordID == currentUserID {
                success(.alreadySynced)
            } else {
                self.saveUserRecordName(recordName)
                success(.changed)
            }
        }
    }
    
    // MARK: - Internal methods for Unit tests
    
    internal func handleRecordChangeInSync(_ record: Record) {
        if let offlineObject = self.store.objectWithIdentifier(record.recordID.recordName) {
            //TODO: Add optional conflict block to handle this situation
            if self.store.modificationDateForObject(offlineObject).isEarlierThan(record.modificationDate)  {
                // Local object needs to be updated with server record
                let dict = record.valuesDictionaryForKeys(T.propertyNamesToSync(), syncableType:T.self)
                self.store.setModificationDate(record.modificationDate, forObject: offlineObject)
                self.store.setSyncStatus(true, forObject: offlineObject)
                self.store.updateObject(offlineObject, withDictionary: dict)
                self.externUpdateBlock?(offlineObject)
            } else  {
                // Local version of the object is newer than the server version. Mark it as unsynced so it will be synced in the end.
                self.store.setSyncStatus(false, forObject: offlineObject)
            }
            
        } else {
            // Create local version as it is not yet present on the device
            self.insertObject(fromRecord: record)
        }
    }
    
    internal func createOrUpdateUnsyncedObjectsInSync(completion: @escaping (_ errors: [Error]) -> ()) {
        let dispatchGroup = DispatchGroup()
        var errors = [Error]()
        
        for object in self.store.allUnsyncedObjects() {
            dispatchGroup.enter()
            if self.store.recordNameForObject(object) == nil {
                // Record was not yet transfered to the server and will now be created
                self.createRecord(object, completion: { (error) -> () in
                    if let error = error { errors.append(error) }
                    dispatchGroup.leave()
                })
            } else {
                // Object was marked unsyned during an update, the server record will now be updated with new data
                self.updateObject({ () -> S.T in
                    return object
                }, completion: { (error) -> () in
                    if let error = error { errors.append(error) }
                    dispatchGroup.leave()
                })
            }
        }
        
        dispatchGroup.notify(queue: self.queue, execute: {
            completion(errors)
        })
    }
    
    // MARK: - Private methods
    
    fileprivate func syncWithToken(_ token: ServerChangeToken?, errorBlock: @escaping ErrorBlock, completion: @escaping CompletionBlock) {
        isSyncing = true
        
        self.interface.fetchRecordChanges(onQueue: self.queue, previousServerChangeToken: token, recordChangeBlock: { [weak self] (record) in
            self?.handleRecordChangeInSync(record)
        }, recordWithNameWasDeletedBlock: { [weak self] recordName in
            guard let offlineObject = self?.store.objectWithIdentifier(recordName) else { return }
            let recordName = recordName
            self?.store.deleteObject(offlineObject)
            self?.externDeletionBlock?(recordName)
        }, fetchRecordChangesCompletionBlock: { [weak self] (token, moreComing, error, needsCleanSync) in
            self?.createOrUpdateUnsyncedObjectsInSync(completion: { errors in
                //TODO: handle errors array
                
                self?.syncToken = token
                if needsCleanSync {
                    self?.syncToken = nil
                    //Delay execution for 3 seconds to not trigger execution limition of iCloud
                    self?.queue.asyncAfter(deadline: DispatchTime.now() + Double(Int64(3.0 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)) { () -> Void in
                        self?.syncWithToken(nil,errorBlock: errorBlock, completion: completion)
                    }

                } else {
                    self?.isSyncing = false
                    completion(error)
                    return
                }
            })
                
        })

    }
    
    fileprivate func createRecord(_ object: S.T, completion: @escaping CompletionBlock) {
        let dictionary = self.store.allPropertiesForObject(object)
        
        self.interface.createRecord(withDictionary: dictionary, onQueue: self.queue) { (recordName, error) in
            if let recordName = recordName {
                self.store.setRecordName(recordName, forObject: object)
                self.store.setSyncStatus(true, forObject: object)
            }
            completion(error)
        }
    }
    
    fileprivate func recordForObject(_ object: S.T, success: @escaping (_ record: InterfaceType.RecordType) -> (), failure: @escaping (_ error: Error) -> ()) {
        self.queue.async { () -> Void in
            guard let recordName = self.store.recordNameForObject(object) else {
                self.store.setSyncStatus(false, forObject: object)
                self.store.setRecordName(nil, forObject: object)
                failure(NSError(domain: "Radon", code: 1, userInfo: [
                    "description":"Object has not yet been synced, it will be uploaded by the next snyc"
                    ]))
                return
            }

            self.interface.fetchRecord(recordName, onQueue: self.queue, fetchRecordsCompletionBlock: { (record, error) in
                if let record = record {
                    success(record)
                    return
                }
                if let error = error {
                    self.store.setSyncStatus(false, forObject: object)
                    self.store.setRecordName(nil, forObject: object)
                    failure(error)
                    return
                }
            })
        }

    }
    
    fileprivate func deleteRecord(_ recordName: String, completion: @escaping CompletionBlock) {
        interface.deleteRecordWithName(recordName, onQueue: self.queue) { (error) in
            completion(error)
        }
    }
    
    fileprivate func insertObject(fromRecord record:Record) {
        let dictionary = record.valuesDictionaryForKeys(T.propertyNamesToSync(), syncableType:T.self)
        let newObject = self.store.newObjectFromDictionary(dictionary)
        self.store.setModificationDate(record.modificationDate, forObject: newObject)
        self.store.setRecordName(record.recordID.recordName, forObject: newObject)
        self.store.setSyncStatus(true, forObject: newObject)
        self.externInsertBlock?(newObject)
    }
    
    internal func handleQueryNotificationReason(_ reason: CKQueryNotificationReason, forRecordName recordName: String) {
        switch reason {
        case .recordCreated:
            self.interface.fetchRecord(recordName, onQueue: self.queue, fetchRecordsCompletionBlock: { [weak self] (record, error) in
                guard let record = record else { return }
                self?.insertObject(fromRecord: record)
            })
            
            return
        case .recordUpdated:
            self.interface.fetchRecord(recordName, onQueue: self.queue, fetchRecordsCompletionBlock: { [weak self] (record, error) in
                guard let record = record,
                let syncable = self?.store.objectWithIdentifier(recordName) else { return }
                let dictionary = record.valuesDictionaryForKeys(T.propertyNamesToSync(), syncableType:T.self)
                self?.store.updateObject(syncable, withDictionary: dictionary)
                self?.externUpdateBlock?(syncable)
            })
            
            return
        case .recordDeleted:
            if let syncable = self.store.objectWithIdentifier(recordName) {
                self.store.deleteObject(syncable)
                self.externDeletionBlock?(recordName)
            }
            return
        }
    }
    
    // MARK: - Private user and token handling methods
    
    fileprivate func saveUserRecordName(_ userID: String?) {
        defaultsStoreable.saveObject(userID as AnyObject?, forKey: RadoniCloudUserConstant)
    }
    
    fileprivate func loadUserRecordName() -> String? {
        return defaultsStoreable.loadObjectForKey(RadoniCloudUserConstant) as? String
    }
    
}




