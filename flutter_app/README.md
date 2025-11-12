# Mindful Mentor Flutter App

This directory contains the Flutter client for the Mindful Mentor project.  
The current implementation covers the Week 1 milestone defined in `plans.md`.

## Features

- Material 3 based layout with a dedicated area for model responses.
- Voice recording toggle (start/stop) using the `record` plugin, saving audio as `.mp3` files inside the app's documents directory.
- Basic status messaging and simulated processing flow that will later call the Python AI services.

## Getting Started

1. **Install Dependencies**

   Ensure the Flutter SDK (3.5 or later) and Android Studio tooling are installed.

2. **Fetch Packages**

   ```bash
   flutter pub get
   ```

3. **Run on Emulator/Device**

   ```bash
   flutter run
   ```

## Next Steps (Week 2+)

- Replace the simulated AI workflow with real network calls to `mp3_in()` and `text_out()`.
- Add error handling for upload failures and network timeouts.
- Integrate refined UI/UX and feedback animations.


