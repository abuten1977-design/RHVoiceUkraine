//
//  ContentView.swift
//  Ukrainian Voices for VoiceOver
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Українські голоси")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("для VoiceOver")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Divider()
                .padding()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Доступні голоси:")
                    .font(.headline)
                
                VoiceRow(name: "Anatol", gender: "чоловічий")
                VoiceRow(name: "Natalia", gender: "жіночий")
                VoiceRow(name: "Marianna", gender: "жіночий")
                VoiceRow(name: "Volodymyr", gender: "чоловічий")
            }
            .padding()
            
            Spacer()
            
            Text("Налаштування → Доступність → VoiceOver → Мова → Українська")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .padding()
    }
}

struct VoiceRow: View {
    let name: String
    let gender: String
    
    var body: some View {
        HStack {
            Image(systemName: "person.wave.2.fill")
                .foregroundColor(.blue)
            Text(name)
                .fontWeight(.medium)
            Spacer()
            Text(gender)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
