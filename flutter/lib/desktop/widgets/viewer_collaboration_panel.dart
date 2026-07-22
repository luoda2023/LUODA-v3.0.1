import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/direct_pairing.dart';
import 'package:luoda_flutter/common/widgets/shared_chat_panel.dart';
import 'package:luoda_flutter/common/widgets/viewer_list_panel.dart';
import 'package:luoda_flutter/models/model.dart';

import 'invite_viewer_dialog.dart';

class ViewerCollaborationPanel extends StatelessWidget {
  const ViewerCollaborationPanel({
    super.key,
    required this.ffi,
  });

  final FFI ffi;

  static Future<void> show(BuildContext context, {required FFI ffi}) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations == true;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: translate('Close'),
      barrierColor: Colors.black.withOpacity(0.18),
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => ViewerCollaborationPanel(ffi: ffi),
      transitionBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutQuart,
          reverseCurve: Curves.easeInCubic,
        )),
        child: child,
      ),
    );
  }

  static Future<void> showInvite(
    BuildContext context, {
    required FFI ffi,
  }) async {
    if (ffi.closed || ffi.viewerMode) return;
    if (!ffi.ffiModel.viewer) {
      await show(context, ffi: ffi);
      return;
    }
    final hostEndpoint =
        DirectPairingStore.resolveEndpoint(ffi.id) ?? ffi.id.trim();
    await InviteViewerDialog.show(
      context,
      sessionId: ffi.sessionId,
      hostLabel: '${translate('Remote Desktop')}: ${ffi.id}',
      hostEndpoint: hostEndpoint,
      viewerSessionModel: ffi.viewerSessionModel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = math.min(440.0, MediaQuery.sizeOf(context).width);
    final localName = (ffi.chatModel.me.firstName ?? '').trim();
    final hostEndpoint =
        DirectPairingStore.resolveEndpoint(ffi.id) ?? ffi.id.trim();
    final isHost = !ffi.viewerMode;
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 8,
          child: SizedBox(
            width: width,
            height: double.infinity,
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: 60,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 18, right: 8),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              translate('Remote assistance'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: ffi.ffiModel,
                            builder: (context, _) {
                              final allowed =
                                  isHost && ffi.ffiModel.viewer && !ffi.closed;
                              return Tooltip(
                                message: translate(allowed
                                    ? 'Invite Viewer'
                                    : 'Viewer permission required'),
                                child: TextButton.icon(
                                  onPressed: !allowed
                                      ? null
                                      : () => InviteViewerDialog.show(
                                            context,
                                            sessionId: ffi.sessionId,
                                            hostLabel:
                                                '${translate('Remote Desktop')}: ${ffi.id}',
                                            hostEndpoint: hostEndpoint,
                                            viewerSessionModel:
                                                ffi.viewerSessionModel,
                                          ),
                                  icon: const Icon(
                                    Icons.person_add_alt_1_rounded,
                                    size: 18,
                                  ),
                                  label: Text(translate('Invite Viewer')),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            tooltip: translate('Close'),
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  AnimatedBuilder(
                    animation: ffi.ffiModel,
                    builder: (context, _) => isHost && !ffi.ffiModel.viewer
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            color: theme.colorScheme.surfaceVariant,
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${translate('Viewer permission required')}: '
                                    '${translate('Allow viewers to join')}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  TabBar(
                    tabs: <Widget>[
                      Tab(text: translate('Viewer List')),
                      Tab(text: translate('Shared Chat')),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: <Widget>[
                        ViewerListPanel(
                          sessionId: ffi.sessionId,
                          viewerSessionModel: ffi.viewerSessionModel,
                          isHost: isHost,
                          selfViewerId: ffi.viewerId,
                        ),
                        SharedChatPanel(
                          sessionId: ffi.sessionId,
                          viewerSessionModel: ffi.viewerSessionModel,
                          isHost: isHost,
                          selfViewerId: isHost ? 'host' : ffi.viewerId,
                          selfDisplayName:
                              localName.isEmpty ? translate('Me') : localName,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
