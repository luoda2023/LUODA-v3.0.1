// Windows classic Bluetooth (RFCOMM) bridge for DotChat.
// Mirrors the Android BluetoothService.kt protocol so the same Dart
// BluetoothService works on both PC and phone.
#pragma once

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

// Must come before any <windows.h> so winsock.h is not pulled in (winsock2
// would otherwise conflict). Included first in flutter_window.cpp too.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <windows.h>

namespace luoda {

constexpr UINT kLuodaBtEventMessage = WM_APP + 101;

class BtWindows {
 public:
  static BtWindows& instance();

  void Init(flutter::BinaryMessenger* messenger, HWND hwnd);
  void Shutdown();

  // Called on the UI thread (from the custom window message) to deliver an
  // event payload allocated on a worker thread.
  void DeliverEvent(flutter::EncodableMap* payload);

 private:
  BtWindows() = default;
  ~BtWindows() = default;

  void EmitEvent(flutter::EncodableMap payload);
  void EmitError(const std::string& message);

  // Native Bluetooth operations.
  bool IsSupported();
  bool IsEnabled();
  flutter::EncodableList PairedDevices();
  void StartScan();
  void StopScan();
  void SetLocalName(const std::string& name);
  void Connect(const std::string& mac, const std::string& name);
  void Disconnect(const std::string& mac);
  void SendEnvelope(const std::string& mac, const std::string& envelope);
  void StartListening();

  void ScanWorker();
  void ListenWorker();
  void ReaderWorker(const std::string& mac, SOCKET socket);
  void AddConnection(const std::string& mac, SOCKET socket);
  void RemoveConnection(const std::string& mac);

  HWND hwnd_ = nullptr;
  std::mutex sink_mutex_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;

  std::unique_ptr<flutter::MethodChannel<>> method_channel_;
  std::unique_ptr<flutter::EventChannel<>> event_channel_;

  std::mutex conn_mutex_;
  std::map<std::string, SOCKET> sockets_;
  std::map<SOCKET, std::string> mac_by_socket_;

  std::atomic<bool> running_{false};
  std::atomic<bool> scanning_{false};
  std::thread scan_thread_;
  std::thread listen_thread_;
  std::atomic<SOCKET> listen_socket_{INVALID_SOCKET};
};

}  // namespace luoda
