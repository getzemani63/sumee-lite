import SwiftUI
import MediaPlayer
import UniformTypeIdentifiers

struct MusicPlayerInlineView: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject private var gameController = GameControllerManager.shared
    @ObservedObject private var musicPlayer = MusicPlayerManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showContent = false
    @State private var selectedIndex: Int = 0
    @AppStorage("musicPlayer.lastCategory") private var selectedCategory: MusicCategory = .system
    @State private var navigationPath: [MusicNavigationItem] = []
    @State private var searchText = ""
    @State private var isSearchActive = false
    
    enum MusicCategory: String, CaseIterable, Identifiable {
        case system = "System Songs"
        case songs = "Songs"
        case albums = "Albums"
        case playlists = "Playlists"
        
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .system: return "iphone"
            case .songs: return "music.note"
            case .albums: return "square.stack"
            case .playlists: return "music.note.list"
            }
        }
    }
    
    struct MusicNavigationItem: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let songs: [Song]
    }
    
    var currentSongs: [Song] {
        if let item = navigationPath.last {
            return item.songs
        }
        
        switch selectedCategory {
        case .system: return musicPlayer.systemSongs
        case .songs: return musicPlayer.librarySongs
        default: return []
        }
    }
    
    var filteredSongs: [Song] {
        if searchText.isEmpty { return currentSongs }
        return currentSongs.filter { song in
            song.title.localizedCaseInsensitiveContains(searchText) ||
            song.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var activeTheme: AppTheme {
        settings.activeTheme
    }
    
    var body: some View {
        GeometryReader { geometry in
            let isPortrait = geometry.size.height > geometry.size.width
            
            ZStack(alignment: .top) {
                if isPortrait {
                    portraitVisualContent
                } else {
                    visualContent
                }
            }
            .background(inputObserver)
            .onAppear {
                gameController.disableHomeNavigation = true
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { showContent = true }
                AudioManager.shared.fadeOutBackgroundMusic(duration: 0.5)
                
                // Unlock orientation
                AppDelegate.orientationLock = .all
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
                }
                UIViewController.attemptRotationToDeviceOrientation()
            }
            .onDisappear {
                gameController.disableHomeNavigation = false
                AudioManager.shared.resumeBackgroundMusic()
                
                // Unlock orientation back to all
                AppDelegate.orientationLock = .all
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
                }
                UIViewController.attemptRotationToDeviceOrientation()
            }
            .onChange(of: gameController.buttonAPressed) { _, newValue in
                if newValue {
                    if (selectedCategory == .albums || selectedCategory == .playlists) && navigationPath.isEmpty {
                        if selectedCategory == .albums {
                            if musicPlayer.albums.indices.contains(selectedIndex) {
                                let album = musicPlayer.albums[selectedIndex]
                                openCollection(album, title: album.representativeItem?.albumTitle ?? "Album")
                            }
                        } else {
                            if musicPlayer.playlists.indices.contains(selectedIndex) {
                                let playlist = musicPlayer.playlists[selectedIndex]
                                openCollection(playlist, title: playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "Playlist")
                            }
                        }
                    } else {
                        playSong()
                    }
                }
            }
            .onChange(of: gameController.buttonBPressed) { _, newValue in
                if newValue {
                    if !navigationPath.isEmpty {
                        _ = navigationPath.popLast()

                    } else {
                        close()
                    }
                }
            }
            .onChange(of: gameController.buttonYPressed) { _, newValue in
                if newValue { musicPlayer.togglePlayPause() }
            }
            .onChange(of: gameController.buttonXPressed) { _, newValue in
                if newValue {

                    viewModel.isImportingMusic = true
                    viewModel.showingFilePicker = true
                }
            }
            
            // Header protection area (only for landscape or if needed)
            if !isPortrait {
                VStack { Color.clear.frame(height: 70); Spacer() }
            }
            
            // Loading Overlay
            if musicPlayer.isLoading {
                ZStack {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Loading...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .padding(24)
                    .background(SettingsManager.shared.reduceTransparency ? Material.thickMaterial : Material.ultraThinMaterial)
                    .cornerRadius(16)
                }
                .transition(.opacity)
                .zIndex(100)
            }
            
            // Portrait Controls (Always on Top)
            if isPortrait {
                VStack(alignment: .center, spacing: 12) { // Added spacing
                    Spacer()
                    
                    // Mini Player
                    // Removed to use global overlay from HomeView
                    
                    ControlCard(actions: [
                        ControlAction(icon: "b.circle", label: "Back", action: { handleBack() })
                    ], position: .center, scale: 1.25)
                    .padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity) // Force full width to enable centering
                .zIndex(200) // Higher than Loading Overlay (100)
                .allowsHitTesting(true) // Ensure it captures touches
            }
        }
        .transition(.opacity)

    }
    
    private var inputObserver: some View {
        Color.clear
            .onChange(of: gameController.dpadRight) { _, newValue in
                if newValue { moveSelection(delta: 1) }
            }
            .onChange(of: gameController.dpadLeft) { _, newValue in
                if newValue { moveSelection(delta: -1) }
            }
            .onChange(of: gameController.dpadDown) { _, newValue in
                if newValue { moveSelection(delta: 4) }
            }
            .onChange(of: gameController.dpadUp) { _, newValue in
                if newValue { moveSelection(delta: -4) }
            }
            .onChange(of: gameController.buttonL1Pressed) { _, newValue in
                if newValue { switchCategory(direction: -1) }
            }
            .onChange(of: gameController.buttonR1Pressed) { _, newValue in
                if newValue { switchCategory(direction: 1) }
            }
    }
    
    private var visualContent: some View {
        ZStack(alignment: .bottom) {
            // Content Layer
            VStack(spacing: 0) {
                Spacer().frame(height: 85)
                
                if navigationPath.isEmpty {
                    categorySelector
                } else {
                    backButton
                }
                
                mainContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Controls Layer
            bottomControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var portraitVisualContent: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                if navigationPath.isEmpty {
                    if isSearchActive {
                        // Extended Search Bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            TextField("Search songs...", text: $searchText)
                                .foregroundColor(.primary)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            
                            Button(action: {
                                withAnimation(.spring()) {
                                    isSearchActive = false
                                    searchText = ""
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(12)
                        .background {
                            BubbleBackground(cornerRadius: 16, theme: activeTheme)
                        }
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        // Title
                        Text("Music")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background {
                                BubbleBackground(cornerRadius: 16, theme: activeTheme)
                            }
                            .padding(.leading)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        
                        Spacer()
                        
                        // Search Button
                        if selectedCategory == .system || selectedCategory == .songs {
                            Button(action: {
                                withAnimation(.spring()) {
                                    isSearchActive = true
                                }
                            }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.primary)
                                    .padding(12)
                                    .background {
                                        BubbleBackground(cornerRadius: 999, theme: activeTheme)
                                    }
                            }
                            .padding(.trailing, 16)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                } else {
                  
                    Spacer()
                }
            }
            .padding(.top, 80) // Safe area (Increased to avoid header intersection)
            

            
            if navigationPath.isEmpty {
                // Portrait Category Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(MusicCategory.allCases) { category in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedCategory = category
                                    selectedIndex = 0
                                }

                            }) {
                                Text(category.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        ZStack {
                                            BubbleBackground(cornerRadius: 16, theme: activeTheme)
                                            if selectedCategory == category {
                                                RoundedRectangle(cornerRadius: 16)
                                                    .fill(activeTheme.color.opacity(0.35))
                                            }
                                        }
                                    )
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 10)
            } else {
                Text(navigationPath.last?.title ?? "")
                    .font(.headline)
                    .fontWeight(.bold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background {
                        BubbleBackground(cornerRadius: 12, theme: activeTheme)
                    }
                    .padding(.bottom, 10)
            }
            
            // Main Content
            mainContent
            

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    }
    
    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(MusicCategory.allCases) { category in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedCategory = category
                            selectedIndex = 0
                        }

                    }) {
                        HStack {
                            Image(systemName: category.icon)
                            Text(category.rawValue)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            ZStack {
                                BubbleBackground(cornerRadius: 20, theme: activeTheme)
                                if selectedCategory == category {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(activeTheme.color.opacity(0.35))
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 10)
    }
    
    private var backButton: some View {
        HStack {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    _ = navigationPath.popLast()
                    selectedIndex = 0
                }

            }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text(navigationPath.last?.title ?? "Back")
                }
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary) // Use primary color for better contrast on material
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    BubbleBackground(cornerRadius: 20, theme: activeTheme)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }
    
    private var mainContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Apple Music Authorization
                if !musicPlayer.isAuthorizedForAppleMusic && selectedCategory != .system {
                    Button(action: {
                        musicPlayer.requestLibraryAccess()
                    }) {
                        HStack {
                            Image(systemName: "applelogo")
                            Text("Connect Apple Music")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.pink)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                    }
                    .padding(.top, 20)
                }
                
                contentGrid
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(false)
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.05), // Small top fade area
                        .init(color: .black, location: 0.95),
                        .init(color: .clear, location: 1.0)  // Also fade bottom slightly for symmetry/polishing
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .opacity(showContent ? 1 : 0)
        .scaleEffect(showContent ? 1 : 0.9)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showContent)
    }
    
    private var contentGrid: some View {
        MusicGridContent(
            category: selectedCategory,
            navigationPath: navigationPath,
            currentSongs: filteredSongs,
            albums: musicPlayer.albums,
            playlists: musicPlayer.playlists,
            selectedIndex: selectedIndex,
            playingSongID: musicPlayer.currentSong?.id,
            isPlaying: musicPlayer.isPlaying,
            onSelectAlbum: { album in
                selectedIndex = musicPlayer.albums.firstIndex(of: album) ?? 0
                openCollection(album, title: album.representativeItem?.albumTitle ?? "Album")
            },
            onSelectPlaylist: { playlist in
                selectedIndex = musicPlayer.playlists.firstIndex(of: playlist) ?? 0
                openCollection(playlist, title: playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "Playlist")
            },
            onSelectSong: { index in
                selectSong(index)
            },
            onDeleteSong: { song in
                musicPlayer.deleteSong(song)
            }
        )

        .equatable()
    }
    

            
    private var bottomControls: some View {
        HStack {
            ControlCard(actions: [
                ControlAction(icon: "x.circle", label: "Add MP3", action: { 
                    viewModel.isImportingMusic = true
                    viewModel.showingFilePicker = true 
                }),
                ControlAction(icon: "y.circle", label: musicPlayer.isPlaying ? "Pause" : "Play")
            ])
                .opacity(showContent ? 1 : 0)
                .offset(x: showContent ? 0 : -30)
                .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.1), value: showContent)
            
            Spacer()
            
            Spacer()
            
            ControlCard(actions: [
                ControlAction(icon: "b.circle", label: "Back", action: { close() }),
                ControlAction(icon: "a.circle", label: "Select")
            ])
                .opacity(showContent ? 1 : 0)
                .offset(x: showContent ? 0 : 30)
                .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.2), value: showContent)
        }
        .frame(height: 32, alignment: .bottom)
        .padding(.horizontal, 20)
        .padding(.bottom, 20) // Lift up slightly
    }
    
    private func switchCategory(direction: Int) {
        guard navigationPath.isEmpty else { return }
        let all = MusicCategory.allCases
        if let idx = all.firstIndex(of: selectedCategory) {
            let nextIdx = (idx + direction + all.count) % all.count
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedCategory = all[nextIdx]
                selectedIndex = 0
            }

        }
    }
    
    private func openCollection(_ collection: MPMediaItemCollection, title: String) {
        let songs = collection.items.map { item in
            Song(
                title: item.title ?? "Unknown",
                artist: item.artist ?? "Unknown",
                fileName: "",
                duration: item.playbackDuration,
                artwork: nil, // Load lazily in SongCardView
                mediaItem: item
            )
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            navigationPath.append(MusicNavigationItem(title: title, songs: songs))
            selectedIndex = 0
        }

    }
    
    private func moveSelection(delta: Int) {
        let count: Int
        if (selectedCategory == .albums && navigationPath.isEmpty) {
            count = musicPlayer.albums.count
        } else if (selectedCategory == .playlists && navigationPath.isEmpty) {
            count = musicPlayer.playlists.count
        } else {
            count = filteredSongs.count + 1 // +1 for Random Button
        }
        
        guard count > 0 else { return }
        let newIndex = max(0, min(selectedIndex + delta, count - 1))
        if newIndex != selectedIndex {

            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        selectedIndex = newIndex
    }
    
    private func selectSong(_ index: Int) {
        selectedIndex = index

        playSong()
    }
    
    private func playSong() {
        // Handle Random Play (Index 0)
        if selectedIndex == 0 {
            if let randomSong = filteredSongs.randomElement() {
                // Shuffle context if desirable, or just play random entry
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    musicPlayer.play(song: randomSong, context: filteredSongs.shuffled())
                }

            }
            return
        }
        
        // Handle Actual Song (Index - 1)
        let realIndex = selectedIndex - 1
        guard filteredSongs.indices.contains(realIndex) else { return }
        let song = filteredSongs[realIndex]
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            musicPlayer.play(song: song, context: filteredSongs)
        }

    }
    
    private func handleBack() {
        if !navigationPath.isEmpty {

            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                _ = navigationPath.popLast()
                selectedIndex = 0
            }
        } else {
            close()
        }
    }
    
    private func close() {
        AudioManager.shared.playBackMusic()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { 
            if SettingsManager.shared.liteMode {
                // If in Lite Mode, return to Game Systems instead of Home
                viewModel.activeSystemApp = .gameSystems
            } else {
                isPresented = false 
            }
        }
    }
    

}

// - Components

//- Components (MiniPlayer & FullControls removed/moved to Header)



// - MiniPlayerBanner



//  - SongCard

// SongCard struct removed - replaced by external SongCardView


struct MusicPlayerInlineView_Previews: PreviewProvider {
    static var previews: some View {
        MusicPlayerInlineView(isPresented: .constant(true), viewModel: HomeViewModel())
            .previewLayout(.sizeThatFits)
            .background(Color.gray.opacity(0.2))
    }
}
