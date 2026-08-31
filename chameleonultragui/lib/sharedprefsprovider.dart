import 'dart:typed_data';
import 'dart:convert';
import 'package:chameleonultragui/helpers/colors.dart' as colors;
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class Dictionary {
  String id;
  String name;
  List<Uint8List> keys;
  Color color;
  int keyLength;
  String? folderId;

  factory Dictionary.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final name = data['name'] as String;
    final encodedKeys = data['keys'] as List<dynamic>;
    if (data['color'] == null) {
      data['color'] = colorToHex(Colors.deepOrange);
    }

    if (data['keyLength'] == null) {
      // legacy
      data['keyLength'] = 12;
    }

    final keyLength = data['keyLength'] as int;
    final color = hexToColor(data['color']);
    final folderId = data['folderId'] as String?;

    List<Uint8List> keys = [];
    for (var key in encodedKeys) {
      keys.add(Uint8List.fromList(List<int>.from(key)));
    }
    return Dictionary(
        id: id,
        name: name,
        keys: keys,
        color: color,
        keyLength: keyLength,
        folderId: folderId);
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'name': name,
      'color': colorToHex(color),
      'keys': keys.map((key) => key.toList()).toList(),
      'keyLength': keyLength,
      if (folderId != null) 'folderId': folderId,
    });
  }

  @override
  String toString() {
    String output = "";
    for (var key in keys) {
      output += "${bytesToHex(key).toUpperCase()}\n";
    }
    return output;
  }

  Uint8List toFile() {
    return const Utf8Encoder().convert(toString());
  }

  factory Dictionary.fromString(String input,
      {String name = '', Color color = Colors.deepOrange}) {
    List<Uint8List> keys = [];
    List<int> allowedKeySizes = [
      12, // 6 - Mifare Classic
      8, // 4 - Mifare Ultralight / T55XX
      32, // 16 - Mifare Ultralight C / AES / Mifare Plus
    ];
    int currentKeySize = 0;

    for (var key in input.split("\n")) {
      key = key.trim().replaceAll('#', ' ');

      if (key.contains(' ')) {
        key = key.split(' ')[0];
      }

      if (allowedKeySizes.contains(key.length) &&
          isValidHexString(key) &&
          (currentKeySize == 0 || currentKeySize == key.length)) {
        if (currentKeySize == 0) {
          currentKeySize = key.length;
        }

        keys.add(hexToBytes(key));
      }
    }

    return Dictionary(
        id: const Uuid().v4(),
        name: name,
        keys: keys,
        color: color,
        keyLength: currentKeySize);
  }

  Dictionary(
      {String? id,
      this.name = "",
      this.keys = const [],
      this.color = Colors.deepOrange,
      this.keyLength = 0,
      this.folderId})
      : id = id ?? const Uuid().v4();
}

class DictionaryFolder {
  String id;
  String name;
  Color color;
  String? parentId;

  DictionaryFolder({
    String? id,
    required this.name,
    this.color = Colors.deepOrange,
    this.parentId,
  }) : id = id ?? const Uuid().v4();

  factory DictionaryFolder.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    return DictionaryFolder(
      id: data['id'] as String,
      name: data['name'] as String,
      color: data['color'] == null
          ? Colors.deepOrange
          : hexToColor(data['color'] as String),
      parentId: data['parentId'] as String?,
    );
  }

  String toJson() => jsonEncode({
        'id': id,
        'name': name,
        'color': colorToHex(color),
        if (parentId != null) 'parentId': parentId,
      });
}

class DictionaryFolderBundle {
  final String rootFolderId;
  final List<DictionaryFolder> folders;
  final List<Dictionary> dictionaries;

  DictionaryFolderBundle({
    required this.rootFolderId,
    required this.folders,
    required this.dictionaries,
  });

  factory DictionaryFolderBundle.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    if (data['format'] != 'chameleon-ultra-gui-dictionary-folder' ||
        data['version'] != 1) {
      throw const FormatException('Unsupported dictionary folder file');
    }
    return DictionaryFolderBundle(
      rootFolderId: data['rootFolderId'] as String,
      folders: (data['folders'] as List<dynamic>)
          .map((item) => DictionaryFolder.fromJson(jsonEncode(item)))
          .toList(),
      dictionaries: (data['dictionaries'] as List<dynamic>)
          .map((item) => Dictionary.fromJson(jsonEncode(item)))
          .toList(),
    );
  }

  String toJson() => jsonEncode({
        'format': 'chameleon-ultra-gui-dictionary-folder',
        'version': 1,
        'rootFolderId': rootFolderId,
        'folders':
            folders.map((folder) => jsonDecode(folder.toJson())).toList(),
        'dictionaries': dictionaries
            .map((dictionary) => jsonDecode(dictionary.toJson()))
            .toList(),
      });
}

