//
//  CloudKitInterface.swift
//  Radon
//
//  Created by mhaddl on 06/05/16.
//  Copyright © 2016 Martin Hartl. All rights reserved.
//

import Foundation

public protocol Record {
    var recordName: String { get }
    var modificationDate: Date? { get }
    func valuesDictionaryForKeys(_ keys: [String], syncableType: Syncable.Type) -> [String:Any]
    func updateWithDictionary(_ dictionary: [String:Any])
}

public protocol ServerChangeToken { }

public protocol CloudInterface {
    
    associatedtype RecordType: Record
    associatedtype ChangeToken: ServerChangeToken
    
    func setup(completion: (Error?) -> Void)
    
    func createRecord(withDictionary dictionary: [String : Any], onQueue queue: DispatchQueue, createRecordCompletionBlock: @escaping ((_ recordName:String?,_ error:Error?) -> Void))
    
    func fetchRecord(_ recordName: String, onQueue queue: DispatchQueue, fetchRecordsCompletionBlock: @escaping ((RecordType?, Error?) -> Void))
    
    func modifyRecord(_ record: RecordType, onQueue queue: DispatchQueue, modifyRecordsCompletionBlock: @escaping (([RecordType]?, [String]?, Error?) -> Void))
    
    func deleteRecordWithName(_ recordName: String, onQueue queue: DispatchQueue, modifyRecordsCompletionBlock: @escaping ((Error?) -> Void))
    
    func fetchRecordChanges(onQueue queue: DispatchQueue, previousServerChangeToken: ServerChangeToken?, recordChangeBlock: @escaping ((Record) -> Void), recordWithNameWasDeletedBlock: @escaping ((String) -> Void), fetchRecordChangesCompletionBlock: @escaping ((ServerChangeToken?, Bool, Error?, Bool) -> Void))
    
    func fetchUserRecordNameWithCompletionHandler(_ completionHandler: @escaping (String?, Error?) -> Void)
}

