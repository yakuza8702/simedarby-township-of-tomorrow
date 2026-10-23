/// Township application state — the local-first port of the legacy appStore.
///
/// Everything persists to JSON in the app documents dir; no cloud. Staff role
/// is a local setting for now (the server-managed role lands with the backend).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class HazardReport {
  final String id;
  final String category; // street light, illegal dumping, bin overflowing…
  final String description;
  final String? photoPath;
  final String severity; // low | medium | high
  final String precinct;
  final double? lat; // null until the backend lands
  final double? lng;
  final String status; // submitted | triaged | resolved
  final DateTime createdAt;
  final DateTime? triagedAt;
  final DateTime? resolvedAt;

  HazardReport({
    required this.id,
    required this.category,
    required this.description,
    this.photoPath,
    required this.severity,
    required this.precinct,
    this.lat,
    this.lng,
    this.status = 'submitted',
    required this.createdAt,
    this.triagedAt,
    this.resolvedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'description': description,
        'photoPath': photoPath,
        'severity': severity,
        'precinct': precinct,
        'lat': lat,
        'lng': lng,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'triagedAt': triagedAt?.toIso8601String(),
        'resolvedAt': resolvedAt?.toIso8601String(),
      };

  static HazardReport fromJson(Map<String, dynamic> j) => HazardReport(
        id: j['id'],
        category: j['category'],
        description: (j['description'] ?? '') as String,
        photoPath: j['photoPath'] as String?,
        severity: (j['severity'] ?? 'low') as String,
        precinct: (j['precinct'] ?? 'Precinct 1') as String,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        status: (j['status'] ?? 'submitted') as String,
        createdAt: DateTime.parse(j['createdAt']),
        triagedAt: j['triagedAt'] == null ? null : DateTime.parse(j['triagedAt']),
        resolvedAt: j['resolvedAt'] == null ? null : DateTime.parse(j['resolvedAt']),
      );
}

class HubListing {
  final String id;
  final String title;
  final String description;
  final String photoPath;
  final String owner;
  final String precinct;
  final String status; // available | reserved
  final DateTime listedAt;

  HubListing({
    required this.id,
    required this.title,
    required this.description,
    required this.photoPath,
    required this.owner,
    required this.precinct,
    this.status = 'available',
    required this.listedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'photoPath': photoPath,
        'owner': owner,
        'precinct': precinct,
        'status': status,
        'listedAt': listedAt.toIso8601String(),
      };

  static HubListing fromJson(Map<String, dynamic> j) => HubListing(
        id: j['id'],
        title: j['title'],
        description: (j['description'] ?? '') as String,
        photoPath: (j['photoPath'] ?? '') as String,
        owner: (j['owner'] ?? 'resident') as String,
        precinct: (j['precinct'] ?? '') as String,
        status: (j['status'] ?? 'available') as String,
        listedAt: DateTime.parse(j['listedAt']),
      );
}

class TownshipStore extends ChangeNotifier {
  // ── profile / onboarding ────────────────────────────────────────────────
  String? householdName;
  String householdAddress = ''; // resident-entered address; saved as 'address'
  String precinct = 'Precinct 1';
  bool onboardingDone = false;
  bool tourDone = false;
  bool isStaff = false; // legacy: server app_metadata; local until backend

  /// Appearance setting — 'system' (follow the phone) | 'light' | 'dark'.
  /// Persisted in the same JSON file as every other preference; main.dart
  /// maps it onto [ThemeMode] through `themeModeFromSetting`.
  String themeMode = 'system';

  /// Read-only alias for [householdAddress] — map_screen.dart (out of scope
  /// for this change) reads store.address for its home-pin label. The JSON
  /// key stays 'address' so existing state files keep loading unchanged.
  String get address => householdAddress;

  // ── hazard reports ──────────────────────────────────────────────────────
  final List<HazardReport> reports = [];

  // ── circular hub ────────────────────────────────────────────────────────
  final List<HubListing> hubListings = [];

  // ── taught scanner references: item label → {category, photos} ───────────
  final List<Map<String, dynamic>> taughtRefs = []; // {label, stream, photoPath}

  File? _file;

  static const precincts = [
    'Precinct 1', 'Precinct 2', 'Precinct 3', 'Precinct 4', 'Precinct 5',
  ];

