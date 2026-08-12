// Windows classic Bluetooth (RFCOMM) bridge for DotChat.
// Mirrors the Android BluetoothService.kt protocol so the same Dart
// BluetoothService works on both PC and phone.
#include "bt_windows.h"

#include <bluetoothapis.h>
#include <ws2bth.h>

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <wchar.h>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "Bthprops.lib")

namespace luoda {

namespace {

// Same SPP UUID as the Android side (e18b0f2c-1f2a-4f8e-9c5a-6b7f1a2b3c4d).
constexpr GUID kAppUuid = {0xe18b0f2c, 0x1f2a, 0x4f8e,
                           {0x9c, 0x5a, 0x6b, 0x7f, 0x1a, 0x2b, 0x3c, 0x4d}};
constexpr int kMaxLine = 64 * 1024;

std::string WideToUtf8(const std::wstring& w) {
  if (w.empty()) return "";
  int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()),
                              nullptr, 0, nullptr, nullptr);
  if (n <= 0) return "";
  std::string out(static_cast<size_t>(n), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()), &out[0],
                      n, nullptr, nullptr);
  return out;
}

// BLUETOOTH_ADDRESS.ullLong: rgBytes[5] is the most significant octet and is
// displayed first ("AA:BB:CC:DD:EE:FF"). Same numeric value is used by
// SOCKADDR_BTH.btAddr.
std::string FormatMac(ULONGLONG addr) {
  char buf[32];
  snprintf(buf, sizeof(buf), "%02X:%02X:%02X:%02X:%02X:%02X",
           static_cast<unsigned>((addr >> 40) & 0xFF),
           static_cast<unsigned>((addr >> 32) & 0xFF),
           static_cast<unsigned>((addr >> 24) & 0xFF),
           static_cast<unsigned>((addr >> 16) & 0xFF),
           static_cast<unsigned>((addr >> 8) & 0xFF),
           static_cast<unsigned>(addr & 0xFF));
  return buf;
}

// Parse "AA:BB:CC:DD:EE:FF" (colons optional) into a BTH_ADDR.
BTH_ADDR ParseMac(const std::string& s) {
  unsigned b[6] = {0, 0, 0, 0, 0, 0};
  int n = sscanf_s(s.c_str(), "%2x:%2x:%2x:%2x:%2x:%2x", &b[0], &b[1], &b[2],
                 &b[3], &b[4], &b[5]);
  if (n != 6) {
    // Retry without colons.
    n = sscanf_s(s.c_str(), "%2x%2x%2x%2x%2x%2x", &b[0], &b[1], &b[2], &b[3],
               &b[4], &b[5]);
    if (n != 6) return 0;
  }
  return (static_cast<BTH_ADDR>(b[0]) << 40) |
         (static_cast<BTH_ADDR>(b[1]) << 32) |
         (static_cast<BTH_ADDR>(b[2]) << 24) |
         (static_cast<BTH_ADDR>(b[3]) << 16) |
         (static_cast<BTH_ADDR>(b[4]) << 8) | static_cast<BTH_ADDR>(b[5]);
}

bool FindFirstRadio(BLUETOOTH_RADIO_INFO* out, HBLUETOOTH_RADIO_FIND* handle,
                    HANDLE* radioHandle) {
  BLUETOOTH_FIND_RADIO_PARAMS params = {sizeof(params)};
  HANDLE h = nullptr;
  HBLUETOOTH_RADIO_FIND find =
      BluetoothFindFirstRadio(&params, &h);
  if (find == nullptr) return false;
  BLUETOOTH_RADIO_INFO info = {sizeof(info)};
  if (BluetoothGetRadioInfo(h, &info) == ERROR_SUCCESS) {
    *out = info;
    *handle = find;
    *radioHandle = h;
    return true;
  }
  BluetoothFindRadioClose(find);
  CloseHandle(h);
  return false;
}

std::string SocketMac(SOCKET s) {
  SOCKADDR_BTH remote{};
  int len = sizeof(remote);
  if (getpeername(s, reinterpret_cast<sockaddr*>(&remote), &len) != 0) {
    return "";
  }
  return FormatMac(remote.btAddr);
}

}  // namespace

