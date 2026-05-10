<p align="center">
  <img src="assets/logo.png" width="180" alt="Luxa Logo">
  <h1 align="center">Luxa</h1>
  <p align="center"><b>Next-Gen Entertainment. Everywhere.</b></p>
  <p align="center">The ultimate unified streaming hub for Movies, TV Shows, Anime, Music, Live TV, and Games.</p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Version-2.3.0-E50914?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/Flutter-3.41+-02569B?style=for-the-badge&logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Platform-Android%20|%20Windows%20|%20Web-black?style=for-the-badge" alt="Platforms">
  <img src="https://img.shields.io/badge/Website-luxa--app.vercel.app-673AB7?style=for-the-badge" alt="Website">
</p>

---

Luxa (formerly Drishya) is a premium, cross-platform media application built with Flutter, designed to deliver a high-fidelity cinematic experience. It features a modern iOS-inspired glassmorphic UI, high-performance playback engines, and a comprehensive library spanning movies, series, IPTV, music, and interactive mini-games.

## ✨ Key Features

- 🎬 **Cinematic Universe**: Extensive library for Movies and TV Shows with deep metadata, cast details, and intelligent recommendations.
- 📺 **Live TV (IPTV)**: Global IPTV integration with category-wise browsing and direct channel access.
- 🎵 **Music Streaming**: Built-in high-quality music player with background playback support.
- 🎮 **Mini Games**: Instant access to a library of web-based "Playables" without installation.
- 🎨 **Aesthetic Excellence**: Stunning iOS-style Glassmorphic design with support for dynamic theming and custom typography.
- 📥 **Advanced Media Manager**: Resumable, high-speed downloads with background processing and smart source fallback.
- ⚡ **Premium Playback**: Hardware-accelerated dual engine support (FVP/FFmpeg & Video Player) for butter-smooth 4K playback.
- 🔗 **Smart Routing & Sharing**: Advanced deep-linking system and social sharing for content, players, and live channels.
- 🚀 **Cross-Platform**: Optimized for Android (Mobile), Windows (Desktop), and Web.

## 🔗 Deep Linking & Routing

Luxa supports advanced deep links and URL routing to allow seamless content sharing and navigation:

### 1. Content Details
- **Route**: `/details`
- **Parameters**: `type` (movie/tv), `id` (TMDB ID)
- **Example**: `https://luxa-app.vercel.app/details?type=movie&id=123`

### 2. Media Player (Movies & TV)
- **Route**: `/watch`
- **Parameters**: `type`, `id`, `s` (Season, optional), `e` (Episode, optional)
- **Example**: `https://luxa-app.vercel.app/watch?type=tv&id=456&s=1&e=5`

### 3. Live TV Player
- **Route**: `/watch/iptv`
- **Parameters**: `id` (Channel ID)
- **Example**: `https://luxa-app.vercel.app/watch/iptv?id=789`

## 🛠 Tech Stack

- **Framework**: [Flutter](https://flutter.dev) (v3.41+)
- **Engines**: 
  - [fvp](https://pub.dev/packages/fvp) (High-performance FFmpeg-based playback)
  - [video_player](https://pub.dev/packages/video_player)
- **UI/UX**:
  - Cupertino-inspired Design System
  - [flutter_animate](https://pub.dev/packages/flutter_animate) (Micro-animations)
  - [google_fonts](https://pub.dev/packages/google_fonts) (Outfit & Inter)
- **Services**:
  - [app_links](https://pub.dev/packages/app_links) (Advanced Deep Linking)
  - [audio_service](https://pub.dev/packages/audio_service) (Background Music Control)
  - [window_manager](https://pub.dev/packages/window_manager) (Desktop Windowing)
  - [share_plus](https://pub.dev/packages/share_plus) (Social Integration)

## 📸 Screenshots

<p align="center">
  <img src="screenshots/1.jpg" width="200" alt="Luxa Screen 1">
  <img src="screenshots/2.jpg" width="200" alt="Luxa Screen 2">
  <img src="screenshots/3.jpg" width="200" alt="Luxa Screen 3">
  <img src="screenshots/4.jpg" width="200" alt="Luxa Screen 4">
  <img src="screenshots/5.jpg" width="200" alt="Luxa Screen 5">
  <img src="screenshots/6.jpg" width="200" alt="Luxa Screen 6">
  <img src="screenshots/7.jpg" width="200" alt="Luxa Screen 7">
  <img src="screenshots/8.jpg" width="200" alt="Luxa Screen 8">
</p>

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (latest stable version)
- Android Studio / VS Code
- A physical device or emulator

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/Shashwat-CODING/StreamFlix-main.git
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run
   ```

## 📜 License
Distributed under the MIT License.

---
<p align="center">Built with ❤️ by Shashwat</p>
