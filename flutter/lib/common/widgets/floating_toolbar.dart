import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../../consts.dart';
import 'dialog.dart';
import '../../models/input_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';

/// A floating, draggable, expandable toolbar for the mobile remote-control page.
///
/// Collapsed state shows a single round FAB with the app icon. Tapping it
/// expands into a horizontal card of action buttons (Back / Home / Recent /
/// Volume / Power / Keyboard / Exit for Android peers; Keyboard / Display /
/// Chat / Exit for desktop peers). Auto-fades to 30% opacity after 3 s of
/// inactivity; any touch restores full opacity.
class FloatingToolbar extends StatefulWidget {
 const FloatingToolbar({
 Key? key,
 required this.ffi,
 required this.onHide,
 this.onOpenKeyboard,
 this.onOpenDisplay,
 this.onOpenChat,
 }) : super(key: key);

 final FFI ffi;
 final VoidCallback onHide;
 final VoidCallback? onOpenKeyboard;
 final VoidCallback? onOpenDisplay;
 final VoidCallback? onOpenChat;

 @override
 _FloatingToolbarState createState() => _FloatingToolbarState();
}

class _FloatingToolbarState extends State<FloatingToolbar> {
 bool _expanded = false;
 double _opacity = 1.0;
 Timer? _autoHideTimer;
 Offset _position = Offset.zero;

 static const String _kPositionKey = 'floating_toolbar_position';
 static const Duration _kAutoHideDelay = Duration(seconds: 3);
 static const double _kFabSize = 48.0;
 static const double _kButtonSize = 40.0;
 static const double _kButtonSpacing = 4.0;

 InputModel get inputModel => widget.ffi.inputModel;
 bool get isPeerAndroid => widget.ffi.ffiModel.isPeerAndroid;
 bool get keyboardEnabled =>
 !widget.ffi.ffiModel.viewOnly && widget.ffi.ffiModel.keyboard;

 @override
 void initState() {
 super.initState();
 _loadPosition();
 _resetAutoHideTimer();
 }

 @override
 void dispose() {
 _autoHideTimer?.cancel();
 super.dispose();
 }

 void _loadPosition() {
 final saved = bind.getLocalFlutterOption(k: _kPositionKey);
 if (saved.isNotEmpty) {
 final parts = saved.split(',');
 if (parts.length == 2) {
 final x = double.tryParse(parts[0]);
 final y = double.tryParse(parts[1]);
 if (x != null && y != null) {
 _position = Offset(x, y);
 }
 }
 }
 }

 void _savePosition(Offset pos) {
 bind.setLocalFlutterOption(
 k: _kPositionKey, v: '${pos.dx},${pos.dy}');
 }

 void _resetAutoHideTimer() {
 _autoHideTimer?.cancel();
 _autoHideTimer = Timer(_kAutoHideDelay, () {
 if (mounted) {
 setState(() => _opacity = 0.3);
 }
 });
 }

 void _onUserInteraction() {
 setState(() => _opacity = 1.0);
 _resetAutoHideTimer();
 }

 Offset _defaultPosition(Size screenSize) {
 // Bottom-right with padding, above the safe area.
 return Offset(
 screenSize.width - _kFabSize - 16,
 screenSize.height - _kFabSize - 80,
 );
 }

 @override
 Widget build(BuildContext context) {
 final screenSize = MediaQuery.of(context).size;
 if (_position == Offset.zero) {
 _position = _defaultPosition(screenSize);
 }

 final children = _buildButtons();

 return Positioned(
 left: _position.dx,
 top: _position.dy,
 child: AnimatedOpacity(
 opacity: _opacity,
 duration: const Duration(milliseconds: 300),
 child: GestureDetector(
 onPanUpdate: (details) {
 setState(() {
 _position += details.delta;
 // Clamp to screen bounds.
 final w = _expanded
 ? (_kButtonSize + _kButtonSpacing) * children.length + 16
 : _kFabSize;
 final h = _expanded ? _kButtonSize + 16 : _kFabSize;
 _position = Offset(
 _position.dx.clamp(0.0, screenSize.width - w),
 _position.dy.clamp(0.0, screenSize.height - h),
 );
 });
 _savePosition(_position);
 _onUserInteraction();
 },
 child: _expanded
 ? _buildExpandedCard(children)
 : _buildCollapsedFab(),
 ),
 ),
 );
 }

