import AppKit

extension NSTextField {
    override open var focusRingType: NSFocusRingType {
        get { .none }
        set {} // swiftlint:disable:this unused_setter_value
    }
}
