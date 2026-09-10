import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
/// 
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDwBEnHBdT5UgF1KV3wbG5EvyL9tAAbAZw',
    appId: '1:910693440390:web:583bc762cb6a481857aa07',
    messagingSenderId: '910693440390',
    projectId: 'icafe-29a92',
    authDomain: 'icafe-29a92.firebaseapp.com',
    storageBucket: 'icafe-29a92.firebasestorage.app',
    measurementId: 'G-QFET7JVK2G',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDBoydagCuDRBti3--_-C6My9NaQCsW1Pc',
    appId: '1:910693440390:ios:eacb39f1e8a6013157aa07',
    messagingSenderId: '910693440390',
    projectId: 'icafe-29a92',
    storageBucket: 'icafe-29a92.firebasestorage.app',
    iosBundleId: 'com.icafe.icafe',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAzIuw-eHuHY21ihJ2XH7Ha98exGWqxpxY',
    appId: '1:910693440390:android:882aba550da81ed757aa07',
    messagingSenderId: '910693440390',
    projectId: 'icafe-29a92',
    storageBucket: 'icafe-29a92.firebasestorage.app',
  );
}
