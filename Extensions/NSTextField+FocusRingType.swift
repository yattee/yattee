import AppKit

extension NSTextField {
    override open var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }
}
