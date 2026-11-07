// MCS4302 Week 6 lab entry point.
//
// Android emulator (debug, Parts 1-2):   flutter run -t lib/main_week6.dart
// Android emulator (profile, Part 3):    flutter run --profile -t lib/main_week6.dart
// Desktop fallback (profile, Part 3):    flutter run -d windows --profile -t lib/main_week6.dart \
//                                          --dart-define=BASE_URL=http://127.0.0.1:8000
//
// BASE_URL: Android emulator 10.0.2.2 (default); desktop or iOS simulator
// 127.0.0.1; physical phone: your laptop's Wi-Fi IP, e.g. 192.168.1.20.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'week6/app.dart';
import 'week6/item_repository.dart';

const baseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

void main() {
  final api = ApiItemRepository(client: http.Client(), baseUrl: baseUrl);
  runApp(Week6App(repo: api, api: api));
}
