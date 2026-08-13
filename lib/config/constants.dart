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

/// WhatsApp Cloud API Configuration
class WhatsAppConfig {
  static const String businessAccountId = '1747544579732026';
  static const String phoneNumberId = '1288955460961328';
  static const String accessToken =
      'EAATJcfK3ZC2cBSMWa3ZCFbQdzQTzZAfBqpCouYeLRuvlDg2d3O6ztAQWANZAqZCaZAo5ZAlYv2suab9raRpvpluTGAe6a4cI0cqUvhZCnUc9N4YMyUCt2pVX0lFg8QwZAFOzWZBhp96CZA1WEOfGFwxmPYRdIiirrdp4fpjuEORmPUNNwOLIiKNL8uBcXfWNwSh4BSeB6oaBBDVVHXqiJ7oh07CckFEgMdiZB1AhLvhyScMXiR5rLUhBfp7FTxTZBZCovLE5yyZA5IRvS15ChLKYHDKZAthZCzaiF';

  static const String apiVersion = 'v20.0';
  static String get mediaUploadUrl =>
      'https://graph.facebook.com/$apiVersion/$phoneNumberId/media';
  static String get sendMessageUrl =>
      'https://graph.facebook.com/$apiVersion/$phoneNumberId/messages';
}