BtWindows& BtWindows::instance() {
  static BtWindows inst;
  return inst;
}

void BtWindows::Init(flutter::BinaryMessenger* messenger, HWND hwnd) {
  if (hwnd_) return;
  hwnd_ = hwnd;

  WSADATA wsa{};
  WSAStartup(MAKEWORD(2, 2), &wsa);

  auto method_handler = [this](const flutter::MethodCall<>& call,
                               std::unique_ptr<flutter::MethodResult<>> result) {
    const std::string& method = call.method_name();
    if (method == "isSupported") {
      result->Success(flutter::EncodableValue(IsSupported()));
    } else if (method == "isEnabled") {
      result->Success(flutter::EncodableValue(IsEnabled()));
    } else if (method == "enable") {
      // Windows cannot programmatically switch the radio; the user must use
      // the system Settings. The Dart UI treats this as a no-op.
      result->Success();
    } else if (method == "pairedDevices") {
      result->Success(flutter::EncodableValue(PairedDevices()));
    } else if (method == "startScan") {
      StartScan();
      result->Success();
    } else if (method == "stopScan") {
      StopScan();
      result->Success();
    } else if (method == "connect") {
      std::string mac;
      std::string name;
      if (call.arguments() &&
          std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
        const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
        auto it = args.find(flutter::EncodableValue("mac"));
        if (it != args.end() &&
            std::holds_alternative<std::string>(it->second)) {
          mac = std::get<std::string>(it->second);
        }
        it = args.find(flutter::EncodableValue("name"));
        if (it != args.end() &&
            std::holds_alternative<std::string>(it->second)) {
          name = std::get<std::string>(it->second);
        }
      }
      if (mac.empty()) {
        result->Error("bad_args", "mac required", nullptr);
      } else {
        Connect(mac, name);
        result->Success();
      }
    } else if (method == "disconnect") {
      if (call.arguments() &&
          std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
        const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
        auto it = args.find(flutter::EncodableValue("mac"));
        if (it != args.end() &&
            std::holds_alternative<std::string>(it->second)) {
          Disconnect(std::get<std::string>(it->second));
        }
      }
      result->Success();
    } else if (method == "sendEnvelope") {
      std::string mac;
      std::string envelope;
      if (call.arguments() &&
          std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
        const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
        auto it = args.find(flutter::EncodableValue("mac"));
        if (it != args.end() &&
            std::holds_alternative<std::string>(it->second)) {
          mac = std::get<std::string>(it->second);
        }
        it = args.find(flutter::EncodableValue("envelope"));
        if (it != args.end() &&
            std::holds_alternative<std::string>(it->second)) {
          envelope = std::get<std::string>(it->second);
        }
      }
      SendEnvelope(mac, envelope);
      result->Success();
    } else if (method == "startListening") {
      StartListening();
      result->Success();
    } else {
      result->NotImplemented();
    }
  };
  method_channel_ = std::make_unique<flutter::MethodChannel<>>(
      messenger, "bluetooth_channel", &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler(method_handler);

  event_channel_ = std::make_unique<flutter::EventChannel<>>(
      messenger, "bluetooth_channel_events",
      &flutter::StandardMethodCodec::GetInstance());
  event_channel_->SetStreamHandler(std::make_unique<flutter::StreamHandlerFunctions<>>(
      [this](const flutter::EncodableValue* /*arguments*/,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        {
          std::lock_guard<std::mutex> lock(sink_mutex_);
          sink_ = std::move(events);
        }
        return nullptr;
      },
      [this](const flutter::EncodableValue* /*arguments*/)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        std::lock_guard<std::mutex> lock(sink_mutex_);
        sink_.reset();
        return nullptr;
      }));
}

void BtWindows::Shutdown() {
  if (!hwnd_) return;
  running_ = false;
  scanning_ = false;

  // Close the listen socket to unblock accept().
  SOCKET listen = listen_socket_.exchange(INVALID_SOCKET);
  if (listen != INVALID_SOCKET) {
    closesocket(listen);
  }
  if (listen_thread_.joinable()) listen_thread_.join();

  // Close all active connections to unblock reader threads.
  {
    std::lock_guard<std::mutex> lock(conn_mutex_);
    for (auto& [mac, socket] : sockets_) {
      closesocket(socket);
    }
    sockets_.clear();
    mac_by_socket_.clear();
  }

  method_channel_.reset();
  event_channel_.reset();
  WSACleanup();
}

