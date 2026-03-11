//
//  VoiceSelectionView.swift
//  PolishVariant
//
//  Экран выбора голоса
//

import SwiftUI

struct VoiceSelectionView: View {
    @ObservedObject var voiceManager = VoiceManager.shared
    
    // Список доступных украинских голосов
    let voices = ["Anatol", "Natalia", "Marianna", "Volodymyr"]
    
    var body: some View {
        List {
            Section(header: Text("Українські голоси")) {
                ForEach(voices, id: \.self) { voice in
                    Button(action: {
                        voiceManager.selectedVoiceIdentifier = "com.rhvoice.ukrainian.\(voice.lowercased())"
                    }) {
                        HStack {
                            Text(voice)
                                .foregroundColor(.primary)
                            Spacer()
                            if voiceManager.selectedVoiceIdentifier.contains(voice.lowercased()) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(InsetGroupedListStyle())
        #else
        .listStyle(SidebarListStyle())
        #endif
        .navigationTitle("Вибір голосу")
    }
}
