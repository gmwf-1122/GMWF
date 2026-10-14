// lib/pages/dispensary/widgets/connection_status_same.dart
//
// ConnectionStatus has no value equality, and the status stream re-emits the same
// state often; screens use this to skip a full-screen setState when nothing changed.

import 'package:gmwf/realtime/connection_manager.dart';

extension ConnectionStatusSame on ConnectionStatus {
  bool sameAs(ConnectionStatus other) =>
      state == other.state && ip == other.ip && port == other.port && message == other.message;
}
