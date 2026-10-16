// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_files.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The filesystem bridge, overridden in tests with an in-memory implementation.

@ProviderFor(backupFiles)
final backupFilesProvider = BackupFilesProvider._();

/// The filesystem bridge, overridden in tests with an in-memory implementation.

final class BackupFilesProvider
    extends $FunctionalProvider<BackupFiles, BackupFiles, BackupFiles>
    with $Provider<BackupFiles> {
  /// The filesystem bridge, overridden in tests with an in-memory implementation.
  BackupFilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupFilesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupFilesHash();

  @$internal
  @override
  $ProviderElement<BackupFiles> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BackupFiles create(Ref ref) {
    return backupFiles(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackupFiles value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackupFiles>(value),
    );
  }
}

String _$backupFilesHash() => r'4000981a32dcfddc842a8bffccf47b6818194684';

/// The exporter, wired to the real repositories.

@ProviderFor(backupExporter)
final backupExporterProvider = BackupExporterProvider._();

/// The exporter, wired to the real repositories.

final class BackupExporterProvider
    extends $FunctionalProvider<BackupExporter, BackupExporter, BackupExporter>
    with $Provider<BackupExporter> {
  /// The exporter, wired to the real repositories.
  BackupExporterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupExporterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupExporterHash();

  @$internal
  @override
  $ProviderElement<BackupExporter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BackupExporter create(Ref ref) {
    return backupExporter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackupExporter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackupExporter>(value),
    );
  }
}

String _$backupExporterHash() => r'5a6995abbd30490ffe8a8cfb8c94666855ad3176';

/// The importer, wired to the real repositories.

@ProviderFor(backupImporter)
final backupImporterProvider = BackupImporterProvider._();

/// The importer, wired to the real repositories.

final class BackupImporterProvider
    extends $FunctionalProvider<BackupImporter, BackupImporter, BackupImporter>
    with $Provider<BackupImporter> {
  /// The importer, wired to the real repositories.
  BackupImporterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupImporterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupImporterHash();

  @$internal
  @override
  $ProviderElement<BackupImporter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BackupImporter create(Ref ref) {
    return backupImporter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackupImporter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackupImporter>(value),
    );
  }
}

String _$backupImporterHash() => r'6f20f97d621ca36a55fdecc164515a748ff31ffc';
