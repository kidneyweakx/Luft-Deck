//
//  AppearanceSettingsView.swift
//  airmeishi
//
//  Lets users choose card accent color and glow
//

import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Card Accent Color") {
                ColorGrid()
            }

            Section("Effects") {
                Toggle("Enable Glow", isOn: $theme.enableGlow)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func ColorGrid() -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            ForEach(Array(theme.presets.enumerated()), id: \.offset) { _, color in
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .onTapGesture { theme.cardAccent = color }
                        .cardGlow(color, enabled: theme.enableGlow)
                    if color.toHexString() == theme.cardAccent.toHexString() {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(4)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationView { AppearanceSettingsView().environmentObject(ThemeManager.shared) }
}


