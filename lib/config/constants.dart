// lib/config/constants.dart

class AppNetwork {
  static const int websocketPort     = 53281;
  static const int udpBroadcastPort  = 45454;
  static const String udpMessagePrefix = 'GMWF_TOKEN_SERVER_I_AM:';

  // ── Dedicated-server mode ──────────────────────────────────────────────────
  // Set useDedicatedServer = true when your network has AP isolation enabled
  // (most routers block device-to-device UDP/mDNS by default). With this on,
  // ConnectionManager skips all auto-discovery and connects straight to
  // dedicatedServerIp. Set the IP to your server device's static LAN address.
  //
  // Leave useDedicatedServer = false to keep the auto-discovery behaviour
  // (mDNS → UDP broadcast → subnet scan).
  static const bool useDedicatedServer  = false; // ← set true when ready
  static const String dedicatedServerIp = '192.168.1.100'; // ← your server IP
}