import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class FeedbackService {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> playAdd() async {
    try {
      HapticFeedback.selectionClick();
      if (!kIsWeb) {
        await _player.play(AssetSource('sounds/click.wav'));
      }
    } catch (e) {
      debugPrint('Error playing add feedback: $e');
    }
  }

  static Future<void> playSuccess() async {
    try {
      HapticFeedback.mediumImpact();
      if (!kIsWeb) {
        await _player.play(AssetSource('sounds/success.wav'));
      }
    } catch (e) {
      debugPrint('Error playing success feedback: $e');
    }
  }

  static Future<void> playError() async {
    try {
      HapticFeedback.heavyImpact();
      if (!kIsWeb) {
        await _player.play(AssetSource('sounds/error.wav'));
      }
    } catch (e) {
      debugPrint('Error playing error feedback: $e');
    }
  }
}
