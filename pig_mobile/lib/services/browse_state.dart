import 'package:flutter/foundation.dart';
import '../models/song.dart';
import 'pig_web_service.dart';

/// Shared state between Browse and Player.
/// Browse writes the queue here. Player reads it.
class BrowseState extends ChangeNotifier {
  List<Song> _queue = [];
  bool _isWeb = false;
  PigWebService? _webService;

  List<Song> get queue => _queue;
  bool get hasQueue => _queue.isNotEmpty;
  bool get isWeb => _isWeb;
  PigWebService? get webService => _webService;

  void setQueue(
    List<Song> songs, {
    bool isWeb = false,
    PigWebService? webService,
  }) {
    _queue = songs;
    _isWeb = isWeb;
    _webService = webService;
    notifyListeners();
  }

  void clear() {
    _queue = [];
    _isWeb = false;
    _webService = null;
    notifyListeners();
  }
}
