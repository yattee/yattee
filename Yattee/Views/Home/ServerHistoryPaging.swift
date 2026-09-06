//
//  ServerHistoryPaging.swift
//  Yattee
//
//  Which page of an account's server history to ask for next.
//

import Foundation

/// Works out the next page number of a server history from what is on screen.
///
/// Its own type so the arithmetic can be reasoned about — and tested — apart
/// from the view that scrolls.
enum ServerHistoryPaging {
    /// The page to request next, given how many rows are loaded.
    ///
    /// Derived from the rows rather than counted up from the last request,
    /// because the server pages by offset and a deletion shifts every offset
    /// after it. Counting up would ask for the page after the one just read and
    /// step straight over the item that moved back across the boundary — gone
    /// for the rest of the session, one more for every further deletion. Asking
    /// for the page the loaded rows actually end in re-reads that boundary
    /// instead, and the caller's de-duplication drops what is already there.
    ///
    /// With nothing deleted this is the same number counting up would give.
    ///
    /// - Parameters:
    ///   - loadedRowCount: how many rows of this account's history are held.
    ///   - pageSize: how many IDs one request asks for.
    static func nextPage(loadedRowCount: Int, pageSize: Int) -> Int {
        guard pageSize > 0 else { return 1 }
        return max(0, loadedRowCount) / pageSize + 1
    }
}
