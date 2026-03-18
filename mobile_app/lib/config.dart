import 'package:flutter/foundation.dart';

const _backendWeb = 'http://127.0.0.1:8000';
const _backendMobile = 'http://10.0.0.248:8000';

String get backendBaseUrl => kIsWeb ? _backendWeb : _backendMobile;