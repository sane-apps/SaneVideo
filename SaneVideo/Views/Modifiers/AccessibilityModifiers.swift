//
//  AccessibilityModifiers.swift
//  SaneVideo
//
//  Enhanced accessibility support for VoiceOver and keyboard navigation
//

import SwiftUI

/// ViewModifier that adds comprehensive accessibility support
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

/// ViewModifier for keyboard navigation hints
struct KeyboardNavigationModifier: ViewModifier {
    let shortcut: String?
    
    func body(content: Content) -> some View {
        content
            .modifyIf(shortcut != nil) { view in
                view.accessibilityHint("Keyboard shortcut: \(shortcut!)")
            }
    }
}

/// Helper extension for conditional modifiers
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
    /// Enhanced accessibility with comprehensive VoiceOver support
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
    
    /// Adds keyboard shortcut hint to accessibility
    func keyboardShortcutHint(_ shortcut: String) -> some View {
        modifier(KeyboardNavigationModifier(shortcut: shortcut))
    }
}