class CardSave {
  String id;
  String uid;
  int sak;
  Uint8List atqa;
  Uint8List ats;
  String name;
  TagType tag;
  List<Uint8List> data;
  CardSaveExtra extraData;
  Color color;
  String? folderId;
  String? skinId; // Preset card face id
  String? imagePath; // User supplied card face image
  bool pinned;
  List<String> tags;

  factory CardSave.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final uid = data['uid'] as String;
    final sak = data['sak'] as int;
    final atqa = List<int>.from(data['atqa'] as List<dynamic>);
    final ats = List<int>.from((data['ats'] ?? []) as List<dynamic>);
    final name = data['name'] as String;
    final tag = getTagTypeByValue(data['tag']);
    final extraData = CardSaveExtra.import(data['extra'] ?? {});
    final color =
        data['color'] == null ? Colors.deepOrange : hexToColor(data['color']);
    final folderId = data['folderId'] as String?;
    final skinId = data['skinId'] as String?;
    final imagePath = data['imagePath'] as String?;
    final pinned = data['pinned'] as bool? ?? false;
    final tags = (data['tags'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
    List<Uint8List> tagData = (data['data'] as List<dynamic>)
        .map((e) => Uint8List.fromList(List<int>.from(e)))
        .toList();

    return CardSave(
        id: id,
        uid: uid,
        sak: sak,
        name: name,
        tag: tag,
        data: tagData,
        color: color,
        folderId: folderId,
        skinId: skinId,
        imagePath: imagePath,
        pinned: pinned,
        tags: tags,
        extraData: extraData,
        ats: Uint8List.fromList(ats),
        atqa: Uint8List.fromList(atqa));
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'uid': uid,
      'sak': sak,
      'atqa': atqa.toList(),
      'ats': ats.toList(),
      'name': name,
      'tag': tag.value,
      'color': colorToHex(color),
      'data': data.map((data) => data.toList()).toList(),
      'extra': extraData.export(),
      if (folderId != null) 'folderId': folderId,
      if (skinId != null) 'skinId': skinId,
      if (imagePath != null) 'imagePath': imagePath,
      if (pinned) 'pinned': pinned,
      if (tags.isNotEmpty) 'tags': tags,
    });
  }

  CardSave({
    String? id,
    required this.uid,
    required this.name,
    required this.tag,
    int? sak,
    Uint8List? atqa,
    Uint8List? ats,
    CardSaveExtra? extraData,
    this.color = Colors.deepOrange,
    this.folderId,
    this.skinId,
    this.imagePath,
    this.pinned = false,
    List<String>? tags,
    this.data = const [],
  })  : id = id ?? const Uuid().v4(),
        sak = sak ?? 0,
        atqa = atqa ?? Uint8List(0),
        ats = ats ?? Uint8List(0),
        tags = tags ?? <String>[],
        extraData = extraData ?? CardSaveExtra();
}

class CardFolder {
  String id;
  String name;
  Color color;
  String? parentId;

  CardFolder({
    String? id,
    required this.name,
    this.color = Colors.deepOrange,
    this.parentId,
  }) : id = id ?? const Uuid().v4();

  factory CardFolder.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    return CardFolder(
      id: data['id'] as String,
      name: data['name'] as String,
      color: data['color'] == null
          ? Colors.deepOrange
          : hexToColor(data['color'] as String),
      parentId: data['parentId'] as String?,
    );
  }

  String toJson() => jsonEncode({
        'id': id,
        'name': name,
        'color': colorToHex(color),
        if (parentId != null) 'parentId': parentId,
      });
}

/// Versioned Chameleon Ultra GUI folder interchange format.
class CardFolderBundle {
  final String rootFolderId;
  final List<CardFolder> folders;
  final List<CardSave> cards;

  CardFolderBundle({
    required this.rootFolderId,
    required this.folders,
    required this.cards,
  });

