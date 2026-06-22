const appEnvironment = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

bool get isProduction => appEnvironment.toLowerCase() == 'prod';
