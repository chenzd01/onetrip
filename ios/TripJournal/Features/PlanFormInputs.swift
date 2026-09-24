import SwiftUI

struct PlanNoteInput: View {
    @Binding var text: String
    var placeholder = "例如：想坐在窗边，累了就多待一会儿。"
    var minHeight: CGFloat = 140
    @FocusState private var isFocused: Bool
    var body: some View {
        TextEditor(text: $text)
            .frame(minHeight: minHeight)
            .focused($isFocused)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).foregroundStyle(.tertiary)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .accessibilityLabel("安排备注")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if isFocused { Spacer(); Button("收起键盘") { isFocused = false } }
                }
            }
    }
}