  factory CardFolderBundle.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    if (data['format'] != 'chameleon-ultra-gui-folder' ||
        data['version'] != 1) {
      throw const FormatException('Unsupported folder file');
    }
    return CardFolderBundle(
      rootFolderId: data['rootFolderId'] as String,
      folders: (data['folders'] as List<dynamic>)
          .map((item) => CardFolder.fromJson(jsonEncode(item)))
          .toList(),
      cards: (data['cards'] as List<dynamic>)
          .map((item) => CardSave.fromJson(jsonEncode(item)))
          .toList(),
    );
  }

  String toJson() => jsonEncode({
        'format': 'chameleon-ultra-gui-folder',
        'version': 1,
        'rootFolderId': rootFolderId,
        'folders':
            folders.map((folder) => jsonDecode(folder.toJson())).toList(),
        'cards': cards.map((card) => jsonDecode(card.toJson())).toList(),
      });
}

class CardSaveExtra {
  Uint8List ultralightSignature;
  Uint8List ultralightVersion;
  List<int> ultralightCounters;

  factory CardSaveExtra.import(Map<String, dynamic> data) {
    List<int> readBytes(Map<String, dynamic> data, String key) {
      return List<int>.from(
          data[key] != null ? data[key] as List<dynamic> : []);
    }

    final ultralightSignature = readBytes(data, 'ultralightSignature');
    final ultralightVersion = readBytes(data, 'ultralightVersion');
    final ultralightCounters = data['ultralightCounters'] != null
        ? List<int>.from(data['ultralightCounters'] as List<dynamic>)
        : <int>[];

    return CardSaveExtra(
        ultralightSignature: Uint8List.fromList(ultralightSignature),
        ultralightVersion: Uint8List.fromList(ultralightVersion),
        ultralightCounters: ultralightCounters);
  }

  Map<String, dynamic> export() {
    Map<String, dynamic> json = {};

    if (ultralightSignature.isNotEmpty) {
      json['ultralightSignature'] = ultralightSignature;
    }

    if (ultralightVersion.isNotEmpty) {
      json['ultralightVersion'] = ultralightVersion;
    }

    if (ultralightCounters.isNotEmpty) {
      json['ultralightCounters'] = ultralightCounters;
    }

    return json;
  }

  CardSaveExtra(
      {Uint8List? ultralightSignature,
      Uint8List? ultralightVersion,
      List<int>? ultralightCounters})
      : ultralightSignature = ultralightSignature ?? Uint8List(0),
        ultralightVersion = ultralightVersion ?? Uint8List(0),
        ultralightCounters = ultralightCounters ?? <int>[];
}

/// A saved place (home, office, ...) bound to a device slot. When the user
/// enters [radius] meters of ([latitude], [longitude]) the app can auto
/// activate the emulated card in [slot] (0-7).
class LocationSlot {
  String id;
  String name;
  double latitude;
  double longitude;
  double radius; // meters
  int slot; // 0-7
  bool enabled;

  LocationSlot({
    String? id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radius = 150,
    this.slot = 0,
    this.enabled = true,
  }) : id = id ?? const Uuid().v4();

  factory LocationSlot.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    return LocationSlot(
      id: data['id'] as String,
      name: data['name'] as String,
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      radius: (data['radius'] as num?)?.toDouble() ?? 150,
      slot: (data['slot'] as num?)?.toInt() ?? 0,
      enabled: data['enabled'] as bool? ?? true,
    );
  }

  String toJson() => jsonEncode({
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
        'slot': slot,
        'enabled': enabled,
      });
}

/// A time-based rule that activates [slot] during a daily window. [weekdays]
/// uses DateTime weekday numbering (1=Mon .. 7=Sun); an empty list means every
/// day. Windows where [startMinutes] > [endMinutes] wrap past midnight.
class ScheduleSlot {
  String id;
  String name;
  int startMinutes; // minutes since midnight
  int endMinutes;
  List<int> weekdays;
  int slot; // 0-7
  bool enabled;

  ScheduleSlot({
    String? id,
    required this.name,
    this.startMinutes = 8 * 60,
    this.endMinutes = 18 * 60,
    List<int>? weekdays,
    this.slot = 0,
    this.enabled = true,
  })  : id = id ?? const Uuid().v4(),
        weekdays = weekdays ?? <int>[];

  /// Whether the given time falls inside this rule's window and weekday set.
  bool matches(DateTime now) {
    if (!enabled) {
      return false;
    }
    if (weekdays.isNotEmpty && !weekdays.contains(now.weekday)) {
      return false;
    }
    final minutes = now.hour * 60 + now.minute;
    if (startMinutes <= endMinutes) {
      return minutes >= startMinutes && minutes < endMinutes;
    }
    // Wraps past midnight, e.g. 22:00 -> 06:00
    return minutes >= startMinutes || minutes < endMinutes;
  }

