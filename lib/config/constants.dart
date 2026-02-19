class AppNetwork {
  static const int websocketPort = 53281;
  static const int udpBroadcastPort = 45454;
  static const String udpMessagePrefix = "GMWF_TOKEN_SERVER_I_AM:";
  
  // ============== ADD THESE ==============
  static const bool useDedicatedServer = false;  // Change to true when ready
  static const String dedicatedServerIp = '192.168.1.100';  // Your server device IP
  // =======================================
}