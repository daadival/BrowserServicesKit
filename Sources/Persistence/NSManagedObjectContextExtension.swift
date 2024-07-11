//
//  NSManagedObjectContextExtension.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import CoreData

public extension NSManagedObjectContext {

    enum PersistenceError: Error {
        case saveLoopError(Error?)
    }

    /*
     Utility function to help with saving changes to the database.

     If there is a timing issue (e.g. another context making changes), we may encounter merge error on save, in such case what this function does is to:
       - reset context
       - reapply changes
       - retry save

     You can expect either `onError` or `onDidSave` to be called once.
     Error thrown from within `changes` block triggers `onError` call and prevents saving.

     IMPORTANT: Due to the nature of the reset(), any reference to an actual object should be considered invalid after calling this method.
     */
    func applyChangesAndSave(changes: () throws -> Void,
                             onError: (Error) -> Void,
                             onDidSave: () -> Void) {
        assert(!hasChanges, "Context should have no changes prior to `applyChangesAndSave` call")
        
        let maxRetries = 4
        var iteration = 0

        var lastError: Error?
        while iteration < maxRetries {
            do {
                try changes()

                try save()
                onDidSave()
                return
            } catch {
                let nsError = error as NSError
                if nsError.code == NSManagedObjectMergeError || nsError.code == NSManagedObjectConstraintMergeError {
                    iteration += 1
                    lastError = error
                    self.reset()
                } else {
                    onError(error)
                    return
                }
            }
        }

        onError(PersistenceError.saveLoopError(lastError))
    }

    /*
     Utility function to help with saving changes to the database.

     If there is a timing issue (e.g. another context making changes), we may encounter merge error on save, in such case what this function does is to:
       - reset context
       - reapply changes
       - retry save

     Error thrown from within `changes` block prevent saving and is rethrown.

     IMPORTANT: Due to the nature of the reset(), any reference to an actual object should be considered invalid after calling this method.
     */
    func applyChangesAndSave(changes: () throws -> Void) throws {
        assert(!hasChanges, "Context should have no changes prior to `applyChangesAndSave` call")

        let maxRetries = 4
        var iteration = 0

        var lastMergeError: NSError?
        while iteration < maxRetries {
            do {
                try changes()
                try save()
                return
            } catch {
                let nsError = error as NSError
                if nsError.code == NSManagedObjectMergeError || nsError.code == NSManagedObjectConstraintMergeError {
                    lastMergeError = nsError
                    iteration += 1
                    reset()
                } else {
                    throw error
                }
            }
        }

        throw PersistenceError.saveLoopError(lastMergeError)
    }

}