  factory ScheduleSlot.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    return ScheduleSlot(
      id: data['id'] as String,
      name: data['name'] as String,
      startMinutes: (data['startMinutes'] as num?)?.toInt() ?? 8 * 60,
      endMinutes: (data['endMinutes'] as num?)?.toInt() ?? 18 * 60,
      weekdays: (data['weekdays'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          <int>[],
      slot: (data['slot'] as num?)?.toInt() ?? 0,
      enabled: data['enabled'] as bool? ?? true,
    );
  }

  String toJson() => jsonEncode({
        'id': id,
        'name': name,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'weekdays': weekdays,
        'slot': slot,
        'enabled': enabled,
      });
}

/// A card that was deleted and can still be restored. Entries older than
/// [RecycleBinEntry.retentionDays] are purged automatically.
class RecycleBinEntry {
  static const int retentionDays = 30;

  final CardSave card;
  final int deletedAt; // millisecondsSinceEpoch

  RecycleBinEntry({required this.card, required this.deletedAt});

  factory RecycleBinEntry.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    return RecycleBinEntry(
      card: CardSave.fromJson(jsonEncode(data['card'])),
      deletedAt: (data['deletedAt'] as num).toInt(),
    );
  }

  String toJson() => jsonEncode({
        'card': jsonDecode(card.toJson()),
        'deletedAt': deletedAt,
      });
}

class SharedPreferencesProvider extends ChangeNotifier {
  SharedPreferencesProvider._privateConstructor();

  static final SharedPreferencesProvider _instance =
      SharedPreferencesProvider._privateConstructor();

  factory SharedPreferencesProvider() {
    return _instance;
  }

  late SharedPreferences _sharedPreferences;

  Future<void> load() async {
    _sharedPreferences = await SharedPreferences.getInstance();
  }

  ThemeMode getTheme() {
    final themeValue = _sharedPreferences.getInt('app_theme') ?? 0;
    return ThemeMode.values[themeValue];
  }

  void setTheme(ThemeMode theme) {
    _sharedPreferences.setInt('app_theme', theme.index);
  }

  bool getSideBarAutoExpansion() {
    return _sharedPreferences.getBool('sidebar_auto_expanded') ?? true;
  }

  bool getSideBarExpanded() {
    return _sharedPreferences.getBool('sidebar_expanded') ?? false;
  }

  int getSideBarExpandedIndex() {
    return _sharedPreferences.getInt('sidebar_expanded_index') ?? 1;
  }

  void setSideBarAutoExpansion(bool autoExpanded) {
    _sharedPreferences.setBool('sidebar_auto_expanded', autoExpanded);
  }

  void setSideBarExpanded(bool expanded) {
    _sharedPreferences.setBool('sidebar_expanded', expanded);
  }

  void setSideBarExpandedIndex(int index) {
    _sharedPreferences.setInt('sidebar_expanded_index', index);
  }

  int getThemeColorIndex() {
    // Default to iOS blue (index 2) so the app reads as iOS out of the box.
    return _sharedPreferences.getInt('app_theme_color') ?? 2;
  }

  MaterialColor getThemeColor() {
    return colors.getThemeColor(getThemeColorIndex());
  }

  Color getThemeComplementaryColor() {
    final themeMode = _sharedPreferences.getInt('app_theme') ?? 2;
    return colors.getThemeComplementary(themeMode, getThemeColorIndex());
  }

  void setThemeColor(int color) {
    _sharedPreferences.setInt('app_theme_color', color);
  }

  bool isDebugMode() {
    return _sharedPreferences.getBool('debug') ?? false;
  }

  void setDebugMode(bool value) {
    _sharedPreferences.setBool('debug', value);
  }

  bool isEmulatedChameleon() {
    return _sharedPreferences.getBool('emulate_device') ?? false;
  }

  void setEmulatedChameleon(bool value) {
    _sharedPreferences.setBool('emulate_device', value);
  }

  List<Dictionary> getDictionaries({int keyLength = 0}) {
    List<Dictionary> output = [];
    final data = _sharedPreferences.getStringList('dictionaries') ?? [];
    for (var dictionary in data) {
      Dictionary dict = Dictionary.fromJson(dictionary);
      if (keyLength == 0 || dict.keyLength == keyLength) {
        output.add(dict);
      }
    }
    return output;
  }

