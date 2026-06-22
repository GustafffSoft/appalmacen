// Production web configuration for appalmacen-prod-5e987.
// Firebase API keys identify the project; access is enforced by Auth and rules.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class ProductionFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb) {
      throw UnsupportedError(
        'Production Firebase is currently configured for Flutter Web only.',
      );
    }
    return web;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDZHNsJksaOiMpZOKXbCbYU-5lWFQHY338',
    appId: '1:832045936244:web:0f1841d8c4552b3e8bab21',
    messagingSenderId: '832045936244',
    projectId: 'appalmacen-prod-5e987',
    authDomain: 'appalmacen-prod-5e987.firebaseapp.com',
    storageBucket: 'appalmacen-prod-5e987.firebasestorage.app',
  );
}
