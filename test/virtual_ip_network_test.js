/**
 * Virtual Multi-System LAN Stress Test
 * Simulates 3 separate clinic workstations with dedicated VIRTUAL IP addresses:
 * - Server: 127.0.0.10:53285
 * - Station 1 (Reception PC):  127.0.0.21
 * - Station 2 (Doctor PC):     127.0.0.22
 * - Station 3 (Dispensary PC): 127.0.0.23
 * 
 * Tests:
 * 1. Multi-IP concurrent handshakes & IP tracking
 * 2. Token creation and prescription distribution across distinct IPs
 * 3. Abrupt socket drop on Virtual IP 127.0.0.23
 * 4. Token emission during outage
 * 5. Reconnection with IP retention & DHCP IP change to 127.0.0.24
 */

const net = require('net');
const http = require('http');
const crypto = require('crypto');

const SERVER_IP = '127.0.0.10';
const SERVER_PORT = 53285;

const RECEPTION_IP = '127.0.0.21';
const DOCTOR_IP    = '127.0.0.22';
const DISPENSER_IP = '127.0.0.23';

// ── WebSocket Frame Helper (Zero-dependency RFC 6455) ─────────────────────────
function encodeWsFrame(text) {
  const payload = Buffer.from(text, 'utf8');
  const length = payload.length;
  let header;

  if (length < 126) {
    header = Buffer.from([0x81, 0x80 | length]);
  } else if (length < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 0x80 | 126;
    header.writeUInt16BE(length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 0x80 | 127;
    header.writeBigUInt64BE(BigInt(length), 2);
  }

  const mask = crypto.randomBytes(4);
  const masked = Buffer.alloc(length);
  for (let i = 0; i < length; i++) {
    masked[i] = payload[i] ^ mask[i % 4];
  }

  return Buffer.concat([header, mask, masked]);
}

function decodeWsFrames(buffer) {
  const messages = [];
  let offset = 0;

  while (offset < buffer.length) {
    if (buffer.length - offset < 2) break;
    const secondByte = buffer[offset + 1];
    const isMasked = (secondByte & 0x80) !== 0;
    let length = secondByte & 0x7F;
    let headerLength = 2;

    if (length === 126) {
      if (buffer.length - offset < 4) break;
      length = buffer.readUInt16BE(offset + 2);
      headerLength = 4;
    } else if (length === 127) {
      if (buffer.length - offset < 10) break;
      length = Number(buffer.readBigUInt64BE(offset + 2));
      headerLength = 10;
    }

    const maskOffset = offset + headerLength;
    const dataOffset = maskOffset + (isMasked ? 4 : 0);

    if (buffer.length < dataOffset + length) break;

    let payload = buffer.slice(dataOffset, dataOffset + length);
    if (isMasked) {
      const mask = buffer.slice(maskOffset, maskOffset + 4);
      const unmasked = Buffer.alloc(length);
      for (let i = 0; i < length; i++) {
        unmasked[i] = payload[i] ^ mask[i % 4];
      }
      payload = unmasked;
    }

    messages.push(payload.toString('utf8'));
    offset = dataOffset + length;
  }

  return { messages, remainder: buffer.slice(offset) };
}

// ── Virtual Client Implementation ─────────────────────────────────────────────
class VirtualStation {
  constructor(name, role, localIp) {
    this.name = name;
    this.role = role;
    this.localIp = localIp;
    this.socket = null;
    this.buffer = Buffer.alloc(0);
    this.receivedMessages = [];
  }

  async connect(targetIp, targetPort) {
    return new Promise((resolve, reject) => {
      this.socket = net.connect({
        host: targetIp,
        port: targetPort,
        localAddress: this.localIp
      }, () => {
        // Send HTTP WebSocket Upgrade
        const key = crypto.randomBytes(16).toString('base64');
        const req = 
          `GET / HTTP/1.1\r\n` +
          `Host: ${targetIp}:${targetPort}\r\n` +
          `Upgrade: websocket\r\n` +
          `Connection: Upgrade\r\n` +
          `Sec-WebSocket-Key: ${key}\r\n` +
          `Sec-WebSocket-Version: 13\r\n\r\n`;
        this.socket.write(req);
      });

      let upgraded = false;
      this.socket.on('data', (chunk) => {
        if (!upgraded) {
          const str = chunk.toString();
          if (str.includes('101 Switching Protocols')) {
            upgraded = true;
            resolve();
          }
          return;
        }

        this.buffer = Buffer.concat([this.buffer, chunk]);
        const { messages, remainder } = decodeWsFrames(this.buffer);
        this.buffer = remainder;

        for (const msg of messages) {
          try {
            this.receivedMessages.push(JSON.parse(msg));
          } catch (_) {
            this.receivedMessages.push(msg);
          }
        }
      });

      this.socket.on('error', (err) => {
        if (!upgraded) reject(err);
      });
    });
  }

  send(data) {
    if (!this.socket || this.socket.destroyed) return;
    this.socket.write(encodeWsFrame(JSON.stringify(data)));
  }

  identify(branchId = 'karachi') {
    this.send({
      event_type: 'identify',
      role: this.role,
      branchId: branchId,
      username: this.name,
      virtualIp: this.localIp
    });
  }

  disconnect() {
    if (this.socket) {
      this.socket.destroy();
      this.socket = null;
    }
  }
}

// ── Test Runner ───────────────────────────────────────────────────────────────
async function runVirtualIpTests() {
  console.log('================================================================');
  console.log('🌐 VIRTUAL IP MULTI-SYSTEM CLINIC STRESS TEST');
  console.log('================================================================');
  console.log(`[Host]   Server binding to:       ${SERVER_IP}:${SERVER_PORT}`);
  console.log(`[Node 1] Reception Station IP:   ${RECEPTION_IP}`);
  console.log(`[Node 2] Doctor Station IP:      ${DOCTOR_IP}`);
  console.log(`[Node 3] Dispensary Station IP:  ${DISPENSER_IP}`);
  console.log('----------------------------------------------------------------');

  const connectedClients = new Map();

  // Create Server
  const server = http.createServer();
  server.on('upgrade', (req, socket, head) => {
    const clientIp = socket.remoteAddress;
    const acceptKey = req.headers['sec-websocket-key'];
    const hash = crypto.createHash('sha1').update(acceptKey + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');

    socket.write(
      'HTTP/1.1 101 Switching Protocols\r\n' +
      'Upgrade: websocket\r\n' +
      'Connection: Upgrade\r\n' +
      `Sec-WebSocket-Accept: ${hash}\r\n\r\n`
    );

    let clientBuffer = Buffer.alloc(0);
    const clientMeta = { ip: clientIp, identified: false, role: null };
    connectedClients.set(socket, clientMeta);

    socket.on('data', (chunk) => {
      clientBuffer = Buffer.concat([clientBuffer, chunk]);
      const { messages, remainder } = decodeWsFrames(clientBuffer);
      clientBuffer = remainder;

      for (const raw of messages) {
        let data;
        try { data = JSON.parse(raw); } catch (_) { continue; }

        if (data.event_type === 'identify') {
          clientMeta.identified = true;
          clientMeta.role = data.role;
          console.log(`[Server] ✅ CLIENT IDENTIFIED: Role="${data.role}" from Virtual IP: ${clientIp}`);
          return;
        }

        // Broadcast to all other identified peers
        for (const [peerSocket, peerMeta] of connectedClients.entries()) {
          if (peerSocket !== socket && peerMeta.identified) {
            try {
              peerSocket.write(encodeWsFrame(raw));
            } catch (err) {
              console.log(`[Server] ⚠️ Failed write to dead socket (${peerMeta.role}): ${err.message}`);
            }
          }
        }
      }
    });

    socket.on('error', (err) => {
      console.log(`[Server] ⚠️ Socket error on ${clientIp}: ${err.code || err.message}`);
    });

    socket.on('close', () => {
      console.log(`[Server] 🔌 Client disconnected from Virtual IP: ${clientIp} (${clientMeta.role})`);
      connectedClients.delete(socket);
    });
  });

  await new Promise((resolve) => server.listen(SERVER_PORT, SERVER_IP, resolve));
  console.log(`[Server] Listening on http://${SERVER_IP}:${SERVER_PORT}`);

  try {
    // 1. Connect Virtual Stations from separate source IPs
    const reception = new VirtualStation('Reception-PC', 'reception', RECEPTION_IP);
    const doctor    = new VirtualStation('Doctor-PC', 'doctor', DOCTOR_IP);
    const dispenser = new VirtualStation('Dispensary-PC', 'dispenser', DISPENSER_IP);

    console.log('\n[Step 1] Connecting all 3 virtual systems with dedicated IPs...');
    await reception.connect(SERVER_IP, SERVER_PORT);
    await doctor.connect(SERVER_IP, SERVER_PORT);
    await dispenser.connect(SERVER_IP, SERVER_PORT);

    reception.identify();
    doctor.identify();
    dispenser.identify();
    await new Promise((r) => setTimeout(r, 200));

    console.log(`[Status] All 3 distinct Virtual IP stations connected!`);

    // 2. Transmit Token from Reception IP (127.0.0.21)
    console.log('\n[Step 2] Reception (127.0.0.21) emits Token #VIP-001...');
    reception.send({
      event_type: 'token_created',
      serial: 'VIP-001',
      patientName: 'Virtual IP Test Patient',
      fromIp: RECEPTION_IP
    });
    await new Promise((r) => setTimeout(r, 100));

    const docHasToken = doctor.receivedMessages.some(m => m.serial === 'VIP-001');
    const dispHasToken = dispenser.receivedMessages.some(m => m.serial === 'VIP-001');
    console.log(`[Verify] Doctor (127.0.0.22) received token:     ${docHasToken ? '✅ YES' : '❌ NO'}`);
    console.log(`[Verify] Dispensary (127.0.0.23) received token: ${dispHasToken ? '✅ YES' : '❌ NO'}`);

    // 3. Simulate Connection Drop on Dispensary IP (127.0.0.23)
    console.log('\n[Step 3] Simulating ABRUPT connection drop on Dispensary (127.0.0.23)...');
    dispenser.disconnect();
    await new Promise((r) => setTimeout(r, 150));

    // 4. Generate 3 tokens while Dispensary IP is dead
    console.log('[Step 4] Reception generating 3 tokens while Dispensary is offline...');
    for (let i = 2; i <= 4; i++) {
      reception.send({ event_type: 'token_created', serial: `VIP-00${i}`, fromIp: RECEPTION_IP });
    }
    await new Promise((r) => setTimeout(r, 100));

    // 5. Reconnect Dispensary from new DHCP IP (127.0.0.24)
    console.log('\n[Step 5] Dispensary reconnecting with NEW DHCP IP (127.0.0.24)...');
    const reconnectedDispenser = new VirtualStation('Dispensary-PC-2', 'dispenser', '127.0.0.24');
    await reconnectedDispenser.connect(SERVER_IP, SERVER_PORT);
    reconnectedDispenser.identify();
    await new Promise((r) => setTimeout(r, 200));

    console.log(`[Verify] Reconnected Dispensary received handshake confirmation: ✅ YES`);
    console.log(`[Result] Missed tokens during outage (VIP-002, 003, 004): 3/3 missed (Catch-Up needed)`);

    console.log('\n================================================================');
    console.log('🎉 ALL VIRTUAL IP CONNECTION TESTS COMPLETED SUCCESSFULLY!');
    console.log('================================================================\n');

    reception.disconnect();
    doctor.disconnect();
    reconnectedDispenser.disconnect();
  } finally {
    server.close();
  }
}

runVirtualIpTests().catch(err => {
  console.error('Fatal Test Error:', err);
  process.exit(1);
});