void BtWindows::DeliverEvent(flutter::EncodableMap* payload) {
  if (!payload) return;
  std::unique_ptr<flutter::EncodableMap> guard(payload);
  std::lock_guard<std::mutex> lock(sink_mutex_);
  if (sink_) {
    sink_->Success(flutter::EncodableValue(*guard));
  }
}

void BtWindows::EmitEvent(flutter::EncodableMap payload) {
  if (!hwnd_) return;
  auto* ptr = new flutter::EncodableMap(std::move(payload));
  if (!PostMessage(hwnd_, kLuodaBtEventMessage, 0,
                   reinterpret_cast<LPARAM>(ptr))) {
    delete ptr;
  }
}

void BtWindows::EmitError(const std::string& message) {
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("event")] = flutter::EncodableValue("error");
  payload[flutter::EncodableValue("message")] = flutter::EncodableValue(message);
  EmitEvent(std::move(payload));
}

bool BtWindows::IsSupported() {
  BLUETOOTH_RADIO_INFO info{};
  HBLUETOOTH_RADIO_FIND handle = nullptr;
  HANDLE radio = nullptr;
  if (!FindFirstRadio(&info, &handle, &radio)) return false;
  BluetoothFindRadioClose(handle);
  CloseHandle(radio);
  return true;
}

bool BtWindows::IsEnabled() {
  BLUETOOTH_RADIO_INFO info{};
  HBLUETOOTH_RADIO_FIND handle = nullptr;
  HANDLE radio = nullptr;
  if (!FindFirstRadio(&info, &handle, &radio)) return false;
  // Keep incoming connections enabled for the RFCOMM server. Its return value
  // reports the *previous* incoming-connection state (and is FALSE once the
  // state is already enabled), so it cannot be used to detect "radio off".
  BluetoothEnableIncomingConnections(radio, TRUE);
  bool connectable = BluetoothIsConnectable(radio) != FALSE;
  BluetoothFindRadioClose(handle);
  CloseHandle(radio);
  return connectable;
}

flutter::EncodableList BtWindows::PairedDevices() {
  flutter::EncodableList out;
  BLUETOOTH_DEVICE_SEARCH_PARAMS search{};
  search.dwSize = sizeof(search);
  search.fReturnAuthenticated = TRUE;
  search.fReturnRemembered = TRUE;
  search.fReturnConnected = TRUE;
  search.fReturnUnknown = FALSE;
  search.fIssueInquiry = FALSE;
  search.cTimeoutMultiplier = 0;

  BLUETOOTH_DEVICE_INFO device{};
  device.dwSize = sizeof(device);
  HBLUETOOTH_DEVICE_FIND find = BluetoothFindFirstDevice(&search, &device);
  if (find == nullptr) return out;
  do {
    flutter::EncodableMap item;
    item[flutter::EncodableValue("name")] =
        flutter::EncodableValue(WideToUtf8(device.szName));
    item[flutter::EncodableValue("mac")] =
        flutter::EncodableValue(FormatMac(device.Address.ullLong));
    item[flutter::EncodableValue("paired")] = flutter::EncodableValue(true);
    out.emplace_back(std::move(item));
  } while (BluetoothFindNextDevice(find, &device) == ERROR_SUCCESS);
  BluetoothFindDeviceClose(find);
  return out;
}

void BtWindows::StartScan() {
  if (scanning_.exchange(true)) return;
  if (scan_thread_.joinable()) scan_thread_.join();
  scan_thread_ = std::thread(&BtWindows::ScanWorker, this);
}

void BtWindows::StopScan() {
  scanning_ = false;
}