  int get openReports => reports.where((r) => r.status != 'resolved').length;
  int get triagedReports => reports.where((r) => r.status == 'triaged').length;
  int get resolvedReports => reports.where((r) => r.status == 'resolved').length;
  List<HubListing> get availableListings =>
      hubListings.where((h) => h.status == 'available').toList();

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/township_state.json');
    if (await _file!.exists()) {
      try {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        householdName = j['householdName'] as String?;
        householdAddress = (j['address'] ?? '') as String;
        precinct = (j['precinct'] ?? 'Precinct 1') as String;
        onboardingDone = (j['onboardingDone'] ?? false) as bool;
        tourDone = (j['tourDone'] ?? false) as bool;
        isStaff = (j['isStaff'] ?? false) as bool;
        themeMode = (j['themeMode'] ?? 'system') as String;
        reports
          ..clear()
          ..addAll([
            for (final r in (j['reports'] as List? ?? []))
              HazardReport.fromJson(Map<String, dynamic>.from(r as Map))
          ]);
        hubListings
          ..clear()
          ..addAll([
            for (final h in (j['hubListings'] as List? ?? []))
              HubListing.fromJson(Map<String, dynamic>.from(h as Map))
          ]);
        taughtRefs
          ..clear()
          ..addAll([
            for (final t in (j['taughtRefs'] as List? ?? []))
              Map<String, dynamic>.from(t as Map)
          ]);
      } catch (e) {
        debugPrint('TWP:ERROR state load: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    if (_file == null) return;
    await _file!.writeAsString(jsonEncode({
      'householdName': householdName,
      'address': address,
      'precinct': precinct,
      'onboardingDone': onboardingDone,
      'tourDone': tourDone,
      'isStaff': isStaff,
      'themeMode': themeMode,
      'reports': [for (final r in reports) r.toJson()],
      'hubListings': [for (final h in hubListings) h.toJson()],
      'taughtRefs': taughtRefs,
    }));
  }

  void completeOnboarding(String name, String address, String precinctName) {
    householdName = name; // the resident's own name ('Your Name' onboarding)
    householdAddress = address;
    precinct = precinctName;
    onboardingDone = true;
    _save();
    notifyListeners();
  }

  void completeTour() {
    tourDone = true;
    _save();
    notifyListeners();
  }

  void setStaff(bool v) {
    isStaff = v;
    _save();
    notifyListeners();
  }

  void setPrecinct(String p) {
    precinct = p;
    _save();
    notifyListeners();
  }

  /// Persist the appearance choice ('system' | 'light' | 'dark'). main.dart
  /// listens on this store, so the MaterialApp theme follows immediately.
  void setThemeMode(String mode) {
    if (mode == themeMode) return;
    themeMode = mode;
    _save();
    notifyListeners();
  }

  HazardReport addReport({
    required String category,
    required String description,
    String? photoPath,
    String severity = 'low',
    String? precinct, // null → the resident's own precinct (demo seeds pin one)
    double? lat,
    double? lng,
  }) {
    final r = HazardReport(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      category: category,
      description: description,
      photoPath: photoPath,
      severity: severity,
      precinct: precinct ?? this.precinct,
      lat: lat,
      lng: lng,
      createdAt: DateTime.now(),
    );
    reports.insert(0, r);
    _save();
    notifyListeners();
    return r;
  }

  void triageReport(String id) {
    final i = reports.indexWhere((r) => r.id == id);
    if (i < 0) return;
    reports[i] = HazardReport(
      id: reports[i].id,
      category: reports[i].category,
      description: reports[i].description,
      photoPath: reports[i].photoPath,
      severity: reports[i].severity,
      precinct: reports[i].precinct,
      lat: reports[i].lat,
      lng: reports[i].lng,
      status: 'triaged',
      createdAt: reports[i].createdAt,
      triagedAt: DateTime.now(),
      resolvedAt: reports[i].resolvedAt,
    );
    _save();
    notifyListeners();
  }

  void resolveReport(String id) {
    final i = reports.indexWhere((r) => r.id == id);
    if (i < 0) return;
    reports[i] = HazardReport(
      id: reports[i].id,
      category: reports[i].category,
      description: reports[i].description,
      photoPath: reports[i].photoPath,
      severity: reports[i].severity,
      precinct: reports[i].precinct,
      lat: reports[i].lat,
      lng: reports[i].lng,
      status: 'resolved',
      createdAt: reports[i].createdAt,
      triagedAt: reports[i].triagedAt ?? DateTime.now(),
      resolvedAt: DateTime.now(),
    );
    _save();
    notifyListeners();
  }

  HubListing addHubListing({
    required String title,
    required String description,
    required String photoPath,
  }) {
    final h = HubListing(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      description: description,
      photoPath: photoPath,
      owner: householdName ?? 'resident',
      precinct: precinct,
      listedAt: DateTime.now(),
    );
    hubListings.insert(0, h);
    _save();
    notifyListeners();
    return h;
  }

  void toggleHubReservation(String id) {
    final i = hubListings.indexWhere((h) => h.id == id);
    if (i < 0) return;
    final h = hubListings[i];
    hubListings[i] = HubListing(
      id: h.id,
      title: h.title,
      description: h.description,
      photoPath: h.photoPath,
      owner: h.owner,
      precinct: h.precinct,
      status: h.status == 'available' ? 'reserved' : 'available',
      listedAt: h.listedAt,
    );
    _save();
    notifyListeners();
  }

  void addTaughtRef({required String label, required String stream, required String photoPath}) {
    taughtRefs.add({'label': label, 'stream': stream, 'photoPath': photoPath});
    _save();
    notifyListeners();
  }

  /// Remove every hazard report and hub listing — the demo-data reset path.
  /// Onboarding, staff mode and taught scanner references are the resident's
  /// own work and are deliberately kept.
  Future<void> clearDemoContent() async {
    reports.clear();
    hubListings.clear();
    await _save();
    notifyListeners();
  }

  /// Copy a captured photo into the app's documents dir so it survives
  /// camera temp storage clears.
  Future<String> persistPhoto(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final photos = Directory('${dir.path}/photos')..createSync(recursive: true);
    final dest = '${photos.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(sourcePath).copy(dest);
    return dest;
  }
}
