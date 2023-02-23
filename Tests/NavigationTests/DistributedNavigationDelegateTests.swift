//
//  DistributedNavigationDelegateTests.swift
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

import Combine
import Common
import Swifter
import WebKit
import XCTest
@testable import Navigation

// swiftlint:disable file_length
// swiftlint:disable line_length
// swiftlint:disable function_body_length
// swiftlint:disable unused_closure_parameter
// swiftlint:disable type_body_length
// swiftlint:disable trailing_comma
// swiftlint:disable opening_brace
// swiftlint:disable force_try
// swiftlint:disable identifier_name

@available(macOS 12.0, iOS 15.0, *)
class DistributedNavigationDelegateTests: DistributedNavigationDelegateTestsBase {

    // MARK: - Basic Responder Chain

    func testWhenNavigationFinished_didFinishIsCalled() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        responder(at: 0).onNavigationResponse = { [urls] resp in
            XCTAssertTrue(resp.url.matches(urls.local))
            XCTAssertEqual(resp.isSuccessful, true)
            XCTAssertEqual(resp.httpResponse?.statusCode, 200)
            XCTAssertEqual(resp.httpResponse?.statusCode, 200)
            XCTAssertTrue(resp.canShowMIMEType)
            XCTAssertFalse(resp.shouldDownload)
            XCTAssertEqual(resp.mainFrameNavigation?.state, .responseReceived)
            XCTAssertNotNil(resp.mainFrameNavigation?.navigationResponse)
            return .next
        }
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { nav in
            XCTAssertEqual(nav.state, .finished)
            eDidFinish.fulfill()
        }
        
        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        
        // regular navigation from an empty state
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)
        
        XCTAssertFalse(navAct(1).navigationAction.isTargetingNewWindow)
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed))
        ])
    }
    
    func testWhenResponderCancelsNavigationAction_followingRespondersNotCalled() {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in }))
        )

        let eDidCancel = expectation(description: "onDidCancel")
        responder(at: 0).onNavigationAction = { _, _ in .next }
        responder(at: 1).onNavigationAction = { _, _ in
            eDidCancel.fulfill()
            return .cancel
        }
        responder(at: 2).onNavigationAction = { _, _ in XCTFail("Unexpected decidePolicyForNavigationAction:"); return .next }

        withWebView { webView in
            _=webView.load(req(urls.local1))
        }
        
        waitForExpectations(timeout: 5)
        
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1), .other, src: main()),
        ])
        assertHistory(ofResponderAt: 1, equalsToHistoryOfResponderAt: 0)
        assertHistory(ofResponderAt: 2, equalsTo: [])
    }
    
    func testWhenResponderCancelsNavigationResponse_followingRespondersNotCalled() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in }))
        )
        
        responder(at: 0).onNavigationResponse = { resp in
            XCTAssertEqual(resp.isSuccessful, false)
            XCTAssertEqual(resp.httpResponse?.statusCode, 404)
            XCTAssertEqual(resp.httpResponse?.statusCode, 404)
            return .next
        }
        responder(at: 1).onNavigationResponse = { _ in .cancel }
        responder(at: 2).onNavigationResponse = { _ in XCTFail("Unexpected decidePolicyForNavigationAction:"); return .next }
        
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 2).onDidFail = { @MainActor [urls] nav, error in
            XCTAssertEqual(error._nsError.domain, WKError.WebKitErrorDomain)
            XCTAssertTrue(nav.state.isFailed)
            XCTAssertTrue(error.isFrameLoadInterrupted)
            XCTAssertEqual(error.failingUrl?.matches(urls.local1), true)
            eDidFail.fulfill()
        }
        
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local1))
        }
        waitForExpectations(timeout: 5)
        
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local1, status: 404, mime: "text/plain", headers: ["Server": "Swifter Unspecified"]))),
            .didFail(Nav(action: navAct(1), .failed(WKError(.frameLoadInterruptedByPolicyChange)), resp: resp(0)), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local1), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(.frameLoadInterruptedByPolicyChange)), resp: resp(0)), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)
        ])
    }
    
    func testWhenNavigationFails_didFailIsCalled() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in eDidFail.fulfill() }
        
        // not calling server.start
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)
        
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail( Nav(action: navAct(1), .failed(WKError(NSURLErrorCannotConnectToHost))), NSURLErrorCannotConnectToHost)
        ])
    }
    
    func testWhenNavigationActionIsAllowed_followingRespondersNotCalled() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in }))
        )
        
        // Regular navigation without redirects
        // 1st: .next
        let eOnNavigationAction1 = expectation(description: "onNavigationAction 1")
        responder(at: 0).onNavigationAction = { _, _ in eOnNavigationAction1.fulfill(); return .next }
        // 2nd: .allow
        let eOnNavigationAction2 = expectation(description: "onNavigationAction 2")
        responder(at: 1).onNavigationAction = { _, _ in eOnNavigationAction2.fulfill(); return .allow }
        // 3rd: not called
        responder(at: 2).onNavigationAction = { _, _ in XCTFail("Unexpected navAction"); return .cancel }
        
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }
        
        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)
        
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed))
        ])
    }
    
    func testWhenNavigationResponseAllowed_followingRespondersNotCalled() throws {
        navigationDelegate.setResponders(
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in })),
            .strong(NavigationResponderMock(defaultHandler: { _ in }))
        )
        
        responder(at: 1).onNavigationResponse = { _ in return .allow }
        responder(at: 2).onNavigationResponse = { _ in XCTFail("Unexpected decidePolicyForNavigationAction:"); return .next }
        
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 2).onDidFinish = { _ in eDidFinish.fulfill() }
        
        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        
        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)
        
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed))
        ])
        assertHistory(ofResponderAt: 0, equalsToHistoryOfResponderAt: 1)
        assertHistory(ofResponderAt: 2, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed))
        ])
    }

    // MARK: - New target frame

    func testOpenInNewWindow() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        navigationDelegateProxy.finishEventsDispatchTime = .instant

        let uiDelegate = WKUIDelegateMock()
        var newWebView: WKWebView!
        uiDelegate.createWebViewWithConfig = { [unowned navigationDelegateProxy] config, _, _ in
            newWebView = WKWebView(frame: .zero, configuration: config)
            newWebView.navigationDelegate = navigationDelegateProxy
            return newWebView
        }
        withWebView { webView in
            webView.uiDelegate = uiDelegate
        }

        server.middleware = [{ [data] request in
            guard request.path == "/" else { return nil }
            return .ok(.html(data.htmlWithOpenInNewWindow.string()!))
        }, { [data, urls] request in
            guard request.path == urls.local2.path else { return nil }
            return .ok(.html(data.metaRedirect.string()!))
        }, { [data, urls] request in
            guard request.path == urls.local3.path else { return nil }
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish")
        var counter = 0
        responder(at: 0).onDidFinish = { _ in
            counter += 1
            guard counter == 3 else { return }
            eDidFinish.fulfill()
        }
        var newFrameIdentity: FrameHandle!
        responder(at: 0).onNavigationAction = { [urls, unowned webView=withWebView(do: { $0 })] navAction, _ in
            if navAction.url.path == urls.local2.path {
                XCTAssertTrue(navAction.isTargetingNewWindow)
                newFrameIdentity = navAction.targetFrame?.handle
                XCTAssertNotEqual(newFrameIdentity, webView.mainFrameHandle)
                XCTAssertTrue(navAction.targetFrame?.isMainFrame == true)
                XCTAssertNotEqual(newFrameIdentity.frameID, WKFrameInfo.defaultMainFrameHandle)
            }
            return .next
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        XCTAssertTrue(navAct(2).navigationAction.isTargetingNewWindow)
        // didFinish event may race and fire before .navigationAction(#2)
        if case .didFinish(var nav, _) = responder(at: 0).history[5] {
            responder(at: 0).history.remove(at: 5)
            XCTAssertTrue(nav.isCurrent)
            nav.isCurrent = false
            responder(at: 0).history.insert(.didFinish(nav), at: 7)
        }
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.htmlWithOpenInNewWindow.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),

            .navigationAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], src: main(urls.local),
                              targ: FrameInfo(webView: newWebView, handle: newFrameIdentity, isMainFrame: true, url: .empty, securityOrigin: urls.local.securityOrigin)),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed, isCurrent: false)),

            .didStart(Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .responseReceived, resp: .resp(urls.local2, data.metaRedirect.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .responseReceived, resp: resp(1), .committed)),
            .navigationAction(NavAction(req(urls.local3, defaultHeaders + ["Referer": urls.local2.string]), .redirect(.client), from: history[2], redirects: [navAct(2)], src: FrameInfo(webView: newWebView, handle: newFrameIdentity, isMainFrame: true, url: urls.local2, securityOrigin: urls.local.securityOrigin))),
            .didReceiveRedirect(navAct(3), Nav(action: navAct(2), .redirected(.client), resp: resp(1), .committed, isCurrent: false)),

            .didFinish(Nav(action: navAct(2), .finished, resp: resp(1), .committed, isCurrent: false)),

            .willStart(Nav(action: navAct(3), redirects: [navAct(2)], .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(3), redirects: [navAct(2)], .started)),
            .response(Nav(action: navAct(3), redirects: [navAct(2)], .responseReceived, resp: .resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(3), redirects: [navAct(2)], .responseReceived, resp: resp(2), .committed)),
            .didFinish(Nav(action: navAct(3), redirects: [navAct(2)], .finished, resp: resp(2), .committed))
        ])
    }

    func testLinkOpeningNewWindow() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        navigationDelegateProxy.finishEventsDispatchTime = .instant

        server.middleware = [{ [data] request in
            return .ok(.html(data.htmlWithOpenInNewWindowLink.string()!))
        }]
        try server.start(8084)

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eDidFinish.fulfill()
        }

        var eDidRequestNewWindow: XCTestExpectation!
        responder(at: 0).onNavigationAction = { [urls] navAction, _ in
            if navAction.url.path == urls.local2.path {
                XCTAssertTrue(navAction.isTargetingNewWindow)
                XCTAssertNil(navAction.targetFrame)
                DispatchQueue.main.async {
                    eDidRequestNewWindow.fulfill()
                }
                return .cancel
            }
            return .next
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)
        responder(at: 0).clear()

        eDidRequestNewWindow = expectation(description: "onDidRequestNewWindow")
        withWebView { webView in
            webView.evaluateJavaScript("document.getElementById('lnk').click()")
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(NavAction(req(urls.local2, defaultHeaders + ["Referer": urls.local.separatedString]), .link, from: history[1], .userInitiated, src: main(urls.local), targ: nil))
        ])
    }

    // MARK: - Reload

    func testReload() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "didFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        responder(at: 0).clear()
        eDidFinish = expectation(description: "didReload")
        withWebView { webView in
            _=webView.reload()
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local, defaultHeaders + ["Upgrade-Insecure-Requests": "1"], cachePolicy: .reloadIgnoringLocalCacheData), .reload, from: history[1], src: main(urls.local)),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart( Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .responseReceived, resp: .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, resp: resp(0), .committed))
        ])
    }

    func testJSReload() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "didFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        responder(at: 0).clear()
        eDidFinish = expectation(description: "didReload")
        withWebView { webView in
            webView.evaluateJavaScript("window.history.go(0)")
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(NavAction(req(urls.local, defaultHeaders + ["Referer": urls.local.separatedString]), .other, from: history[1], .userInitiated, src: main(urls.local))),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart( Nav(action: navAct(2), .started)),
            .response(Nav(action: navAct(2), .responseReceived, resp: .resp(urls.local, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(2), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(2), .finished, resp: resp(0), .committed))
        ])
    }

    func testReloadAfterSameDocumentNavigation() throws {
        let customCallbacksHandler = CustomCallbacksHandler()
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })), .weak(customCallbacksHandler))

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var eDidFinish = expectation(description: "#1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        responder(at: 0).onNavigationAction = { navigationAction, _ in
            return .allow
        }

        // #1 load URL
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        // #2 load URL#namedlink
        eDidFinish = expectation(description: "#2")
        customCallbacksHandler.didSameDocumentNavigation = { _, type in
            if type == .sessionStatePop { eDidFinish.fulfill() }
        }
        withWebView { webView in
            _=webView.load(req(urls.localHashed1))
        }
        waitForExpectations(timeout: 5)

        responder(at: 0).clear()
        eDidFinish = expectation(description: "didReload")
        let eNavAction = expectation(description: "onNavigationAction")
        responder(at: 0).onNavigationAction = { navigationAction, _ in
            eNavAction.fulfill()
            return .allow
        }
        withWebView { webView in
            _=webView.reload()
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(NavAction(req(urls.localHashed1, defaultHeaders + ["Upgrade-Insecure-Requests": "1"], cachePolicy: .reloadIgnoringLocalCacheData), .reload, from: history[2], src: main(urls.localHashed1))),
            .willStart(Nav(action: navAct(3), .approved, isCurrent: false)),
            .didStart( Nav(action: navAct(3), .started)),
            .response(Nav(action: navAct(3), .responseReceived, resp: .resp(urls.localHashed1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(3), .responseReceived, resp: resp(1), .committed)),
            .didFinish(Nav(action: navAct(3), .finished, resp: resp(1), .committed))
        ])
    }

    // MARK: Custom schemes

    // initial about: navigation doesn‘t wait for decidePolicyForNavigationAction
    func testAboutNavigation() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        withWebView { webView in
            _=webView.load(req(urls.aboutPrefs))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .willStart(Nav(action: .init(req(urls.aboutPrefs), .other, src: main()), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didCommit(Nav(action: navAct(1), .started, .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed))
        ])
    }

    func testAboutNavigationAfterRegularNavigation() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFinish = expectation(description: "onDidFinish 1")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]

        try server.start(8084)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        let eDidFinish2 = expectation(description: "onDidFinish 2")
        responder(at: 0).onDidFinish = { _ in eDidFinish2.fulfill() }
        withWebView { webView in
            _=webView.load(req(urls.aboutBlank))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, data.html.count))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed)),

            .navigationAction(req(urls.aboutBlank), .other, from: history[1], src: main(urls.local)),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), .started)),
            .didCommit(Nav(action: navAct(2), .started, .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
        ])
    }

    func testCustomSchemeHandlerRequest() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        testSchemeHandler.onRequest = { [responseData=data.html] task in
            task.didReceive(.response(for: task.request, mimeType: "text/html", expectedLength: responseData.count))
            task.didReceive(responseData)
            task.didFinish()
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        withWebView { webView in
            _=webView.load(req(urls.testScheme))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.testScheme), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.testScheme, status: nil, data.html.count))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed))
        ])
    }

    // MARK: - Simulated requests

    func testSimulatedRequest() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        withWebView { webView in
            _=webView.loadSimulatedRequest(req(urls.https), responseHTML: String(data: data.html, encoding: .utf8)!)
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.https), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didCommit(Nav(action: navAct(1), .started, .committed)),
            .didFinish(Nav(action: navAct(1), .finished, .committed))
        ])
    }

    func testSimulatedRequestAfterCustomSchemeRequest() {
        navigationDelegateProxy.finishEventsDispatchTime = .instant
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        testSchemeHandler.onRequest = { [unowned webView=withWebView(do: { $0 }), data, urls] task in
            webView.loadSimulatedRequest(req(urls.https), responseHTML: String(data: data.html, encoding: .utf8)!)
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        responder(at: 0).onDidFail = { [urls] _, error in
            XCTAssertEqual(error._nsError.domain, NSURLErrorDomain)
            XCTAssertTrue(error.isNavigationCancelled)
            XCTAssertEqual(error.failingUrl?.matches(urls.testScheme), true)
        }

        withWebView { webView in
            _=webView.load(req(urls.testScheme))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.testScheme), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled),

            .navigationAction(req(urls.https), .other, src: main()),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), .started)),
            .didCommit(Nav(action: navAct(2), .started, .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
        ])
    }

    func testSimulatedRequestAfterCustomSchemeRequestWithFailureBeforeWillStartNavigation() {
        // receive didFailProvisionalNavigation AFTER decidePolicyForNavigationAction for loadSimulatedRequest (works different in runtime than in tests)
        navigationDelegateProxy.finishEventsDispatchTime = .beforeWillStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        testSchemeHandler.onRequest = { [unowned webView=withWebView(do: { $0 }), data, urls] task in
            webView.loadSimulatedRequest(req(urls.https), responseHTML: String(data: data.html, encoding: .utf8)!)
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        withWebView { webView in
            _=webView.load(req(urls.testScheme))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.testScheme), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.https), .other, src: main()),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled),

            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), .started)),
            .didCommit(Nav(action: navAct(2), .started, .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
        ])
    }

    func testSimulatedRequestAfterCustomSchemeRequestWithFailureAfterWillStartNavigation() {
        // receive didFailProvisionalNavigation AFTER decidePolicyForNavigationAction for loadSimulatedRequest (because it works different in runtime than in tests)
        navigationDelegateProxy.finishEventsDispatchTime = .afterWillStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        testSchemeHandler.onRequest = { [unowned webView=withWebView(do: { $0 }), data, urls] task in
            webView.loadSimulatedRequest(req(urls.https), responseHTML: String(data: data.html, encoding: .utf8)!)
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        withWebView { webView in
            _=webView.load(req(urls.testScheme))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.testScheme), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.https), .other, src: main()),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled)), isCurrent: false), NSURLErrorCancelled),

            .didStart(Nav(action: navAct(2), .started)),
            .didCommit(Nav(action: navAct(2), .started, .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
        ])
    }

    func testSimulatedRequestAfterCustomSchemeRequestWithFailureAfterDidStartNavigation() {
        // receive didFailProvisionalNavigation AFTER decidePolicyForNavigationAction for loadSimulatedRequest (works different in runtime than in tests)
        navigationDelegateProxy.finishEventsDispatchTime = .afterDidStartNavigationAction
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        testSchemeHandler.onRequest = { [unowned webView=withWebView(do: { $0 }), data, urls] task in
            webView.loadSimulatedRequest(req(urls.https), responseHTML: String(data: data.html, encoding: .utf8)!)
        }

        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        withWebView { webView in
            _=webView.load(req(urls.testScheme))
        }
        waitForExpectations(timeout: 5)

        if case .didFail = responder(at: 0).history[5] {
            responder(at: 0).history.insert(responder(at: 0).history.remove(at: 5), at: 6)
        }
        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.testScheme), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),

            .navigationAction(req(urls.https), .other, src: main()),
            .willStart(Nav(action: navAct(2), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(2), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled)), isCurrent: false), NSURLErrorCancelled),

            .didCommit(Nav(action: navAct(2), .started, .committed)),
            .didFinish(Nav(action: navAct(2), .finished, .committed))
        ])
    }

    func testRealRequestAfterCustomSchemeRequest() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        testSchemeHandler.onRequest = { [data, urls] task in
            task.didReceive(.response(for: req(urls.local1)))
            task.didReceive(data.html)
            task.didFinish()
        }
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }
        withWebView { webView in
            _=webView.load(req(urls.testScheme))
        }

        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.testScheme), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local1, status: nil, data.empty.count))),
            .didCommit(Nav(action: navAct(1), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(1), .finished, resp: resp(0), .committed))
        ])
    }

    // MARK: - Stop loading

    func testStopLoadingBeforeWillStart() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        responder(at: 0).onNavigationAction = { [unowned webView=withWebView(do: { $0 })] _, _ in
            webView.stopLoading()
            return .next
        }
        let eStopped = expectation(description: "loading stopped")
        responder(at: 0).onDidFail = { _, _ in
            eStopped.fulfill()
        }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled)), isCurrent: false), NSURLErrorCancelled)
        ])
    }

    func testStopLoadingAfterWillStart() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        responder(at: 0).onWillStart = { [unowned webView=withWebView(do: { $0 })] _ in
            DispatchQueue.main.async {
                webView.stopLoading()
            }
        }
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in eDidFail.fulfill() }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled)
        ])
    }

    func testStopLoadingAfterDidStart() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        responder(at: 0).onDidStart = { [unowned webView=withWebView(do: { $0 })] _ in
            webView.stopLoading()
        }
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in eDidFail.fulfill() }

        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .didFail(Nav(action: navAct(1), .failed(WKError(NSURLErrorCancelled))), NSURLErrorCancelled)
        ])
    }

    func testStopLoadingAfterResponse() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        server.middleware = [{ [data] request in
            return .ok(.data(data.html))
        }]
        try server.start(8084)

        responder(at: 0).onNavigationResponse = { [unowned webView=withWebView(do: { $0 })] _ in
            webView.stopLoading()
            return .next
        }
        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { _, _ in eDidFail.fulfill() }
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local, status: 200, data.html.count))),
            .didFail(Nav(action: navAct(1), .failed(WKError(.frameLoadInterruptedByPolicyChange)), resp: resp(0)), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)
        ])
    }

    // MARK: - Task Cancellation

    func testWhenNavigationActionResponderTakesLongToReturnDecisionAndAnotherNavigationComesInBeforeItThenTaskIsCancelled() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        var unlock: (() -> Void)!
        let f = Future<Void, Never> { promise in
            unlock = { promise(.success(())) }
        }

        let eOnNavAction1 = expectation(description: "onNavigationAction 1")
        var eOnNavAction1_1: XCTestExpectation!
        responder(at: 0).onNavigationAction = { _, _ in
            eOnNavAction1.fulfill()
            _=await f.value
            XCTAssertTrue(Task.isCancelled)
            defer {
                eOnNavAction1_1.fulfill()
            }
            return .allow
        }

        // run first request (will wait in async onNavigationAction)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        // when wait for the first decision has started run a second request
        let eOnNavAction2 = expectation(description: "onNavigationAction 2")
        responder(at: 0).onNavigationAction = { _, _ in
            eOnNavAction2.fulfill()
            XCTAssertFalse(Task.isCancelled)
            return .cancel
        }

        withWebView { webView in
            _=webView.load(req(urls.local2))
        }
        waitForExpectations(timeout: 5)

        // #1 navigation will fail on unlock
        eOnNavAction1_1 = expectation(description: "onNavigationAction 1_1")
        unlock()
        waitForExpectations(timeout: 1)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .navigationAction(req(urls.local2), .other, src: main()),
        ])
    }

    func testWhenRedirectNavigationActionResponderTakesLongToReturnDecisionAndAnotherNavigationComesInBeforeItThenTaskIsCancelled() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        navigationDelegateProxy.finishEventsDispatchTime = .afterWillStartNavigationAction

        server.middleware = [{ [urls, data] request in
            guard request.path == "/" else { return nil }

            return .raw(301, "Moved", ["Location": urls.local2.path]) { writer in
                try! writer.write(data.empty)
            }
        }, { [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        var unlock: (() -> Void)!
        let f = Future<Void, Never> { promise in
            unlock = { promise(.success(())) }
        }

        let eOnNavAction1 = expectation(description: "onNavigationAction 1")
        var eOnNavAction1_1: XCTestExpectation!
        responder(at: 0).onNavigationAction = { [urls] action, _ in
            if action.url.matches(urls.local2) {
                eOnNavAction1.fulfill()
                _=await f.value
                XCTAssertTrue(Task.isCancelled)
                eOnNavAction1_1.fulfill()
            }
            return .allow
        }

        // run first request (will wait in async onNavigationAction)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        // when wait for the first decision has been redirected run a second request
        let eOnDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in
            eOnDidFinish.fulfill()
        }
        withWebView { webView in
            _=webView.load(req(urls.local3))
        }
        waitForExpectations(timeout: 5)

        eOnNavAction1_1 = expectation(description: "onNavigationAction 1_1")
        unlock()
        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .navigationAction(req(urls.local2, defaultHeaders + ["Accept-Encoding": "gzip, deflate", "Accept-Language": "en-XX,en;q=0.9", "Upgrade-Insecure-Requests": "1"]), .redirect(.server), redirects: [navAct(1)], src: main()),

            .navigationAction(req(urls.local3), .other, src: main()),
            .willStart(Nav(action: navAct(3), .approved, isCurrent: false)),

            .didFail(Nav(action: navAct(2), redirects: [navAct(1)], .failed(WKError(.frameLoadInterruptedByPolicyChange)), isCurrent: false), WKError.Code.frameLoadInterruptedByPolicyChange.rawValue),

            .didStart(Nav(action: navAct(3), .started)),
            .response(Nav(action: navAct(3), .responseReceived, resp: .resp(urls.local3, data.html.count, headers: .default + ["Content-Type": "text/html"]))),
            .didCommit(Nav(action: navAct(3), .responseReceived, resp: resp(0), .committed)),
            .didFinish(Nav(action: navAct(3), .finished, resp: resp(0), .committed))
        ])
    }

    func testWhenNavigationActionDecisionCancelledThenNextResponderIsNotCalled() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })),
                                         .strong(NavigationResponderMock(defaultHandler: { _ in })))

        var unlock: (() -> Void)!
        let f = Future<Void, Never> { promise in
            unlock = { promise(.success(())) }
        }

        let eOnNavAction1 = expectation(description: "onNavigationAction 1")
        responder(at: 0).onNavigationAction = { _, _ in
            eOnNavAction1.fulfill()
            _=await f.value
            XCTAssertTrue(Task.isCancelled)
            return .next
        }
        responder(at: 1).onNavigationAction = { _, _ in
            XCTFail("should never receive onNavigationAction")
            return .next
        }

        // run first request (will wait in async onNavigationAction)
        withWebView { webView in
            _=webView.load(req(urls.local))
        }
        waitForExpectations(timeout: 5)

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        // when wait for the first decision has started run a second request
        let eOnNavAction2 = expectation(description: "onNavigationAction 2")
        responder(at: 0).onNavigationAction = { _, _ in
            eOnNavAction2.fulfill()
            XCTAssertFalse(Task.isCancelled)
            return .cancel
        }
        withWebView { webView in
            _=webView.load(req(urls.local2))
        }
        waitForExpectations(timeout: 5)

        unlock()

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local), .other, src: main()),
            .navigationAction(req(urls.local2), .other, src: main()),
        ])
    }

    func testWhenWebContentProcessIsTerminated_webProcessDidTerminateAndNavigationDidFailReceived() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        responder(at: 0).onNavigationResponse = { [unowned webView=withWebView(do: { $0 })] _ in
            webView.perform(NSSelectorFromString("_killWebContentProcess"))
            return .next
        }

        let eDidFail = expectation(description: "onDidFail")
        responder(at: 0).onDidFail = { @MainActor nav, error in
            XCTAssertTrue(nav.isCurrent)
            XCTAssertEqual(error.userInfo[WKProcessTerminationReason.userInfoKey] as? WKProcessTerminationReason, WKProcessTerminationReason.crash)

            eDidFail.fulfill()
        }

        server.middleware = [{ [data] request in
            return .ok(.html(data.html.string()!))
        }]
        try server.start(8084)

        withWebView { webView in
            _=webView.load(req(urls.local1))
        }

        waitForExpectations(timeout: 5)

        assertHistory(ofResponderAt: 0, equalsTo: [
            .navigationAction(req(urls.local1), .other, src: main()),
            .willStart(Nav(action: navAct(1), .approved, isCurrent: false)),
            .didStart(Nav(action: navAct(1), .started)),
            .response(Nav(action: navAct(1), .responseReceived, resp: .resp(urls.local1, data.html.count, headers: .default + ["Content-Type": "text/html"]))),

            .didTerminate(.crash),
            .didFail(Nav(action: navAct(1), .failed(WKError(.webContentProcessTerminated)), resp: resp(0)), WKError.Code.webContentProcessTerminated.rawValue)
        ])
    }

}