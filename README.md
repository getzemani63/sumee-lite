# SUMEE (Lite)

> ⚠️ **Important Update:** This repository is a refactored Lite fork of my original SUMEE! codebase. The work focused on reducing project size, splitting large files into smaller modules, and improving maintainability. English ↔ Spanish translation tasks were also streamlined in this version.

**SUMEE** is a highly stylized, nostalgic iOS launcher and frontend inspired by the **PS Vita** interface and the **Frutiger Aero** design language.

## Project Context (Important)

This repository is a **refactored Lite fork** of the original **SUMEE!** project, based on my own original codebase.

Main goal of this fork:
- Make SUMEE! smaller and easier to maintain.
- Split large files/features into smaller, modular components.
- Keep behavior and design identity while improving readability and iteration speed.

About development workflow:
- Core architecture, app logic, and project direction are authored manually.
- Refactoring focused on decomposition into reusable pieces (views, managers, and feature modules).
- English ↔ Spanish translation tasks were also made easier during this refactor process.

### AI Usage in the Codebase

AI tools were used as targeted support to speed up refactoring, cleanup, and writing tasks.

However, the project design, core architecture, and technical decisions behind SUMEE! Lite are original work and are maintained manually.

It transforms your iOS navigation experience with 3D bubble icons, "LiveArea" style app pages, floating cartridges, and a fully functional system interface including Music, Photos, and Game integrations.

[Join our Discord](https://discord.gg/KbNJeQX4Nn)

## Features

- **Vita-Style Home Screen**:
    - Vertical scrolling pages with 3D, physics-based bubble icons.
    - "Wobble" edit mode and drag-and-drop organization.
- **LiveArea Interface**:
    - Launch apps into a "LiveArea" gate before entering.
    - **Peel-to-Close**: Use the signature "peel" gesture (top-right corner) to close apps and games. Includes haptic feedback!
- **System Apps**:
    - **Music Player**: Floating mini-player and full-screen visualization.
    - **Photos**: Integrated gallery viewer.
    - **Settings**: Comprehensive customization (Lite Mode, Performance Mode, Custom Themes).
- **Emulation Frontend**:
    - Built-in support for launching and managing ROMs (requires appropriate backend/core setup).
- **Aesthetics**:
    - Frutiger Aero gloss and depth.
    - Dynamic backgrounds and floating particle effects.
    - Custom "Lite Mode" for older devices to ensure smooth 60fps performance.

## Prerequisites

- **macOS** with the latest version of **Xcode** (15.0+ recommended).
- **iOS Device** matching the deployment target (iOS 15.0+).
- **Apple ID** (for signing).

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/getzemani63/sumee-lite.git
cd sumee-lite
```

### 2. Open in Xcode

Double-click on **`SUMEE!.xcodeproj`** to open the project.

### 3. Configure Signing

1.  Click on the **SUMEE** project icon in the top-left project navigator.
2.  Select the **SUMEE** target under "Targets".
3.  Go to the **Signing & Capabilities** tab.
4.  Select your **Team** from the dropdown menu.
5.  Ensure the **Bundle Identifier** is unique (e.g., change `com.sumee.app` to `com.yourname.sumee`) if you don't have access to the original team profile.

### 4. Run the App

1.  Connect your iOS device via USB.
2.  Select your device from the generic device list in the top toolbar.
3.  Press **Cmd + R** or click the **Play** button to build and run.

> **Note:** If running on a physical device for the first time, you may need to trust your developer profile in **Settings > General > VPN & Device Management** on your iPhone/iPad.

---

## Building an IPA (For Sideloading)

To verify the app or share it (e.g., via AltStore, SideStore, or TrollStore), you need to export an `.ipa` file.

1.  **Select "Any iOS Device (arm64)"**:
    - In the device selector (top toolbar), choose **Any iOS Device (arm64)** instead of a specific connected phone.

2.  **Archive**:
    - Go to **Product > Archive** in the menu bar.
    - Xcode will build the project. This may take a few minutes.

3.  **Distribute App**:
    - Once the Organizer window appears with your archive selected, click **Distribute App**.
    - Select **Custom** (or *Ad Hoc* / *Development* depending on your Xcode version options).
    - Choose **App Thinning**: *None* (to make it compatible with all devices) or select your specific model.
    - **Signing**: Select *Automatically manage signing* or manually select your profile.

4.  **Export**:
    - Choose a destination folder on your Mac.
    - Xcode will generate a folder containing `SUMEE.ipa`.

You can now sideload this `SUMEE.ipa` using tools like **AltServer** or **SideStore**.

## Contributing

Contributions are welcome! Please fork the repository and submit a Pull Request.

## Acknowledgements

Special thanks to the developers and community members who helped shape SUMEE:

- **Stossy11** (Creator of MeloNX): Huge thanks for your help with URL schemes and AirPlay integration!
- **Maftyマフティー (Manic EMU)**: Thank you for the permission to integrate your amazing skins.
- **Delta Skins**: This project is fully compatible with Delta emulator skins.
- **Music**: **k0o1**
- **Assets & Design**:
  - **@Nobody**
  - **@Sloops**
  - **@Kylixer**
  - **@Limba44 (Kirby lover)**

## License

This project is licensed under the **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License (CC BY-NC-SA 4.0)**.
**Copyright © 2026 SUMEE! (Getzemani Cruz Garcia / ParienteKun)**

### You are free to:
- **Share**: Copy and redistribute the material in any medium or format.
- **Adapt**: Remix, transform, and build upon the material.

### Under the following terms:
- **Attribution**: You must give appropriate credit, provide a link to the license, and indicate if changes were made.
- **NonCommercial**: You may **NOT** use the material for commercial purposes.
- **ShareAlike**: If you remix, transform, or build upon the material, you must distribute your contributions under the same license as the original.


## Emulator Licenses

This project uses the following Libretro cores for emulation. Each core is subject to its own license:

- **NES**: FCEUmm (GPL v2)
- **SNES**: Snes9x (Non-commercial)
- **GBA**: mGBA (MPL 2.0)
- **DS**: melonDS (GPL v3)
- **PSX**: PCSX ReARMed (GPL v2)
- **Genesis/Mega Drive**: PicoDrive (MAME / GPL v2)

