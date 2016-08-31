# Radon CloudKit Syncing
Radon CloudKit Sync provides a way to synchronise a model of an Application with the Apple CloudKit backend. Radon is only concerned with the synchronisation part and requires the implementation of two protocols that handle the individual the access to the used model and database layer in the App.

Radon is still a work in progress. Currently it handles synchronisation of every model class separately. Relationships need to be handled by the developer itself.

Radon is currently used in the App [Noteness](https://hartl.co/apps/noteness).

## Installation

### CocoaPods
Add `pod 'Radon', :git => 'https://github.com/hartlco/Radon.git'` to your Podfile. The git-path is required for now as it has not yet been published in the global pod repository.
Run `pod install`to install Radon.

### Manual
Just drag and copy the files in the `Source` folder into your project.

## Usage
A full usage guide is still `TODO:` and a lot of the APIs are still in flux as a bigger refactoring is currently happening.

To use Radon, a Store-Class needs to implement all functions defined in `RadonStore`. This Store-Class will be the connection between Radon and the database layer of your App.
Your model objects that need to be synced need to conform to the `Syncable`protocol.
You can the use the public Radon methods to sync, create, update and delete objects in your database and automatically transfer the change to CloudKit.

Everything is still experimental and a full documentation is coming.

## License
MIT