  void setDictionaries(List<Dictionary> dictionaries) {
    List<String> output = [];
    for (var dictionary in dictionaries) {
      if (dictionary.id != "") {
        // system empty dictionary, never save it
        output.add(dictionary.toJson());
      }
    }
    _sharedPreferences.setStringList('dictionaries', output);
  }

  List<DictionaryFolder> getDictionaryFolders() {
    final data = _sharedPreferences.getStringList('dictionary_folders') ?? [];
    return data.map(DictionaryFolder.fromJson).toList();
  }

  void setDictionaryFolders(List<DictionaryFolder> folders) {
    _sharedPreferences.setStringList(
      'dictionary_folders',
      folders.map((folder) => folder.toJson()).toList(),
    );
  }

  List<CardSave> getCards() {
    List<CardSave> output = [];
    final data = _sharedPreferences.getStringList('cards') ?? [];
    for (var tag in data) {
      output.add(CardSave.fromJson(tag));
    }
    return output;
  }

  void setCards(List<CardSave> cards) {
    List<String> output = [];
    for (var card in cards) {
      output.add(card.toJson());
    }
    _sharedPreferences.setStringList('cards', output);
  }

  List<CardFolder> getCardFolders() {
    final data = _sharedPreferences.getStringList('card_folders') ?? [];
    return data.map(CardFolder.fromJson).toList();
  }

  void setCardFolders(List<CardFolder> folders) {
    _sharedPreferences.setStringList(
      'card_folders',
      folders.map((folder) => folder.toJson()).toList(),
    );
  }

  void setLocale(Locale loc) {
    for (var locale in AppLocalizations.supportedLocales) {
      if (locale.toLanguageTag().toLowerCase() ==
          loc.toLanguageTag().toLowerCase()) {
        _sharedPreferences.setString('locale', loc.toLanguageTag());
        notifyListeners();
        return;
      }
    }
  }

  String getLocaleString() {
    return _sharedPreferences.getString("locale") ?? "en";
  }

  Locale getLocale() {
    final localeId = getLocaleString();
    Locale locale;
    if (localeId.contains("-")) {
      final [lcode, ccode] = localeId.toString().split("-");
      locale = Locale(lcode, ccode);
    } else {
      locale = Locale(localeId);
    }
    if (!AppLocalizations.supportedLocales.contains(locale)) {
      return const Locale('en');
    } else {
      return locale;
    }
  }

  void clearLocale() {
    _sharedPreferences.setString('locale', "en");
    notifyListeners();
  }

  bool isDebugLogging() {
    return _sharedPreferences.getBool('debug_logging') ?? false;
  }

  void setDebugLogging(bool value) {
    _sharedPreferences.setBool('debug_logging', value);
  }

  void addLogLine(String value) {
    List<String> rows =
        _sharedPreferences.getStringList('debug_logging_value') ?? [];
    rows.add(value);

    if (rows.length > 5000) {
      rows.removeAt(0);
    }

    _sharedPreferences.setStringList('debug_logging_value', rows);
  }

  void clearLogLines() {
    _sharedPreferences.setStringList('debug_logging_value', []);
  }

  List<String> getLogLines() {
    return _sharedPreferences.getStringList('debug_logging_value') ?? [];
  }

  String dumpSettingsToJson() {
    Map<String, dynamic> settingsMap = {};

    for (var key in _sharedPreferences.getKeys()) {
      if (key == "debug_logging_value") {
        continue;
      }
      var value = _sharedPreferences.get(key) as dynamic;
      if (value == null) {
        continue;
      }
      if (value is List) {
        // this hack is needed in order to output proper json with objects instead of objects-in-strings
        value = value.map((e) => jsonDecode(e)).toList();
      }
      settingsMap[key] = value;
    }

    return jsonEncode(settingsMap);
  }

  void restoreSettingsFromJson(String jsonSettings) {
    Map<String, dynamic> settingsMap = jsonDecode(jsonSettings);

    for (var key in settingsMap.keys) {
      dynamic value = settingsMap[key];

      if (value == null) {
        continue;
      }
      switch (value) {
        case String s:
          _sharedPreferences.setString(key, s);
          break;
        case int i:
          _sharedPreferences.setInt(key, i);
          break;
        case double d:
          _sharedPreferences.setDouble(key, d);
          break;
        case bool b:
          _sharedPreferences.setBool(key, b);
          break;
        case List l:
          // this is the reverse of the hack above :)
          _sharedPreferences.setStringList(
              key, l.map((e) => jsonEncode(e)).toList());
          break;
        default:
          break;
      }
    }
  }