 Widget _buildCollapsedFab() {
 return GestureDetector(
 onTap: () {
 setState(() => _expanded = true);
 _onUserInteraction();
 },
 child: Container(
 width: _kFabSize,
 height: _kFabSize,
 decoration: BoxDecoration(
 color: MyTheme.accent.withOpacity(0.85),
 shape: BoxShape.circle,
 boxShadow: [
 BoxShadow(
 color: Colors.black.withOpacity(0.3),
 blurRadius: 6,
 offset: const Offset(0, 2),
 ),
 ],
 ),
 child: Center(
 child: SvgPicture.asset(
 'assets/icon.svg',
 width: 24,
 height: 24,
 colorFilter: const ColorFilter.mode(
 Colors.white,
 BlendMode.srcIn,
 ),
 ),
 ),
 ),
 );
 }

 Widget _buildExpandedCard(List<Widget> children) {
 return Container(
 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
 decoration: BoxDecoration(
 color: const Color(0xFF20252E).withOpacity(0.92),
 borderRadius: BorderRadius.circular(16),
 boxShadow: [
 BoxShadow(
 color: Colors.black.withOpacity(0.3),
 blurRadius: 8,
 offset: const Offset(0, 2),
 ),
 ],
 ),
 child: Row(
 mainAxisSize: MainAxisSize.min,
 children: [
 ...children,
 // Collapse button
 Container(
 width: 1,
 height: 24,
 margin: const EdgeInsets.only(left: 4),
 color: Colors.white.withOpacity(0.16),
 ),
 _buildButton(
 icon: Icons.expand_more_rounded,
 color: Colors.white,
 onPressed: () {
 setState(() => _expanded = false);
 _onUserInteraction();
 },
 ),
 ],
 ),
 );
 }

 List<Widget> _buildButtons() {
 if (isPeerAndroid && keyboardEnabled) {
 return _buildAndroidButtons();
 } else if (isPeerAndroid) {
 // Android peer but no keyboard permission — still show navigation.
 return _buildAndroidNavButtons();
 } else {
 return _buildDesktopButtons();
 }
 }

 List<Widget> _buildAndroidButtons() {
 return [
 _buildButton(
 icon: Icons.arrow_back_rounded,
 tooltip: 'Back',
 onPressed: () {
 inputModel.onMobileBack();
 _onUserInteraction();
 },
 ),
 _buildButton(
 icon: Icons.home_rounded,
 tooltip: 'Home',
 onPressed: () {
 inputModel.onMobileHome();
 _onUserInteraction();
 },
 ),
 _buildButton(
 icon: Icons.apps_rounded,
 tooltip: 'Recent',
 onPressed: () {
 inputModel.onMobileApps();
 _onUserInteraction();
 },
 ),
 _buildButton(
 icon: Icons.volume_up_rounded,
 tooltip: 'Volume up',
 onPressed: () {
 inputModel.onMobileVolumeUp();
 _onUserInteraction();
 },
 ),
 _buildButton(
 icon: Icons.volume_down_rounded,
 tooltip: 'Volume down',
 onPressed: () {
 inputModel.onMobileVolumeDown();
 _onUserInteraction();
 },
 ),
 _buildButton(
 icon: Icons.power_settings_new_rounded,
 tooltip: 'Power',
 onPressed: () {
 inputModel.onMobilePower();
 _onUserInteraction();
 },
 ),
 _buildButton(
 icon: Icons.keyboard_rounded,
 tooltip: 'Keyboard',
 onPressed: () {
 widget.onOpenKeyboard?.call();
 _onUserInteraction();
 },
 ),
 // Divider before exit.
 Container(
 width: 1,
 height: 24,
 margin: const EdgeInsets.only(left: 4),
 color: Colors.white.withOpacity(0.16),
 ),
 _buildButton(
 icon: Icons.close_rounded,
 tooltip: 'Exit',
 color: const Color(0xFFFF7B72),
 onPressed: () {
 clientClose(widget.ffi.sessionId, widget.ffi);
 _onUserInteraction();
 },
 ),
 ];
 }

