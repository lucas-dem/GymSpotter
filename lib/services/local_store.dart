import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/workout.dart';
import 'store_migrations.dart';

/// Indicador de que el blob guardado no se pudo usar tal cual y quedó una
/// copia cruda de rescate.
@immutable
class StoreRescue {
  const StoreRescue({
    required this.reason,
    required this.slot,
    required this.where,
    required this.at,
    this.version,
    this.error,
    this.count = 1,
  });

  /// `unreadable`, `notAMap`, `unsupportedVersion`, `migrationFailed`,
  /// `itemsSkipped` (se salteó algún ítem ilegible) o `loadFailed`.
  final String reason;

  /// Copia con el crudo de este incidente (ver [Store.rescueCopies]).
  final String slot;

  /// `file` (directorio de documentos de la app) o `prefs` (si no hubo archivo).
  final String where;
  final DateTime at;
  final int? version;

  /// Solo el tipo del error: el mensaje puede incluir datos del usuario.
  final String? error;

  /// Incidentes acumulados desde que existe el indicador.
  final int count;

  Map<String, dynamic> toJson() => {
    'reason': reason,
    'slot': slot,
    'where': where,
    'at': at.toIso8601String(),
    if (version != null) 'version': version,
    if (error != null) 'error': error,
    'count': count,
  };

  static StoreRescue? tryParse(Object? raw) {
    if (raw is! String) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return StoreRescue(
        reason: j['reason'] as String,
        slot: j['slot'] as String,
        where: j['where'] as String,
        at: DateTime.parse(j['at'] as String),
        version: j['version'] as int?,
        error: j['error'] as String?,
        count: j['count'] as int? ?? 1,
      );
    } catch (_) {
      return null;
    }
  }
}

class Store {
  Store._();
  static final Store instance = Store._();

  static const _key = 'gymmane_v1';
  static const _rescueKey = '${_key}_rescue';
  static const _rescueDirName = 'data_rescue';

  /// Copias de rescate que se conservan como mucho.
  static const maxRescueCopies = 3;

  // Nombres de la primera versión de esta capa (sesión 16): cuentan como las
  // copias más viejas.
  static const _legacySlots = ['first', 'premigration', 'last'];

  static String? _rescueDir;
  static bool _rescueDirKnown = false;

  SharedPreferences? _prefs;
  int _schemaVersion = kStoreSchemaVersion;
  Map<int, StoreMigration> _migrations = kStoreMigrations;
  int? _storedVersion;
  String? _rescuedRaw;

