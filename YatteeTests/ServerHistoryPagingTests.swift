//
//  ServerHistoryPagingTests.swift
//  YatteeTests
//
//  Which page of a server history is asked for next, once rows have been
//  deleted out from under the offsets.
//

import Testing
import Foundation
@testable import Yattee

@Suite("Server History Paging")
struct ServerHistoryPagingTests {
    private static let pageSize = 60

    private static func nextPage(_ loadedRowCount: Int) -> Int {
        ServerHistoryPaging.nextPage(loadedRowCount: loadedRowCount, pageSize: pageSize)
    }

    @Test("Nothing loaded asks for the first page")
    func nothingLoadedAsksForTheFirstPage() {
        #expect(Self.nextPage(0) == 1)
    }

    @Test("A full page loaded asks for the second")
    func aFullPageAsksForTheSecond() {
        #expect(Self.nextPage(Self.pageSize) == 2)
    }

    @Test("Two full pages loaded ask for the third")
    func twoFullPagesAskForTheThird() {
        #expect(Self.nextPage(Self.pageSize * 2) == 3)
    }

    @Test("A row deleted out of the first page puts the boundary back in reach")
    func aDeletionRereadsTheBoundary() {
        // The server closed the gap: what was the first item of page 2 is now
        // the last of page 1, and asking for page 2 would step over it.
        #expect(Self.nextPage(Self.pageSize - 1) == 1)
    }

    @Test("Deletions across two pages come back to the page they left short")
    func deletionsAcrossPagesRereadThatPage() {
        #expect(Self.nextPage(Self.pageSize * 2 - 1) == 2)
    }

    @Test("A partly filled page still asks for the page it is in")
    func aPartialPageAsksForItself() {
        #expect(Self.nextPage(1) == 1)
        #expect(Self.nextPage(Self.pageSize + 1) == 2)
    }

    @Test("Nonsense counts still name a page that exists")
    func degenerateInputsStayValid() {
        #expect(ServerHistoryPaging.nextPage(loadedRowCount: -5, pageSize: Self.pageSize) == 1)
        #expect(ServerHistoryPaging.nextPage(loadedRowCount: 10, pageSize: 0) == 1)
    }
}