 List<Widget> _buildAndroidNavButtons() {
 return [
 _buildButton(
 icon: Icons.arrow_back_rounded,
 tooltip: 'Back',
 onPressed: () {
 inputModel.onMobileBack();
 _onUserInteraction();
 },
 ),
 _buildButton(
 icon: Icons.home_rounded,
 tooltip: 'Home',
 onPressed: () {
 inputModel.onMobileHome();
 _onUserInteraction();
 },
 ),
 _buildButton(
 icon: Icons.apps_rounded,
 tooltip: 'Recent',
 onPressed: () {
 inputModel.onMobileApps();
 _onUserInteraction();
 },
 ),
 _buildButton(
 icon: Icons.close_rounded,
 tooltip: 'Exit',
 color: const Color(0xFFFF7B72),
 onPressed: () {
 clientClose(widget.ffi.sessionId, widget.ffi);
 _onUserInteraction();
 },
 ),
 ];
 }

 List<Widget> _buildDesktopButtons() {
 final pi = widget.ffi.ffiModel.pi;
 final canRestart = pi.platform == kPeerPlatformLinux ||
 pi.platform == kPeerPlatformWindows ||
 pi.platform == kPeerPlatformMacOS;
 return [
 _buildButton(
 icon: Icons.keyboard_rounded,
 tooltip: 'Keyboard',
 onPressed: () {
 widget.onOpenKeyboard?.call();
 _onUserInteraction();
 },
 ),
 _buildButton(
 icon: Icons.tune_rounded,
 tooltip: 'Display',
 onPressed: () {
 widget.onOpenDisplay?.call();
 _onUserInteraction();
 },
 ),
 _buildButton(
 icon: Icons.chat_bubble_outline_rounded,
 tooltip: 'Chat',
 onPressed: () {
 widget.onOpenChat?.call();
 _onUserInteraction();
 },
 ),
 if (canRestart) ...[
 _buildButton(
 icon: Icons.restart_alt_rounded,
 tooltip: 'Restart remote device',
 onPressed: () {
 showRestartRemoteDevice(
 pi, widget.ffi.id, widget.ffi.sessionId, widget.ffi.dialogManager);
 _onUserInteraction();
 },
 ),
 _buildButton(
 icon: Icons.power_settings_new_rounded,
 tooltip: 'Shutdown remote device',
 color: const Color(0xFFFFB372),
 onPressed: () {
 showShutdownRemoteDevice(
 pi, widget.ffi.id, widget.ffi.sessionId, widget.ffi.dialogManager);
 _onUserInteraction();
 },
 ),
 ],
 _buildButton(
 icon: Icons.close_rounded,
 tooltip: 'Exit',
 color: const Color(0xFFFF7B72),
 onPressed: () {
 clientClose(widget.ffi.sessionId, widget.ffi);
 _onUserInteraction();
 },
 ),
 ];
 }

 Widget _buildButton({
 required IconData icon,
 String? tooltip,
 Color color = Colors.white,
 required VoidCallback onPressed,
 }) {
 final btn = GestureDetector(
 onTap: onPressed,
 child: Container(
 width: _kButtonSize,
 height: _kButtonSize,
 decoration: const BoxDecoration(
 shape: BoxShape.circle,
 color: Colors.transparent,
 ),
 child: Icon(
 icon,
 size: 22,
 color: color,
 ),
 ),
 );
 if (tooltip != null) {
 return Tooltip(
 message: translate(tooltip),
 child: btn,
 );
 }
 return btn;
 }
}
