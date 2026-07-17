import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:luoda_flutter/common.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = math.min(440.0, MediaQuery.sizeOf(context).width);
    final localName = (ffi.chatModel.me.firstName ?? '').trim();
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
                          TextButton.icon(
                            onPressed: ffi.closed
                                ? null
                                : () => InviteViewerDialog.show(
                                      context,
                                      sessionId: ffi.sessionId,
                                      hostLabel:
                                          '${translate('Remote Desktop')}: ${ffi.id}',
                                      viewerSessionModel:
                                          ffi.viewerSessionModel,
                                    ),
                            icon: const Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 18,
                            ),
                            label: Text(translate('Invite Viewer')),
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
                          isHost: true,
                        ),
                        SharedChatPanel(
                          sessionId: ffi.sessionId,
                          viewerSessionModel: ffi.viewerSessionModel,
                          isHost: true,
                          selfViewerId: 'host',
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
