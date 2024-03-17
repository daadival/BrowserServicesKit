//
//  AppStoreRestoreFlow.swift
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

import Foundation
import StoreKit
import Common

@available(macOS 12.0, iOS 15.0, *)
public final class AppStoreRestoreFlow {

    public typealias RestoredAccountDetails = (authToken: String, accessToken: String, externalID: String, email: String?)

    public enum Error: Swift.Error {
        case missingAccountOrTransactions
        case pastTransactionAuthenticationError
        case failedToObtainAccessToken
        case failedToFetchAccountDetails
        case failedToFetchSubscriptionDetails
        case subscriptionExpired(accountDetails: RestoredAccountDetails)
    }

    private var accountManager: AccountManaging
    private var authService: AuthServiceProtocol
    private var subscriptionService: SubscriptionServiceProtocol

    init(accountManager: AccountManaging, authService: AuthServiceProtocol, subscriptionService: SubscriptionServiceProtocol) {
        self.accountManager = accountManager
        self.authService = authService
        self.subscriptionService = subscriptionService
    }

    public func restoreAccountFromPastPurchase(subscriptionAppGroup: String) async -> Result<Void, AppStoreRestoreFlow.Error> {
        os_log(.info, log: .subscription, "[AppStoreRestoreFlow] restoreAccountFromPastPurchase")

        guard let lastTransactionJWSRepresentation = await PurchaseManager.mostRecentTransaction() else {
            os_log(.error, log: .subscription, "[AppStoreRestoreFlow] Error: missingAccountOrTransactions")
            return .failure(.missingAccountOrTransactions)
        }

        // Do the store login to get short-lived token
        let authToken: String

        switch await authService.storeLogin(signature: lastTransactionJWSRepresentation) {
        case .success(let response):
            authToken = response.authToken
        case .failure:
            os_log(.error, log: .subscription, "[AppStoreRestoreFlow] Error: pastTransactionAuthenticationError")
            return .failure(.pastTransactionAuthenticationError)
        }

        let accessToken: String
        let email: String?
        let externalID: String

        switch await accountManager.exchangeAuthTokenToAccessToken(authToken) {
        case .success(let exchangedAccessToken):
            accessToken = exchangedAccessToken
        case .failure:
            os_log(.error, log: .subscription, "[AppStoreRestoreFlow] Error: failedToObtainAccessToken")
            return .failure(.failedToObtainAccessToken)
        }

        switch await accountManager.fetchAccountDetails(with: accessToken) {
        case .success(let accountDetails):
            email = accountDetails.email
            externalID = accountDetails.externalID
        case .failure:
            os_log(.error, log: .subscription, "[AppStoreRestoreFlow] Error: failedToFetchAccountDetails")
            return .failure(.failedToFetchAccountDetails)
        }

        var isSubscriptionActive = false

        switch await subscriptionService.getSubscription(accessToken: accessToken, cachePolicy: .reloadIgnoringLocalCacheData) {
        case .success(let subscription):
            isSubscriptionActive = subscription.isActive
        case .failure:
            os_log(.error, log: .subscription, "[AppStoreRestoreFlow] Error: failedToFetchSubscriptionDetails")
            return .failure(.failedToFetchSubscriptionDetails)
        }

        if isSubscriptionActive {
            accountManager.storeAuthToken(token: authToken)
            accountManager.storeAccount(token: accessToken, email: email, externalID: externalID)
            return .success(())
        } else {
            let details = RestoredAccountDetails(authToken: authToken, accessToken: accessToken, externalID: externalID, email: email)
            os_log(.error, log: .subscription, "[AppStoreRestoreFlow] Error: subscriptionExpired")
            return .failure(.subscriptionExpired(accountDetails: details))
        }
    }
}
