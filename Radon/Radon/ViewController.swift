//
//  ViewController.swift
//  Radon
//
//  Created by mhaddl on 01/11/15.
//  Copyright © 2015 Martin Hartl. All rights reserved.
//

import UIKit

class TestClassRadon {
    
    static let store = ExampleRadonStore()
    static let radon = Radon<ExampleRadonStore, TestClass>(store: store, cloudKitIdentifier: "iCloud.me.mhaddl.Radon")
}

class ViewController: UITableViewController {

    var store: ExampleRadonStore!
    var radon = Radon<ExampleRadonStore, TestClass>(store: ExampleRadonStore(), cloudKitIdentifier: "iCloud.me.mhaddl.Radon")
    
    var insertBlock: ((Syncable?, String?) -> ())?
    var updateBlock: ((Syncable?, String?) -> ())?
    var deleteBlock: ((Syncable?, String?) -> ())?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.insertBlock = { (syncable: Syncable?, recordID: String?) -> () in
            print("new syncable appended")
            self.tableView.reloadData()
        }
        
        self.updateBlock = { (syncable: Syncable?, recordID: String?) -> () in
            guard let testObject = syncable as? TestClass,
            let indexForItem = self.store.allObjects().indexOf(testObject) else {
                return
            }
            
            let indexPath = NSIndexPath(forRow: indexForItem, inSection: 0)
            self.tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
            
        }
        
        self.deleteBlock = { (syncable: Syncable?, recordID: String?) -> () in
            guard let testObject = syncable as? TestClass,
                let indexForItem = self.store.allObjects().indexOf(testObject) else {
                    return
            }
            
            let indexPath = NSIndexPath(forRow: indexForItem, inSection: 0)
            self.tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
        }
        
        self.store = TestClassRadon.store
        
        self.radon = TestClassRadon.radon
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


    @IBAction func syncButtonPressed(sender: AnyObject) {
        radon.sync({ (error) in
            
        }) { [weak self] (error) in
            self?.tableView.reloadData()
        }
    }

    @IBAction func addNoteButtonPressed(sender: AnyObject) {
        radon.createObject({ (newObject) -> (TestClass) in
            return newObject
        }) { (error) -> () in
                
        }
        self.tableView.reloadData()
        
    }
    
    // MARK: - TableViewDelegate - DataSource
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.store.allObjects().count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let note = self.store.allObjects()[indexPath.row]

        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)
        cell.textLabel?.text = note.string
        cell.detailTextLabel?.text = "\(note.int)"
        return cell
    }
    
    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return true
    }
    
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        
        let note = self.store.allObjects()[indexPath.row]
        self.radon.deleteObject(note, completion: { (error) -> () in
            if error == nil {
                self.tableView.reloadData()
            }
        })
        
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let object = self.store.allObjects()[indexPath.row]
        
        self.radon.updateObject({
            object.string = String(random())
            object.int = object.int + 1
            return object
        }) { (error) -> () in
            print("Update Record Error: \(error)")
        }
        
        
        self.tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
    }

}