  bool getConfirmDelete() {
    return _sharedPreferences.getBool('confirm_delete') ?? true;
  }

  void setConfirmDelete(bool value) {
    _sharedPreferences.setBool('confirm_delete', value);
  }

  bool getAutoScanEnabled() {
    return _sharedPreferences.getBool('auto_scan_enabled') ?? true;
  }

  void setAutoScanEnabled(bool value) {
    _sharedPreferences.setBool('auto_scan_enabled', value);
  }

  bool getAutoConnectFirstFoundDevice() {
    return _sharedPreferences.getBool('auto_connect_first_found') ?? false;
  }

  void setAutoConnectFirstFoundDevice(bool value) {
    _sharedPreferences.setBool('auto_connect_first_found', value);
  }

  List<LocationSlot> getLocationSlots() {
    final data = _sharedPreferences.getStringList('location_slots') ?? [];
    return data.map(LocationSlot.fromJson).toList();
  }

  void setLocationSlots(List<LocationSlot> slots) {
    _sharedPreferences.setStringList(
        'location_slots', slots.map((slot) => slot.toJson()).toList());
    notifyListeners();
  }

  bool getLocationSwitchEnabled() {
    return _sharedPreferences.getBool('location_switch_enabled') ?? false;
  }

  void setLocationSwitchEnabled(bool value) {
    _sharedPreferences.setBool('location_switch_enabled', value);
    notifyListeners();
  }

  List<ScheduleSlot> getScheduleSlots() {
    final data = _sharedPreferences.getStringList('schedule_slots') ?? [];
    return data.map(ScheduleSlot.fromJson).toList();
  }

  void setScheduleSlots(List<ScheduleSlot> slots) {
    _sharedPreferences.setStringList(
        'schedule_slots', slots.map((slot) => slot.toJson()).toList());
    notifyListeners();
  }

  bool getScheduleSwitchEnabled() {
    return _sharedPreferences.getBool('schedule_switch_enabled') ?? false;
  }

  void setScheduleSwitchEnabled(bool value) {
    _sharedPreferences.setBool('schedule_switch_enabled', value);
    notifyListeners();
  }

  List<RecycleBinEntry> getRecycleBin() {
    final data = _sharedPreferences.getStringList('recycle_bin') ?? [];
    return data.map(RecycleBinEntry.fromJson).toList();
  }

  void _setRecycleBin(List<RecycleBinEntry> entries) {
    _sharedPreferences.setStringList(
        'recycle_bin', entries.map((entry) => entry.toJson()).toList());
  }

  /// Removes entries older than the retention window. Returns the survivors.
  List<RecycleBinEntry> purgeExpiredRecycleBin() {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: RecycleBinEntry.retentionDays))
        .millisecondsSinceEpoch;
    final entries =
        getRecycleBin().where((entry) => entry.deletedAt >= cutoff).toList();
    _setRecycleBin(entries);
    return entries;
  }

  void moveCardToRecycleBin(CardSave card) {
    final entries = getRecycleBin();
    entries.add(RecycleBinEntry(
        card: card, deletedAt: DateTime.now().millisecondsSinceEpoch));
    _setRecycleBin(entries);

    final cards = getCards()..removeWhere((c) => c.id == card.id);
    setCards(cards);
  }

  void restoreFromRecycleBin(String cardId) {
    final entries = getRecycleBin();
    final entry = entries.cast<RecycleBinEntry?>().firstWhere(
          (e) => e?.card.id == cardId,
          orElse: () => null,
        );
    if (entry == null) {
      return;
    }
    entries.removeWhere((e) => e.card.id == cardId);
    _setRecycleBin(entries);

    final cards = getCards();
    // Guard against duplicate ids if the card was somehow re-created.
    if (!cards.any((c) => c.id == entry.card.id)) {
      cards.add(entry.card);
      setCards(cards);
    } else {
      notifyListeners();
    }
  }

  void deleteFromRecycleBin(String cardId) {
    final entries = getRecycleBin()
      ..removeWhere((e) => e.card.id == cardId);
    _setRecycleBin(entries);
    notifyListeners();
  }

  void emptyRecycleBin() {
    _setRecycleBin([]);
    notifyListeners();
  }
}
