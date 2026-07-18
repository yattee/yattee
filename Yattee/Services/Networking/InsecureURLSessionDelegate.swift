//
//  InsecureURLSessionDelegate.swift
//  Yattee
//
//  URLSessionDelegate that bypasses SSL certificate validation.
//  Used for connections to servers with self-signed or invalid certificates.
//

import Foundation

/// URLSessionDelegate that accepts all server certificates, bypassing SSL validation.
/// Only use this for trusted servers with self-signed certificates.
final class InsecureURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // For server trust challenges, accept the certificate without validation
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            // For other authentication methods, use default handling
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
