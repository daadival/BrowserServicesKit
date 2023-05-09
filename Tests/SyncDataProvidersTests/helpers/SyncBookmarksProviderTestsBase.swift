//
//  SyncBookmarksProviderTestsBase.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import XCTest
import Bookmarks
import Common
import DDGSync
import Persistence
@testable import SyncDataProviders

internal class SyncBookmarksProviderTestsBase: XCTestCase {
    var bookmarksDatabase: CoreDataDatabase!
    var bookmarksDatabaseLocation: URL!
    var metadataDatabase: CoreDataDatabase!
    var metadataDatabaseLocation: URL!
    var crypter = CryptingMock()
    var provider: SyncBookmarksProvider!

    func setUpBookmarksDatabase() {
        bookmarksDatabaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = Bookmarks.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BookmarksModel") else {
            XCTFail("Failed to load model")
            return
        }
        bookmarksDatabase = CoreDataDatabase(name: className, containerLocation: bookmarksDatabaseLocation, model: model)
        bookmarksDatabase.loadStore()
    }

    func setUpSyncMetadataDatabase() {
        metadataDatabaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = DDGSync.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "SyncMetadata") else {
            XCTFail("Failed to load model")
            return
        }
        metadataDatabase = CoreDataDatabase(name: className, containerLocation: metadataDatabaseLocation, model: model)
        metadataDatabase.loadStore()
    }

    override func setUp() {
        super.setUp()

        setUpBookmarksDatabase()
        setUpSyncMetadataDatabase()

        provider = SyncBookmarksProvider(database: bookmarksDatabase, metadataStore: LocalSyncMetadataStore(database: metadataDatabase), reloadBookmarksAfterSync: {})
    }

    override func tearDown() {
        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: bookmarksDatabaseLocation)

        try? metadataDatabase.tearDown(deleteStores: true)
        metadataDatabase = nil
        try? FileManager.default.removeItem(at: metadataDatabaseLocation)
    }
}

extension SyncBookmarksProviderTestsBase {

    func fetchAllNonRootEntities(in context: NSManagedObjectContext) -> [BookmarkEntity] {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "NOT %K IN %@", #keyPath(BookmarkEntity.uuid), [BookmarkEntity.Constants.rootFolderID, BookmarkEntity.Constants.favoritesFolderID])
        request.sortDescriptors = [.init(key: #keyPath(BookmarkEntity.title), ascending: true)]
        return try! context.fetch(request)
    }

    @discardableResult
    func makeFolder(named title: String, withParent parent: BookmarkEntity? = nil, in context: NSManagedObjectContext) -> BookmarkEntity {
        let parentFolder = parent ?? BookmarkUtils.fetchRootFolder(context)!
        return BookmarkEntity.makeFolder(title: title, parent: parentFolder, context: context)
    }

    @discardableResult
    func makeBookmark(named title: String = "Bookmark", withParent parent: BookmarkEntity? = nil, in context: NSManagedObjectContext) -> BookmarkEntity {
        let parentFolder = parent ?? BookmarkUtils.fetchRootFolder(context)!
        return BookmarkEntity.makeBookmark(
            title: title,
            url: "https://www.duckduckgo.com",
            parent: parentFolder,
            context: context
        )
    }
}