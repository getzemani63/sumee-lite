import SwiftUI
import UniformTypeIdentifiers

struct DSBiosImporterView: View {
    @ObservedObject var biosManager = DSBiosManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var showingImporter = false
    @State private var selectedType: DSBiosManager.BiosType?
    
    @State private var showConfig = false
    
    var body: some View {
        NavigationView {
             GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()
                    
    
                    VStack {
                        HStack {
                            Button(action: {
                                dismiss()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding()
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                    .zIndex(10)
                    
                    if geo.size.width > geo.size.height {
                 
                        HStack(spacing: 40) {
                  
                            VStack(alignment: .leading, spacing: 20) {
                                Spacer()
                                Text("Nintendo DS Setup")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text("To play Nintendo DS games, you legally need to dump your own BIOS files from your console and import them here.")
                                    .font(.body)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.leading)
                                
                                Text("Please do not ask about where to get the files on any of our social media channels.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(.leading, 60)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
           
                            VStack(spacing: 15) {
                                Spacer()
                                Group {
                                    BiosRow(title: "BIOS 7", filename: "bios7.bin", isPresent: biosManager.hasBios7) {
                                        selectedType = .bios7; showingImporter = true
                                    }
                                    BiosRow(title: "BIOS 9", filename: "bios9.bin", isPresent: biosManager.hasBios9) {
                                        selectedType = .bios9; showingImporter = true
                                    }
                                    BiosRow(title: "Firmware", filename: "firmware.bin", isPresent: biosManager.hasFirmware) {
                                        selectedType = .firmware; showingImporter = true
                                    }
                                }
                                
                                Spacer().frame(height: 20)
                                
                                if biosManager.areAllBiosPresent {
                                    Button(action: { showConfig = true }) {
                                        Text("Next") // Changed to Next
                                            .font(.headline).foregroundColor(.black).padding()
                                            .frame(maxWidth: .infinity).background(Color.green).cornerRadius(12)
                                    }
                                } else {
                                    Text("Please import all files to proceed.").font(.caption).foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .frame(maxWidth: 400)
                            .padding(.trailing, 40)
                        }
                    } else {
                        // --- PORTRAIT LAYOUT (Stack) ---
                        VStack(spacing: 20) {
                            Spacer()
                            Text("Nintendo DS Setup")
                                .font(.largeTitle).fontWeight(.bold).foregroundColor(.white)
                            
                            Text("To play Nintendo DS games, you legally need to dump your own BIOS files from your console and import them here.")
                                .font(.body).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal)
                            
                            Text("Please do not ask about where to get the files on any of our social media channels.")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            VStack(spacing: 15) {
                                BiosRow(title: "BIOS 7", filename: "bios7.bin", isPresent: biosManager.hasBios7) {
                                    selectedType = .bios7; showingImporter = true
                                }
                                BiosRow(title: "BIOS 9", filename: "bios9.bin", isPresent: biosManager.hasBios9) {
                                    selectedType = .bios9; showingImporter = true
                                }
                                BiosRow(title: "Firmware", filename: "firmware.bin", isPresent: biosManager.hasFirmware) {
                                    selectedType = .firmware; showingImporter = true
                                }
                            }
                            .padding()
                            
                            Spacer()
                            
                            if biosManager.areAllBiosPresent {
                                Button(action: { showConfig = true }) {
                                    Text("Next")
                                        .font(.headline).foregroundColor(.black).padding()
                                        .frame(maxWidth: .infinity).background(Color.green).cornerRadius(12)
                                }
                                .padding(.horizontal)
                            } else {
                                Text("Please import all files.").font(.caption).foregroundColor(.gray)
                            }
                            Spacer()
                        }
                    }
                    
                    // Navigation Link invisible o encapsulado
                    NavigationLink(destination: DSFirmwareConfigView(onFinish: {
                        dismiss()
                    }), isActive: $showConfig) {
                        EmptyView()
                    }
                    
                } // End ZStack
            } // End GeometryReader
            .navigationBarHidden(true)
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result: result)
            }
        } // End NavigationView
    }
    
    private func handleImport(result: Result<[URL], Error>) {
        guard let type = selectedType else { return }
        
        switch result {
        case .success(let urls):
            if let url = urls.first {
                // Simply import the file. The customization happens in the next screen.
                // Note: DSBiosManager already handles security scope using startAccessingSecurityScopedResource
                 let success = biosManager.importBios(url: url, type: type)
                 if !success {
                     print("Import BIOS failed inside manager")
                 }
            }
        case .failure(let error):
            print("Import failed: \(error.localizedDescription)")
        }
    }
}

struct BiosRow: View {
    let title: String
    let filename: String
    let isPresent: Bool
    let action: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(filename)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if isPresent {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .frame(width: 30, height: 30)
                    .foregroundColor(.green)
            } else {
                Button(action: action) {
                    Text("Import")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .cornerRadius(20)
                }
            }
        }
        .padding()
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isPresent ? Color.green : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}
