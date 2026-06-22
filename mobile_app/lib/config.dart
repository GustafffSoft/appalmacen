import 'package:flutter/foundation.dart';

const _backendOverride = String.fromEnvironment('BACKEND_BASE_URL');
const _backendWeb = 'https://appalmacen-backend.onrender.com';
const _backendMobile = 'https://appalmacen-backend.onrender.com';

String get backendBaseUrl {
  if (_backendOverride.isNotEmpty) {
    return _backendOverride;
  }
  return kIsWeb ? _backendWeb : _backendMobile;
}
