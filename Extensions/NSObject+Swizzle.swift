extension NSObject {
    class func swizzle(origSelector: Selector, withSelector: Selector, forClass: AnyClass) {
        let originalMethod = class_getInstanceMethod(forClass, origSelector)
        let swizzledMethod = class_getInstanceMethod(forClass, withSelector)
        method_exchangeImplementations(originalMethod!, swizzledMethod!)
    }
}
