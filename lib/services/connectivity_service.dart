import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<bool> get changes => _connectivity.onConnectivityChanged.map(_hasConnection).distinct();

  Future<bool> check() async => _hasConnection(await _connectivity.checkConnectivity());

  bool _hasConnection(List<ConnectivityResult> results) => results.any((result) => result != ConnectivityResult.none);
}
