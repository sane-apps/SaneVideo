//
//  FocusNavigationModifier.swift
//  SaneVideo
//
//  Provides keyboard navigation support with custom focus styling
//  to replace the removed .focusable() modifiers (which caused yellow focus rings)
//

import SwiftUI

// MARK: - Focus Style Configuration

/// Configuration for custom focus styling
struct FocusStyle {
    var borderColor: Color = .accentColor
    var borderWidth: CGFloat = 2
    var cornerRadius: CGFloat = 6
    var backgroundColor: Color = .clear
    var scale: CGFloat = 1.0

    static let `default` = FocusStyle()
    static let subtle = FocusStyle(borderColor: .secondary.opacity(0.5), borderWidth: 1)
    static let button = FocusStyle(borderColor: .accentColor, borderWidth: 2, scale: 1.02)
    static let listRow = FocusStyle(borderColor: .accentColor.opacity(0.6), borderWidth: 1, backgroundColor: .accentColor.opacity(0.1))
}

// MARK: - Focusable Item Modifier

/// Makes a view focusable with custom focus styling (no yellow ring)
struct FocusableItemModifier: ViewModifier {
    let style: FocusStyle
    let onActivate: (() -> Void)?
    @FocusState private var isFocused: Bool

    init(style: FocusStyle = .default, onActivate: (() -> Void)? = nil) {
        self.style = style
        self.onActivate = onActivate
    }

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($isFocused)
            .scaleEffect(isFocused ? style.scale : 1.0)
            .background(isFocused ? style.backgroundColor : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .stroke(isFocused ? style.borderColor : .clear, lineWidth: style.borderWidth)
            )
            .onKeyPress(.return) {
                onActivate?()
                return onActivate != nil ? .handled : .ignored
            }
            .onKeyPress(.space) {
                onActivate?()
                return onActivate != nil ? .handled : .ignored
            }
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - List Navigation Modifier

/// Provides arrow key navigation for list items
struct ListNavigationModifier<Item: Identifiable>: ViewModifier {
    let items: [Item]
    @Binding var selectedId: Item.ID?
    let onSelect: ((Item) -> Void)?

    func body(content: Content) -> some View {
        content
            .onKeyPress(.upArrow) {
                selectPrevious()
                return .handled
            }
            .onKeyPress(.downArrow) {
                selectNext()
                return .handled
            }
            .onKeyPress(.return) {
                if let id = selectedId, let item = items.first(where: { $0.id == id }) {
                    onSelect?(item)
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.escape) {
                selectedId = nil
                return .handled
            }
    }

    private func selectPrevious() {
        guard !items.isEmpty else { return }
        if let currentId = selectedId,
           let currentIndex = items.firstIndex(where: { $0.id == currentId }),
           currentIndex > 0 {
            selectedId = items[currentIndex - 1].id
        } else {
            selectedId = items.last?.id
        }
    }

    private func selectNext() {
        guard !items.isEmpty else { return }
        if let currentId = selectedId,
           let currentIndex = items.firstIndex(where: { $0.id == currentId }),
           currentIndex < items.count - 1 {
            selectedId = items[currentIndex + 1].id
        } else {
            selectedId = items.first?.id
        }
    }
}

// MARK: - Sheet Navigation Modifier

/// Provides standard sheet keyboard navigation (Escape to close, Return to confirm)
struct SheetNavigationModifier: ViewModifier {
    let onCancel: (() -> Void)?
    let onConfirm: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onKeyPress(.escape) {
                onCancel?()
                return onCancel != nil ? .handled : .ignored
            }
            .onKeyPress(.return) {
                onConfirm?()
                return onConfirm != nil ? .handled : .ignored
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Makes view focusable with custom styling (replaces .focusable() which caused yellow rings)
    func keyboardFocusable(style: FocusStyle = .default, onActivate: (() -> Void)? = nil) -> some View {
        modifier(FocusableItemModifier(style: style, onActivate: onActivate))
    }

    /// Adds arrow key navigation for lists
    func listNavigation<Item: Identifiable>(
        items: [Item],
        selectedId: Binding<Item.ID?>,
        onSelect: ((Item) -> Void)? = nil
    ) -> some View {
        modifier(ListNavigationModifier(items: items, selectedId: selectedId, onSelect: onSelect))
    }

    /// Adds standard sheet keyboard navigation
    func sheetNavigation(onCancel: (() -> Void)? = nil, onConfirm: (() -> Void)? = nil) -> some View {
        modifier(SheetNavigationModifier(onCancel: onCancel, onConfirm: onConfirm))
    }
}