void BtWindows::ScanWorker() {
  bool ok = false;
  BLUETOOTH_DEVICE_SEARCH_PARAMS search{};
  search.dwSize = sizeof(search);
  search.fReturnAuthenticated = TRUE;
  search.fReturnRemembered = TRUE;
  search.fReturnConnected = TRUE;
  search.fReturnUnknown = TRUE;  // triggers an inquiry for nearby devices
  search.fIssueInquiry = TRUE;
  search.cTimeoutMultiplier = 3;  // ~3 * 1.28s inquiry window

  BLUETOOTH_DEVICE_INFO device{};
  device.dwSize = sizeof(device);
  HBLUETOOTH_DEVICE_FIND find = BluetoothFindFirstDevice(&search, &device);
  if (find == nullptr) {
    int err = GetLastError();
    if (err == ERROR_NO_MORE_ITEMS) {
      ok = true;
    } else {
      char msg[128];
      snprintf(msg, sizeof(msg), "Bluetooth scan failed: %d", err);
      EmitError(msg);
    }
    scanning_ = false;
    return;
  }
  do {
    if (!scanning_) break;
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("event")] =
        flutter::EncodableValue("deviceFound");
    payload[flutter::EncodableValue("name")] =
        flutter::EncodableValue(WideToUtf8(device.szName));
    payload[flutter::EncodableValue("mac")] =
        flutter::EncodableValue(FormatMac(device.Address.ullLong));
    payload[flutter::EncodableValue("paired")] =
        flutter::EncodableValue(device.fAuthenticated == TRUE ||
                                device.fRemembered == TRUE);
    EmitEvent(std::move(payload));
    Sleep(250);
  } while (BluetoothFindNextDevice(find, &device) == ERROR_SUCCESS &&
           scanning_);
  BluetoothFindDeviceClose(find);
  scanning_ = false;
}

void BtWindows::Connect(const std::string& mac, const std::string& /*name*/) {
  std::thread([this, mac]() {
    BTH_ADDR addr = ParseMac(mac);
    if (addr == 0) {
      EmitError("Invalid Bluetooth address: " + mac);
      return;
    }
    SOCKET s = socket(AF_BTH, SOCK_STREAM, BTHPROTO_RFCOMM);
    if (s == INVALID_SOCKET) {
      EmitError("Bluetooth socket failed");
      return;
    }
    SOCKADDR_BTH target{};
    target.addressFamily = AF_BTH;
    target.serviceClassId = kAppUuid;
    target.btAddr = addr;
    target.port = BT_PORT_ANY;  // resolved via SDP using serviceClassId
    if (connect(s, reinterpret_cast<sockaddr*>(&target), sizeof(target)) != 0) {
      int err = WSAGetLastError();
      closesocket(s);
      char msg[160];
      snprintf(msg, sizeof(msg), "Bluetooth connect failed: %d", err);
      EmitError(msg);
      return;
    }
    std::string remote = SocketMac(s);
    if (remote.empty()) remote = FormatMac(addr);
    AddConnection(remote, s);

    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("event")] =
        flutter::EncodableValue("connected");
    payload[flutter::EncodableValue("mac")] =
        flutter::EncodableValue(remote);
    payload[flutter::EncodableValue("name")] = flutter::EncodableValue("");
    EmitEvent(std::move(payload));

    std::thread(&BtWindows::ReaderWorker, this, remote, s).detach();
  }).detach();
}

void BtWindows::Disconnect(const std::string& mac) {
  std::lock_guard<std::mutex> lock(conn_mutex_);
  auto it = sockets_.find(mac);
  if (it == sockets_.end()) return;
  closesocket(it->second);
  sockets_.erase(it);
  for (auto mit = mac_by_socket_.begin(); mit != mac_by_socket_.end(); ++mit) {
    if (mit->second == mac) {
      mac_by_socket_.erase(mit);
      break;
    }
  }
}

void BtWindows::SendEnvelope(const std::string& mac,
                             const std::string& envelope) {
  if (mac.empty() || envelope.empty()) return;
  SOCKET s = INVALID_SOCKET;
  {
    std::lock_guard<std::mutex> lock(conn_mutex_);
    auto it = sockets_.find(mac);
    if (it == sockets_.end()) return;
    s = it->second;
  }
  std::string line = envelope + "\r\n";
  size_t sent = 0;
  while (sent < line.size()) {
    int n = send(s, line.data() + sent,
                 static_cast<int>(line.size() - sent), 0);
    if (n <= 0) {
      std::thread(&BtWindows::ReaderWorker, this, mac, s).detach();
      return;
    }
    sent += static_cast<size_t>(n);
  }
}

