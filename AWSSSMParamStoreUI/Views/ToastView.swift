import SwiftUI

enum ToastStyle {
    case info
    case error
    
    var gradient: LinearGradient {
        switch self {
        case .info:
            return LinearGradient(
                colors: [
                    Color(red: 0.3, green: 0.5, blue: 1.0),
                    Color(red: 0.5, green: 0.3, blue: 0.9)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .error:
            return LinearGradient(
                colors: [
                    Color(red: 0.9, green: 0.2, blue: 0.2),
                    Color(red: 0.8, green: 0.1, blue: 0.3)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    
    var shadowColor: Color {
        switch self {
        case .info:
            return Color(red: 0.4, green: 0.4, blue: 1.0).opacity(0.4)
        case .error:
            return Color(red: 0.9, green: 0.2, blue: 0.2).opacity(0.4)
        }
    }
    
    var defaultIcon: String {
        switch self {
        case .info:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct ToastView: View {
    let message: String
    let icon: String
    let style: ToastStyle
    var onDismiss: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon with circular background
            ZStack {
                Circle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            // Copy and Close buttons for error style
            if let onDismiss = onDismiss {
                // Copy button
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .help("Copy error message")
                
                // Close button
                Button {
                    onDismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(style.gradient)
                .shadow(color: style.shadowColor, radius: 20, x: 0, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
    }
}

// MARK: - Toast Modifier (Info - auto dismiss)

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    var icon: String = "arrow.triangle.2.circlepath"
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message = message {
                    ToastView(message: message, icon: icon, style: .info)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95, anchor: .bottom)),
                            removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottom))
                        ))
                        .zIndex(100)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: message)
    }
}

// MARK: - Error Toast Modifier (with close button)

struct ErrorToastModifier: ViewModifier {
    @Binding var message: String?
    var icon: String = "exclamationmark.triangle.fill"
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message = message {
                    ToastView(message: message, icon: icon, style: .error) {
                        self.message = nil
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95, anchor: .bottom)),
                        removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottom))
                    ))
                    .zIndex(99) // Below info toast
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: message)
    }
}

extension View {
    func toast(message: Binding<String?>, icon: String = "arrow.triangle.2.circlepath") -> some View {
        modifier(ToastModifier(message: message, icon: icon))
    }
    
    func errorToast(message: Binding<String?>, icon: String = "exclamationmark.triangle.fill") -> some View {
        modifier(ErrorToastModifier(message: message, icon: icon))
    }
}


