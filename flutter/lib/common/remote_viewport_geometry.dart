import 'dart:math' as math;
import 'dart:ui';

class RemoteViewportGeometry {
  const RemoteViewportGeometry({
    required this.globalOrigin,
    required this.size,
  });

  final Offset globalOrigin;
  final Size size;

  Offset globalToLocal(Offset globalPosition) => globalPosition - globalOrigin;
}

class RemoteFramebufferTransform {
  const RemoteFramebufferTransform({
    required this.imageOrigin,
    required this.scale,
    this.remoteFrameOrigin = Offset.zero,
  });

  factory RemoteFramebufferTransform.adaptive({
    required Size viewportSize,
    required Size remoteFrameSize,
  }) {
    final scale = math.min(
      viewportSize.width / remoteFrameSize.width,
      viewportSize.height / remoteFrameSize.height,
    );
    return RemoteFramebufferTransform(
      imageOrigin: Offset(
        (viewportSize.width - remoteFrameSize.width * scale) / 2,
        (viewportSize.height - remoteFrameSize.height * scale) / 2,
      ),
      scale: scale,
    );
  }

  final Offset imageOrigin;
  final double scale;
  final Offset remoteFrameOrigin;

  Offset viewportToRemote(Offset viewportPosition) {
    if (!scale.isFinite || scale <= 0) return remoteFrameOrigin;
    return Offset(
      (viewportPosition.dx - imageOrigin.dx) / scale + remoteFrameOrigin.dx,
      (viewportPosition.dy - imageOrigin.dy) / scale + remoteFrameOrigin.dy,
    );
  }

  Offset remoteToViewport(Offset remotePosition) => Offset(
        (remotePosition.dx - remoteFrameOrigin.dx) * scale + imageOrigin.dx,
        (remotePosition.dy - remoteFrameOrigin.dy) * scale + imageOrigin.dy,
      );
}
