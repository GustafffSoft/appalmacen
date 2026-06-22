import 'package:flutter/foundation.dart';

import 'app_environment.dart';

const _backendOverride = String.fromEnvironment('BACKEND_BASE_URL');
const _backendProduction = String.fromEnvironment('BACKEND_PROD_URL');
const _backendDevelopmentWeb = 'http://127.0.0.1:8000';
const _backendDevelopmentMobile = 'http://10.0.2.2:8000';

String get backendBaseUrl {
  if (_backendOverride.isNotEmpty) {
    return _backendOverride;
  }
  if (isProduction) {
    if (_backendProduction.isEmpty) {
      throw StateError('BACKEND_PROD_URL is required when APP_ENV=prod.');
    }
    return _backendProduction;
  }
  return kIsWeb ? _backendDevelopmentWeb : _backendDevelopmentMobile;
}
