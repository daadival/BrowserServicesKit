//
//  BrokenSiteReport.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
//  Implementation guidelines: https://app.asana.com/0/1198207348643509/1200202563872939/f

import Foundation
import Common

public struct BrokenSiteReport {

    public enum Mode {

        case regular
        case toggle

    }

    public enum Source: String {

        /// From the app menu's "Report Broken Site"
        case appMenu = "menu"
        /// From the privacy dashboard's "Website not working?"
        case dashboard
        /// From the app menu's "Disable Privacy Protection"
        case onProtectionsOffMenu = "on_protections_off_menu"
        /// From the privacy dashboard's on protections toggle off
        case onProtectionsOffDashboard = "on_protections_off_dashboard_main"

    }

#if os(iOS)
    public enum SiteType: String {

        case desktop
        case mobile

    }
#endif

    public static let allowedQueryReservedCharacters = CharacterSet(charactersIn: ",")

    let siteUrl: URL
    let category: String
    let description: String?
    let osVersion: String
    let manufacturer: String
    let upgradedHttps: Bool
    let tdsETag: String?
    let blockedTrackerDomains: [String]
    let installedSurrogates: [String]
    let isGPCEnabled: Bool
    let ampURL: String
    let urlParametersRemoved: Bool
    let reportFlow: Source
    let protectionsState: Bool
    var lastSentDay: String?
    let errors: [Error]?
    let httpStatusCodes: [Int]?
    let didOpenReportInfo: Bool
    let toggleReportCounter: Int?
#if os(iOS)
    let siteType: SiteType
    let atb: String
    let model: String
#endif

#if os(macOS)
    public init(
        siteUrl: URL,
        category: String,
        description: String?,
        osVersion: String,
        manufacturer: String,
        upgradedHttps: Bool,
        tdsETag: String?,
        blockedTrackerDomains: [String]?,
        installedSurrogates: [String]?,
        isGPCEnabled: Bool,
        ampURL: String,
        urlParametersRemoved: Bool,
        protectionsState: Bool,
        reportFlow: Source,
        errors: [Error]?,
        httpStatusCodes: [Int]?,
        didOpenReportInfo: Bool,
        toggleReportCounter: Int?
    ) {
        self.siteUrl = siteUrl
        self.category = category
        self.description = description
        self.osVersion = osVersion
        self.manufacturer = manufacturer
        self.upgradedHttps = upgradedHttps
        self.tdsETag = tdsETag
        self.blockedTrackerDomains = blockedTrackerDomains ?? []
        self.installedSurrogates = installedSurrogates ?? []
        self.isGPCEnabled = isGPCEnabled
        self.ampURL = ampURL
        self.protectionsState = protectionsState
        self.urlParametersRemoved = urlParametersRemoved
        self.reportFlow = reportFlow
        self.errors = errors
        self.httpStatusCodes = httpStatusCodes
        self.didOpenReportInfo = didOpenReportInfo
        self.toggleReportCounter = toggleReportCounter
    }
#endif

#if os(iOS)
    public init(
        siteUrl: URL,
        category: String,
        description: String?,
        osVersion: String,
        manufacturer: String,
        upgradedHttps: Bool,
        tdsETag: String?,
        blockedTrackerDomains: [String]?,
        installedSurrogates: [String]?,
        isGPCEnabled: Bool,
        ampURL: String,
        urlParametersRemoved: Bool,
        protectionsState: Bool,
        reportFlow: Source,
        siteType: SiteType,
        atb: String,
        model: String,
        errors: [Error]?,
        httpStatusCodes: [Int]?,
        didOpenReportInfo: Bool,
        toggleReportCounter: Int?
    ) {
        self.siteUrl = siteUrl
        self.category = category
        self.description = description
        self.osVersion = osVersion
        self.manufacturer = manufacturer
        self.upgradedHttps = upgradedHttps
        self.tdsETag = tdsETag
        self.blockedTrackerDomains = blockedTrackerDomains ?? []
        self.installedSurrogates = installedSurrogates ?? []
        self.isGPCEnabled = isGPCEnabled
        self.ampURL = ampURL
        self.protectionsState = protectionsState
        self.urlParametersRemoved = urlParametersRemoved
        self.reportFlow = reportFlow
        self.siteType = siteType
        self.atb = atb
        self.model = model
        self.errors = errors
        self.httpStatusCodes = httpStatusCodes
        self.didOpenReportInfo = didOpenReportInfo
        self.toggleReportCounter = toggleReportCounter
    }
#endif

    /// A dictionary containing all the parameters needed from the Report Broken Site Pixel
    public var requestParameters: [String: String] { getRequestParameters(forReportMode: .regular) }

    public func getRequestParameters(forReportMode mode: Mode) -> [String: String] {
        var result: [String: String] = [
            "siteUrl": siteUrl.trimmingQueryItemsAndFragment().absoluteString,
            "upgradedHttps": upgradedHttps.description,
            "tds": tdsETag?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "",
            "blockedTrackers": blockedTrackerDomains.joined(separator: ","),
            "surrogates": installedSurrogates.joined(separator: ","),
            "gpc": isGPCEnabled.description,
            "ampUrl": ampURL,
            "urlParametersRemoved": urlParametersRemoved.description,
            "os": osVersion,
            "manufacturer": manufacturer,
            "reportFlow": reportFlow.rawValue
        ]

        if mode == .regular {
            result["category"] = category
            result["description"] = description ?? ""
            result["protectionsState"] = protectionsState.description
        } else {
            result["didOpenReportInfo"] = didOpenReportInfo.description
            if let toggleReportCounter {
                result["toggleReportCounter"] = String(toggleReportCounter)
            }
        }

        if let lastSentDay = lastSentDay {
            result["lastSentDay"] = lastSentDay
        }

        if let httpStatusCodes {
            let codes: [String] = httpStatusCodes.map { String($0) }
            result["httpErrorCodes"] = codes.joined(separator: ",")
        }

        if let errors {
            let errorDescriptions: [String] = errors.map {
                let error = $0 as NSError
                return "\(error.code) - \(error.domain):\(error.localizedDescription)"
            }
            result["errorDescriptions"] = errorDescriptions.joined(separator: ",")
        }

#if os(iOS)
        result["siteType"] = siteType.rawValue
        result["atb"] = atb
        result["model"] = model
#endif
        return result
    }

}