void BtWindows::StartListening() {
  if (running_.exchange(true)) return;
  if (listen_thread_.joinable()) listen_thread_.join();
  listen_thread_ = std::thread(&BtWindows::ListenWorker, this);
}

void BtWindows::ListenWorker() {
  SOCKET s = socket(AF_BTH, SOCK_STREAM, BTHPROTO_RFCOMM);
  if (s == INVALID_SOCKET) {
    running_ = false;
    EmitError("Bluetooth server socket failed");
    return;
  }
  SOCKADDR_BTH local{};
  local.addressFamily = AF_BTH;
  local.serviceClassId = kAppUuid;
  local.port = BT_PORT_ANY;
  if (bind(s, reinterpret_cast<sockaddr*>(&local), sizeof(local)) != 0 ||
      listen(s, 4) != 0) {
    int err = WSAGetLastError();
    closesocket(s);
    running_ = false;
    char msg[160];
    snprintf(msg, sizeof(msg), "Bluetooth server bind failed: %d", err);
    EmitError(msg);
    return;
  }
  listen_socket_ = s;
  while (running_) {
    SOCKET client = accept(s, nullptr, nullptr);
    if (client == INVALID_SOCKET) break;  // socket closed on shutdown
    std::string remote = SocketMac(client);
    if (remote.empty()) {
      closesocket(client);
      continue;
    }
    AddConnection(remote, client);

    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("event")] =
        flutter::EncodableValue("connected");
    payload[flutter::EncodableValue("mac")] =
        flutter::EncodableValue(remote);
    payload[flutter::EncodableValue("name")] = flutter::EncodableValue("");
    EmitEvent(std::move(payload));

    std::thread(&BtWindows::ReaderWorker, this, remote, client).detach();
  }
  listen_socket_ = INVALID_SOCKET;
  closesocket(s);
  running_ = false;
}

void BtWindows::AddConnection(const std::string& mac, SOCKET socket) {
  std::lock_guard<std::mutex> lock(conn_mutex_);
  auto it = sockets_.find(mac);
  if (it != sockets_.end()) closesocket(it->second);
  sockets_[mac] = socket;
  mac_by_socket_[socket] = mac;
}

void BtWindows::RemoveConnection(const std::string& mac) {
  std::lock_guard<std::mutex> lock(conn_mutex_);
  auto it = sockets_.find(mac);
  if (it == sockets_.end()) return;
  closesocket(it->second);
  sockets_.erase(it);
  for (auto mit = mac_by_socket_.begin(); mit != mac_by_socket_.end(); ++mit) {
    if (mit->second == mac) {
      mac_by_socket_.erase(mit);
      break;
    }
  }
}

void BtWindows::ReaderWorker(const std::string& mac, SOCKET socket) {
  std::string buffer;
  buffer.reserve(4096);
  char chunk[2048];
  for (;;) {
    int n = recv(socket, chunk, sizeof(chunk), 0);
    if (n <= 0) break;
    buffer.append(chunk, static_cast<size_t>(n));
    for (;;) {
      size_t nl = buffer.find('\n');
      if (nl == std::string::npos) break;
      std::string line = buffer.substr(0, nl);
      buffer.erase(0, nl + 1);
      if (!line.empty() && line.back() == '\r') line.pop_back();
      if (line.empty()) continue;

      flutter::EncodableMap payload;
      payload[flutter::EncodableValue("event")] =
          flutter::EncodableValue("wire");
      payload[flutter::EncodableValue("mac")] =
          flutter::EncodableValue(mac);
      payload[flutter::EncodableValue("envelope")] =
          flutter::EncodableValue(line);
      EmitEvent(std::move(payload));
      if (buffer.size() > static_cast<size_t>(kMaxLine)) buffer.clear();
    }
  }
  RemoveConnection(mac);
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("event")] =
      flutter::EncodableValue("disconnected");
  payload[flutter::EncodableValue("mac")] = flutter::EncodableValue(mac);
  EmitEvent(std::move(payload));
}

}  // namespace luoda
