/// Versionado del blob `gymmane_v1` (ver `Store` en local_store.dart).
///
/// - Un blob sin [kSchemaVersionKey] es el formato de 1.3.x: versión 1.
/// - [kStoreMigrations] va hacia adelante: la clave es la versión DESDE la
///   que migra. Cada paso recibe una copia superficial (las listas y mapas
///   anidados son compartidos) y devuelve un mapa nuevo, sin borrar datos del
///   usuario (renombrar o agregar, nunca descartar). Antes de migrar, `Store`
///   guarda el crudo original en la copia `premigration`; si un paso falla,
///   carga ese crudo de nuevo, sin migrar.
/// - Al subir [kStoreSchemaVersion] hay que agregar el paso que falta; el test
///   `store_rescue_test.dart` lo vigila.
library;

typedef StoreMigration = Map<String, dynamic> Function(Map<String, dynamic> data);

const String kSchemaVersionKey = 'schemaVersion';

const int kStoreSchemaVersion = 1;

const Map<int, StoreMigration> kStoreMigrations = {};

/// Aplica en orden los pasos de [from] a [to]. Lanza si falta alguno.
Map<String, dynamic> runStoreMigrations(
  Map<String, dynamic> data, {
  required int from,
  required int to,
  required Map<int, StoreMigration> migrations,
}) {
  var current = data;
  for (var version = from; version < to; version++) {
    final step = migrations[version];
    if (step == null) throw StateError('Falta la migración $version -> ${version + 1}');
    current = step(Map<String, dynamic>.of(current));
  }
  return current;
}
