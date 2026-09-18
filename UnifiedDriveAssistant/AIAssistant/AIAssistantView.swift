//
//  AIAssistantView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  AI ASSISTANT BLOCK — UI
//  ------------------------------------------------------------
//  Shown at the bottom of FaultDetailView, only when the user has
//  the assistant switched on. Always sits BELOW the static
//  Cause/Remedy fields — the verified data is the primary answer,
//  the assistant is supplementary explanation, never a replacement.
//  ============================================================

import SwiftUI

struct AIAssistantView: View {
    let fault: FaultCode

    @StateObject private var assistant = AIAssistantService.shared
    @State private var guidance: String?
    @State private var hasRequested = false

    var body: some View {
        if assistant.isEnabled {
            VStack(alignment: .leading, spacing: UDATheme.spacingS) {
                HStack(spacing: UDATheme.spacingXS) {
                    Image(systemName: "sparkles")
                        .foregroundColor(UDATheme.accentPressed)
                    Text("AI GUIDANCE")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                        .tracking(1)
                }

                if assistant.isLoading {
                    HStack(spacing: UDATheme.spacingS) {
                        ProgressView()
                        Text("Thinking through the fix…")
                            .font(UDATheme.caption)
                            .foregroundColor(UDATheme.textSecondary)
                    }
                    .transition(.opacity)
                } else if let guidance {
                    Text(guidance)
                        .font(UDATheme.body)
                        .foregroundColor(UDATheme.textPrimary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    Text("via \(assistant.selectedProvider.displayName)")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                } else if let error = assistant.lastError {
                    Text(error)
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                        .transition(.opacity)
                } else {
                    Button("Ask for step-by-step guidance") {
                        Task {
                            hasRequested = true
                            let result = await assistant.guidance(for: fault)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                guidance = result
                            }
                        }
                    }
                    .font(UDATheme.bodyBold)
                    .foregroundColor(UDATheme.accentPressed)
                    .transition(.opacity)
                }
            }
            .padding(UDATheme.spacingM)
            .background(UDATheme.surfaceElevated)
            .cornerRadius(UDATheme.chamferMedium)
            .animation(.easeInOut(duration: 0.25), value: assistant.isLoading)
            .animation(.easeInOut(duration: 0.25), value: guidance)
        }
    }
}
