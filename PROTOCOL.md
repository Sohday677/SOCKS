# SOCKS5 Protocol Implementation

## Protocol Details

This SOCKS5 server implementation now supports both TCP and UDP protocols as defined in RFC 1928.

### Answer to: "does it use UDP ASSOCIATE or just UDP or is it TCP online?"

**Previously:** The server only supported **TCP** connections using the SOCKS5 CONNECT command (0x01).

**Now:** The server supports **both TCP and UDP**:
- **TCP via CONNECT command (0x01)**: For standard TCP proxy connections
- **UDP via UDP ASSOCIATE command (0x03)**: For UDP relay functionality

## How It Works

### TCP Support (CONNECT)
1. Client connects to the SOCKS5 server on the TCP control port (default: 4884)
2. Client sends CONNECT request with destination address
3. Server establishes TCP connection to the target
4. Server relays data bidirectionally between client and target

### UDP Support (UDP ASSOCIATE)
1. Client connects to the SOCKS5 server on the TCP control port (default: 4884)
2. Client sends UDP ASSOCIATE request
3. Server responds with UDP relay address and port (default: 4885)
4. Client sends UDP packets to the relay port, encapsulated in SOCKS5 UDP format
5. Server extracts and forwards UDP packets to the actual destination
6. Server receives responses and relays them back to the client
7. TCP control connection remains open during the UDP session

## Supported Commands

| Command | Code | Description | Status |
|---------|------|-------------|--------|
| CONNECT | 0x01 | TCP connection | ✅ Supported |
| BIND | 0x02 | TCP listening | ❌ Not supported |
| UDP ASSOCIATE | 0x03 | UDP relay | ✅ Supported |

## Port Configuration

- **TCP Control Port**: 4884 (configurable via UI)
- **UDP Relay Port**: 4885 (automatically configured, TCP port + 1)

## Use Cases

### TCP (CONNECT) is ideal for:
- Web browsing (HTTP/HTTPS)
- Email protocols (SMTP, IMAP, POP3)
- SSH connections
- FTP transfers
- Any TCP-based application

### UDP (UDP ASSOCIATE) is ideal for:
- DNS queries
- Online gaming
- VoIP applications (Skype, Discord, Zoom)
- Video streaming (some protocols)
- P2P applications
- Any latency-sensitive UDP traffic

## Technical Implementation

The implementation uses Apple's Network.framework:
- `NWListener` with `NWParameters.tcp` for TCP control connections
- `NWListener` with `NWParameters.udp` for UDP relay
- Proper SOCKS5 UDP packet encapsulation/decapsulation
- Thread-safe data tracking with separate dispatch queues for TCP and UDP

## Limitations

- UDP fragmentation (FRAG field) is not supported; only non-fragmented packets (FRAG=0x00)
- BIND command is not implemented
- Authentication methods beyond "no authentication" are not supported
