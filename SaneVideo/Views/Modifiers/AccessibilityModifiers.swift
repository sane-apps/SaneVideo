import SwiftUI

struct EnhancedAccessibilityModifier: ViewModifier {
    let label: String
    let hint: String?
    let value: String?
    let traits: AccessibilityTraits?
    
    init(
        label: String,
        hint: String? = nil,
        value: String? = nil,
        traits: AccessibilityTraits? = nil
    ) {
        self.label = label
        self.hint = hint
        self.value = value
        self.traits = traits
    }
    
    func body(content: Content) -> some View {
        content
            .accessibilityLabel(label)
            .modifyIf(hint != nil) { view in
                view.accessibilityHint(hint!)
            }
            .modifyIf(value != nil) { view in
                view.accessibilityValue(value!)
            }
            .modifyIf(traits != nil) { view in
                view.accessibilityAddTraits(traits!)
            }
    }
}

struct KeyboardNavigationModifier: ViewModifier {
    let shortcut: String?
    
    func body(content: Content) -> some View {
        content
            .modifyIf(shortcut != nil) { view in
                view.accessibilityHint("Keyboard shortcut: \(shortcut!)")
            }
    }
}

extension View {
    @ViewBuilder
    func modifyIf<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

extension View {
    func enhancedAccessibility(
        label: String,
        hint: String? = nil,
        value: String? = nil,
        traits: AccessibilityTraits? = nil
    ) -> some View {
        modifier(EnhancedAccessibilityModifier(
            label: label,
            hint: hint,
            value: value,
            traits: traits
        ))
    }
    
    func keyboardShortcutHint(_ shortcut: String) -> some View {
        modifier(KeyboardNavigationModifier(shortcut: shortcut))
    }
}
