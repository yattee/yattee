// HTTP response status codes

enum HTTPStatus {
    // Informational responses (100 - 199)

    static let Continue = 100
    static let SwitchingProtocols = 101
    static let Processing = 102
    static let EarlyHints = 103

    // Successful responses (200 - 299)

    static let OK = 200
    static let Created = 201
    static let Accepted = 202
    static let NonAuthoritativeInformation = 203
    static let NoContent = 204
    static let ResetContent = 205
    static let PartialContent = 206
    static let MultiStatus = 207
    static let AlreadyReported = 208
    static let IMUsed = 226

    // Redirection messages (300 - 399)

    static let MultipleChoices = 300
    static let MovedPermanently = 301
    static let Found = 302
    static let SeeOther = 303
    static let NotModified = 304
    static let UseProxy = 305
    static let SwitchProxy = 306
    static let TemporaryRedirect = 307
    static let PermanentRedirect = 308

    // Client error responses (400 - 499)

    static let BadRequest = 400
    static let Unauthorized = 401
    static let PaymentRequired = 402
    static let Forbidden = 403
    static let NotFound = 404
    static let MethodNotAllowed = 405
    static let NotAcceptable = 406
    static let ProxyAuthenticationRequired = 407
    static let RequestTimeout = 408
    static let Conflict = 409
    static let Gone = 410
    static let LengthRequired = 411
    static let PreconditionFailed = 412
    static let PayloadTooLarge = 413
    static let URITooLong = 414
    static let UnsupportedMediaType = 415
    static let RangeNotSatisfiable = 416
    static let ExpectationFailed = 417
    static let IAmATeapot = 418
    static let MisdirectedRequest = 421
    static let UnprocessableEntity = 422
    static let Locked = 423
    static let FailedDependency = 424
    static let TooEarly = 425
    static let UpgradeRequired = 426
    static let PreconditionRequired = 428
    static let TooManyRequests = 429
    static let RequestHeaderFieldsTooLarge = 431
    static let UnavailableForLegalReasons = 451

    // Server error responses (500 - 599)

    static let InternalServerError = 500
    static let NotImplemented = 501
    static let BadGateway = 502
    static let ServiceUnavailable = 503
    static let GatewayTimeout = 504
    static let HTTPVersionNotSupported = 505
    static let VariantAlsoNegotiates = 506
    static let InsufficientStorage = 507
    static let LoopDetected = 508
    static let NotExtended = 510
    static let NetworkAuthenticationRequired = 511
}
