//
//  NetworkProtectionOptionKey.swift
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

public enum NetworkProtectionOptionKey {
    public static let keyValidity = "keyValidity"
    public static let selectedServer = "selectedServer"
    public static let authToken = "authToken"
    public static let isOnDemand = "is-on-demand"
    public static let activationAttemptId = "activationAttemptId"
    public static let tunnelFailureSimulation = "tunnelFailureSimulation"
    public static let tunnelFatalErrorCrashSimulation = "tunnelFatalErrorCrashSimulation"
    public static let tunnelMemoryCrashSimulation = "tunnelMemoryCrashSimulation"
    public static let includedRoutes = "includedRoutes"
    public static let excludedRoutes = "excludedRoutes"
    public static let connectionTesterEnabled = "connectionTesterEnabled"
}
public enum NetworkProtectionOptionValue {
    public static let `true` = "true" as NSString
}