  /// Directorio de las copias de rescate. `null` = solo SharedPreferences.
  @visibleForTesting
  static set rescueDirectory(String? path) {
    _rescueDir = path;
    _rescueDirKnown = true;
  }

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    if (_rescueDirKnown) return;
    _rescueDirKnown = true;
    try {
      final docs = await getApplicationDocumentsDirectory();
      _rescueDir = '${docs.path}/$_rescueDirName';
    } catch (_) {
      _rescueDir = null;
    }
  }

  /// Lee el blob. Si no se puede usar tal cual, primero deja una copia cruda
  /// (antes de que cualquier guardado pueda pisarla) y devuelve lo utilizable.
  Map<String, dynamic> load() {
    final raw = _storedRaw();
    if (raw == null || raw.isEmpty) return {};
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (error) {
      _rescue('unreadable', raw, error: error);
      return {};
    }
    if (decoded is! Map<String, dynamic>) {
      _rescue('notAMap', raw);
      return {};
    }
    return _upgrade(decoded, raw);
  }

  Map<String, dynamic> _upgrade(Map<String, dynamic> stored, String raw) {
    final tag = stored[kSchemaVersionKey];
    final data = tag == null ? stored : (Map<String, dynamic>.of(stored)..remove(kSchemaVersionKey));
    final version = tag == null ? 1 : (tag is int ? tag : -1);
    _storedVersion = version;
    if (version == _schemaVersion) return data;
    if (version < 1 || version > _schemaVersion) {
      _rescue('unsupportedVersion', raw, version: tag is int ? tag : null);
      return data;
    }
    _saveCopy(raw);
    try {
      return runStoreMigrations(data, from: version, to: _schemaVersion, migrations: _migrations);
    } catch (error) {
      _rescue('migrationFailed', raw, version: version, error: error);
      // Cada paso recibe una copia superficial: si tocó una lista o un mapa
      // anidado antes de fallar, `data` quedó migrado a medias. Se carga el
      // crudo de nuevo, sin migrar.
      return (jsonDecode(raw) as Map<String, dynamic>)..remove(kSchemaVersionKey);
    }
  }

  /// La carga en FitState falló (p. ej. un tipo inesperado): copia el crudo
  /// antes de que la app vuelva a guardar.
  void preserveStored(String reason, {Object? error}) {
    final raw = _storedRaw();
    if (raw == null || raw.isEmpty) return;
    _rescue(reason, raw, version: _storedVersion, error: error);
  }

  /// Último incidente registrado, para un aviso futuro. `null` = nunca hubo.
  StoreRescue? get rescue => StoreRescue.tryParse(_prefs?.get(_rescueKey));

  /// Copias de rescate que hay, de la más vieja a la más nueva.
  List<String> get rescueCopies {
    final ids = <String>{};
    final dir = _rescueDir;
    try {
      if (dir != null && Directory(dir).existsSync()) {
        for (final f in Directory(dir).listSync()) {
          final name = f.uri.pathSegments.last;
          if (f is! File || !name.endsWith('.json')) continue;
          final id = name.substring(0, name.length - '.json'.length);
          if (_isCopyId(id)) ids.add(id);
        }
      }
    } catch (_) {}
    for (final key in _prefs?.getKeys() ?? const <String>{}) {
      if (!key.startsWith('${_rescueKey}_')) continue;
      final id = key.substring(_rescueKey.length + 1);
      if (_isCopyId(id)) ids.add(id);
    }
    return ids.toList()..sort((a, b) => _age(a).compareTo(_age(b)));
  }

  /// Crudo guardado en la copia [slot] (uno de [rescueCopies]).
  String? readRescueCopy(String slot) {
    final file = _slotFile(slot);
    try {
      if (file != null && file.existsSync()) return file.readAsStringSync();
    } catch (_) {}
    final kept = _prefs?.get(_prefsSlot(slot));
    return kept is String ? kept : null;
  }

  @visibleForTesting
  void debugSchema(int version, Map<int, StoreMigration> migrations) {
    _schemaVersion = version;
    _migrations = migrations;
  }

  @visibleForTesting
  void debugReset() {
    _prefs = null;
    _schemaVersion = kStoreSchemaVersion;
    _migrations = kStoreMigrations;
    _storedVersion = null;
    _rescuedRaw = null;
  }

  String? _storedRaw() {
    final value = _prefs?.get(_key);
    if (value == null) return null;
    return value is String ? value : '$value';
  }

  void _rescue(String reason, String raw, {int? version, Object? error}) {
    if (raw == _rescuedRaw) return;
    final copy = _saveCopy(raw);
    final notice = StoreRescue(
      reason: reason,
      slot: copy.id,
      where: copy.where,
      at: DateTime.now(),
      version: version,
      error: error?.runtimeType.toString(),
      count: (rescue?.count ?? 0) + 1,
    );
    _prefs?.setString(_rescueKey, jsonEncode(notice.toJson()));
    _rescuedRaw = raw;
  }

  /// Escribe la copia de forma atómica (.tmp + rename). Sin directorio o si
  /// falla, la deja en SharedPreferences. Devuelve dónde quedó.
  String _writeCopy(String slot, String raw) {
    final file = _slotFile(slot);
    if (file != null) {
      try {
        file.parent.createSync(recursive: true);
        final tmp = File('${file.path}.tmp')..writeAsStringSync(raw, flush: true);
        tmp.renameSync(file.path);
        _prefs?.remove(_prefsSlot(slot));
        return 'file';
      } catch (_) {}
    }
    _prefs?.setString(_prefsSlot(slot), raw);
    return 'prefs';
  }

  /// Guarda [raw] como copia de rescate y deja como mucho [maxRescueCopies].
  /// Si ya hay una copia con el mismo contenido, no escribe otra.
  ({String id, String where}) _saveCopy(String raw) {
    final ids = rescueCopies;
    for (final id in ids) {
      if (readRescueCopy(id) == raw) return (id: id, where: _whereOf(id));
    }
    final id = _newCopyId(ids);
    final where = _writeCopy(id, raw);
    _rotate([...ids, id], keep: id);
    return (id: id, where: where);
  }

  // Cuando sobran copias se descartan primero las que no se pueden recuperar,
  // de la más vieja a la más nueva, y después las útiles más viejas. Nunca la
  // última copia útil ni la que se acaba de escribir.
  void _rotate(List<String> ids, {required String keep}) {
    var extra = ids.length - maxRescueCopies;
    if (extra <= 0) return;
    final useful = {
      for (final id in ids)
        if (_isUseful(readRescueCopy(id))) id,
    };
    final lastUseful = ids.lastWhere(useful.contains, orElse: () => keep);
    final order = [...ids.where((id) => !useful.contains(id)), ...ids.where(useful.contains)];
    for (final id in order) {
      if (extra <= 0) break;
      if (id == keep || id == lastUseful) continue;
      _deleteCopy(id);
      extra--;
    }
  }

  /// Una copia es útil si se puede recuperar: es un objeto JSON.
  static bool _isUseful(String? raw) {
    if (raw == null) return false;
    try {
      return jsonDecode(raw) is Map<String, dynamic>;
    } catch (_) {
      return false;
    }
  }

  void _deleteCopy(String id) {
    try {
      final file = _slotFile(id);
      if (file != null && file.existsSync()) file.deleteSync();
    } catch (_) {}
    _prefs?.remove(_prefsSlot(id));
  }

  String _whereOf(String id) {
    final file = _slotFile(id);
    return file != null && file.existsSync() ? 'file' : 'prefs';
  }

  // Microsegundos desde 1970, siempre mayor que el de la copia más nueva.
  static String _newCopyId(List<String> ids) {
    var next = DateTime.now().microsecondsSinceEpoch;
    for (final id in ids) {
      final age = _age(id);
      if (age >= next) next = age + 1;
    }
    return '$next';
  }

  // Solo nombres que escribe esta capa: los de la s16 o un número que entra en un int.
  static bool _isCopyId(String id) =>
      _legacySlots.contains(id) || (RegExp(r'^\d+$').hasMatch(id) && int.tryParse(id) != null);

  static int _age(String id) {
    final legacy = _legacySlots.indexOf(id);
    return legacy >= 0 ? legacy - _legacySlots.length : int.parse(id);
  }

  File? _slotFile(String slot) => _rescueDir == null ? null : File('$_rescueDir/$slot.json');

  static String _prefsSlot(String slot) => '${_rescueKey}_$slot';

  String? note(String key) => _prefs?.getString('gm_$key');

  void setNote(String key, String value) => _prefs?.setString('gm_$key', value);

  /// Guarda el estado agregando la versión de formato. `toJson()` y los
  /// backups exportados no cambian: la versión solo vive en el almacenamiento.
  Future<void> save(Map<String, dynamic> data) async {
    try {
      await _prefs?.setString(_key, jsonEncode({...data, kSchemaVersionKey: _schemaVersion}));
    } catch (_) {}
  }

  String exportJson(Map<String, dynamic> data) => const JsonEncoder.withIndent('  ').convert(data);

  String exportCsv(List<LoggedSession> sessions) {
    final rows = StringBuffer(
      'date,exercise,muscle,set,reps,weight_kg,volume_kg,est_1rm_kg,distance_km,duration_s,rpe\n',
    );
    final ordered = [...sessions]..sort((a, b) => a.date.compareTo(b.date));
    for (final s in ordered) {
      final day = s.date.toIso8601String().split('T').first;
      for (final e in s.exercises) {
        for (var i = 0; i < e.sets.length; i++) {
          final st = e.sets[i];
          rows.writeln(
            [
              day,
              _csv(e.name),
              e.primary,
              i + 1,
              st.reps,
              _num(st.weight),
              _num(st.volume),
              _num(st.oneRm),
              st.km == null ? '' : _num(st.km!),
              st.sec ?? '',
              st.rpe == null ? '' : _num(st.rpe!),
            ].join(','),
          );
        }
      }
    }
    return rows.toString();
  }

  static String _csv(String v) => v.contains(RegExp('[",\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

  static String _num(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  Map<String, dynamic>? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
