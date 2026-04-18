import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkStatusService {
  NetworkStatusService._internal();
  static final NetworkStatusService _instance = NetworkStatusService._internal();
  factory NetworkStatusService() => _instance;

  final Connectivity _connectivity = Connectivity();

  Stream<bool> get onlineChanges {
    return _connectivity.onConnectivityChanged
        .map((dynamic event) => _isOnlineFromEvent(event))
        .distinct();
  }

  Future<bool> isOnline() async {
    final dynamic result = await _connectivity.checkConnectivity();
    return _isOnlineFromEvent(result);
  }

  bool _isOnlineFromEvent(dynamic event) {
    if (event is ConnectivityResult) {
      return event != ConnectivityResult.none;
    }

    if (event is List) {
      for (final item in event) {
        if (item is ConnectivityResult && item != ConnectivityResult.none) {
          return true;
        }
      }
      return false;
    }

    // If connectivity plugin returns an unknown value, avoid false negatives.
    return true;
  }
}
