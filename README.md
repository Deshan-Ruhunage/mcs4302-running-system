# MCS4302 Week 4 Lab - Code Pack

Follow the lab sheet for instructions. This pack contains:

```
backend/               FastAPI server (run once, used in every part)
  main.py
  requirements.txt
flutter/
  part2/lib/...        Starting files: config, Item model, basic ApiClient, main.dart
  part3/lib/...        Adds api_exceptions.dart; REPLACES api_client.dart and main.dart
  part4/lib/...        Adds retry.dart; REPLACES api_client.dart and main.dart
  part5/lib/...        Adds experiment.dart, experiment_screen.dart; REPLACES main.dart
```

At the start of each part, merge that part's `lib/` into your project's `lib/`,
replacing matching files and retaining earlier files. Do not delete the existing
`lib/` folder. Hot restart (capital R in the `flutter run` terminal) after merging.

## Where each component runs

| Component                         | Runs on                                   |
|-----------------------------------|-------------------------------------------|
| FastAPI backend (backend/main.py) | Host machine (laptop), via uvicorn        |
| Swagger page /docs                | Host machine browser: localhost:8000/docs |
| Android Emulator                  | Host machine (virtual phone)              |
| Flutter app (mobile_client)       | Inside the Android Emulator               |

`flutter run` is typed on the host; it builds the app and installs it on the emulator.
The app reaches the backend at http://10.0.2.2:8000 (the emulator's alias for the host).
Inside the emulator, `localhost` means the emulator itself.

## Backend (host machine)

```
cd backend
python -m venv .venv
# Windows Command Prompt: .venv\Scripts\activate.bat
# Windows PowerShell:     .\.venv\Scripts\Activate.ps1
# macOS/Linux:            source .venv/bin/activate
python -m pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Check: open http://localhost:8000/docs

## Flutter project (built on the host, runs on the emulator)

```
flutter create mobile_client
cd mobile_client
flutter pub add http
```

Edit the existing `android/app/src/main/AndroidManifest.xml`: add INTERNET above the application and add usesCleartextTraffic to its existing opening tag. Keep all existing application attributes. The snippet below is illustrative; do not replace the full tag. Plain HTTP is for this lab only and is removed in Week 9.

```xml
<uses-permission android:name="android.permission.INTERNET" />   <!-- above <application> -->
<application
    android:usesCleartextTraffic="true">
```

Requirements: Flutter 3.24+ (Dart 3), Python 3.10+. Check the Flutter setup with:

```
flutter doctor
```
Base URL is set in `lib/config.dart` (`10.0.2.2` = host machine from the Android Emulator).


## Revised experiment and submission
The first completed experiment uses seed 42, the next 43, then 44. All four
conditions within a run share its seed. Copy CSV after each run: the next run
replaces the displayed results. CSV includes the seed and quotes labels.
Restarting or hot-restarting (R) the app resets the seed counter to 42,
so complete all three runs without restarting. Do not interact with Swagger or
other clients during experiments; they share the backend random stream.
The reported p95 is nearest rank over all 50 logical requests, including failures.
For the sheet, report the mean of the three run-level p95 values, not a pooled p95.
HTTP calls counts /flaky attempts only and excludes the reset request.

The keys and catalogue are in memory. Reset or server restart clears both.
An idempotency key covers automatic retries within one createItem call, not a
later user submission. A reused key with changed data is rejected with HTTP 409.
Cached replays return the saved result without injecting a second failure; this
is a deliberately simplified backend for teaching, not a production service.
Retryable here means potentially transient, not permission to retry every method.
/slow and /bad-json remain single-attempt tests in Part 4; /flaky uses retries.
Timeouts stop waiting but do not cancel requests. Keep one backend per student.

Submit measurement PDF, Flutter lib/, pubspec.yaml, pubspec.lock,
android/app/src/main/AndroidManifest.xml, and backend/ (exclude .venv/ and caches).
Git should contain the full generated Flutter project and backend; include your
repository URL on the measurement sheet. Avoid committing .venv/ or build output.
