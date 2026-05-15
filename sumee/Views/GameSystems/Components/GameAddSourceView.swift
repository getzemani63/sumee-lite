import SwiftUI

struct GameAddSourceView: View {
    var onAddFile: () -> Void
    var onAddManicEmu: (String, String) -> Void
    
    @State private var manicName: String = ""
    @State private var manicURL: String = ""
    
    @State private var isIntegrationsExpanded: Bool = false
    @State private var isManicExpanded: Bool = false
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Native Import")) {
                    Button(action: onAddFile) {
                        Label("Import from Files", systemImage: "folder")
                            .font(.headline)
                            .padding(.vertical, 4)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Supported formats:")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        
                        Group {
                            Text("Nintendo DS: .nds")
                            Text("Nintendo 64: .n64, .z64")
                            Text("Game Boy Advance: .gba")
                            Text("Game Boy / Color: .gb, .gbc")
                            Text("NES: .nes")
                            Text("SNES: .sfc, .smc")
                            Text("Genesis/Mega Drive: .gen, .md, .bin")
                            Text("PlayStation: .bin/.cue, .pbp, .chd")
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Other Sources")) {
                    DisclosureGroup(isExpanded: $isIntegrationsExpanded) {
                        // iOS Apps
                        HStack(alignment: .top, spacing: 16) {
                            Image("cart_ios")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .cornerRadius(8)
                                .padding(.top, 4)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("iOS Apps")
                                    .font(.headline)
                                (Text("1. Long press app on Home Screen\n2. Tap 'Share App' ") +
                                 Text(Image(systemName: "square.and.arrow.up")) +
                                 Text("\n3. Select 'SUMEE! Lite'"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        // MeloNX (TEMPORARILY DISABLED)
                        // HStack(alignment: .top, spacing: 16) {
                        //     Image("cart_melonx")
                        //         .resizable()
                        //         .aspectRatio(contentMode: .fit)
                        //         .frame(width: 32, height: 32)
                        //         .cornerRadius(8)
                        //         .padding(.top, 4)
                        //     
                        //     VStack(alignment: .leading, spacing: 4) {
                        //         Text("MeloNX Games")
                        //             .font(.headline)
                        //         Text("1. Go to 'Add-ons' menu in SUMEE! Lite\n2. Add 'MeloNX' add-on\n3. Library syncs automatically")
                        //             .font(.caption)
                        //             .foregroundColor(.secondary)
                        //             .fixedSize(horizontal: false, vertical: true)
                        //     }
                        // }
                        // .padding(.vertical, 8)
                        
                        // Web ROMs
                        HStack(alignment: .top, spacing: 16) {
                            Image("icon_MiBrowser")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .cornerRadius(8) // Optional: rounded corners for app icon look
                                .padding(.top, 4)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Web ROMs")
                                    .font(.headline)
                                (Text("1. Install 'MiBrowser' from Add-ons\n2. Navigate to your game\n3. Tap ") +
                                 Text(Image(systemName: "gamecontroller")) +
                                 Text(" in the bottom menu"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 8)
                    } label: {
                        // Label("Integrations (iOS & MeloNX)", systemImage: "link")
                        Label("Integrations", systemImage: "link")
                            .font(.headline)
                    }

                    DisclosureGroup(isExpanded: $isManicExpanded) {
                         VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.gray)
                                Text("How to import")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                            }
                            
                            Text("1. Download Manic Emu from App Store.\n2. Add your games to Manic Emu.\n3. Tap & hold a game then select 'Share URL'.\n4. Paste the URL below.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)

                        TextField("Game Name", text: $manicName)
                        TextField("URL (manicemu://...)", text: $manicURL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button(action: {
                            if !manicName.isEmpty && !manicURL.isEmpty {
                                onAddManicEmu(manicName, manicURL)
                                presentationMode.wrappedValue.dismiss()
                            }
                        }) {
                            Label("Add Game", systemImage: "plus")
                        }
                        .disabled(manicName.isEmpty || manicURL.isEmpty)
                    } label: {
                        HStack {
                            Image("cart_manic")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                                .cornerRadius(6)
                            Text("ManicEmu Link")
                                .font(.headline)
                        }
                    }
                }

                Section(footer: Text("Note: ZIP archives are not supported. Please extract your files first.\n\nYou must own a legal copy of any game you import. SUMEE! does not condone piracy.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                ) {
                    // Empty section for footer
                }
            }
            .navigationTitle("Add Game")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
