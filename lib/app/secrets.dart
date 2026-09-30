import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedSecrets {
  final String deepSeekKey;
  final String deepSeekBase;
  final String deepSeekModel;

  const SavedSecrets({
    this.deepSeekKey = '',
    this.deepSeekBase = 'https://api.deepseek.com',
    this.deepSeekModel = 'deepseek-flash',
  });
}

/// Local smoke: skip libsecret/keyring prompts on Linux desktop.
class _MemoryStorage extends FlutterSecureStorage {
  static final Map<String, String> _data = <String, String>{};

  const _MemoryStorage() : super();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async => _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    _data.remove(key);
  }
}

class SecureSecrets {
  SecureSecrets({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          (Platform.isLinux
              ? const _MemoryStorage()
              : const FlutterSecureStorage());

  final FlutterSecureStorage _storage;

  Future<SavedSecrets> load() async {
    // Drop legacy TokenHub keys if still present.
    _write('tokenhub_key', '');
    _write('tokenhub_base', '');
    _write('tokenhub_model', '');
    return SavedSecrets(
      deepSeekKey: await _read('deepseek_key'),
      deepSeekBase: await _read(
        'deepseek_base',
        fallback: 'https://api.deepseek.com',
      ),
      deepSeekModel: await _read('deepseek_model', fallback: 'deepseek-flash'),
    );
  }

  void save(SavedSecrets secrets) {
    _write('deepseek_key', secrets.deepSeekKey);
    _write('deepseek_base', secrets.deepSeekBase);
    _write('deepseek_model', secrets.deepSeekModel);
    _write('tokenhub_key', '');
    _write('tokenhub_base', '');
    _write('tokenhub_model', '');
  }

  Future<String> _read(String key, {String fallback = ''}) async {
    try {
      final value = await _storage.read(key: key);
      if (value == null || value.trim().isEmpty) return fallback;
      return value.trim();
    } on Object {
      return fallback;
    }
  }

  void _write(String key, String value) {
    final trimmed = value.trim();
    final Future<void> op = trimmed.isEmpty
        ? _storage.delete(key: key)
        : _storage.write(key: key, value: trimmed);
    op.catchError((Object _) {}).ignore();
  }
}
