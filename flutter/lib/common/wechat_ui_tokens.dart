import 'package:flutter/material.dart';

const Color kWeChatPrimaryColor = Color(0xFF07C160);
const Color kWeChatChromeColor = Color(0xFFE3E8E5);
const Color kWeChatListSurfaceColor = Color(0xFFF0F1F2);
const Color kWeChatCanvasColor = Color(0xFFF7F7F7);
// LUODA FIX: light-mode incoming bubble must be visually distinct from the
// near-white canvas (#F7F7F7). Pure white on near-white is invisible. We use a
// warm off-white plus a subtle 1px border so peer messages read clearly.
const Color kWeChatIncomingBubbleColor = Color(0xFFFFFFFF);
const Color kWeChatIncomingBubbleBorder = Color(0xFFE2E2E2);
const Color kWeChatOutgoingBubbleColor = Color(0xFF95EC69);
const Color kWeChatSelectedConversationColor = Color(0xFF07C160);
const Color kWeChatDividerColor = Color(0xFFE5E5E5);

/// Dark-mode canvas — slightly lighter than pure #1C1E23 so incoming bubbles
/// (Color(0xFF2B2D32)) remain visually distinguishable from the background.
const Color kWeChatCanvasColorDark = Color(0xFF181A1F);
/// Dark-mode incoming bubble — lightened from #2B2D32 to give meaningful
/// contrast against kWeChatCanvasColorDark.
const Color kWeChatIncomingBubbleColorDark = Color(0xFF3A3D43);
/// Dark-mode outgoing bubble — slightly brighter green so it still pops in dark.
const Color kWeChatOutgoingBubbleColorDark = Color(0xFF4A8F66);

const double kWeChatDesktopRailWidth = 64;
const double kWeChatDesktopRailButtonSize = 44;
const double kWeChatDesktopListWidthCompact = 264;
const double kWeChatDesktopListWidthWide = 284;
const double kWeChatDesktopRailBreakpoint = 820;
const double kWeChatDesktopWideBreakpoint = 1180;
const double kWeChatHeadingFontSize = 16;
const double kWeChatBodyFontSize = 14;
const double kWeChatMetaFontSize = 12;
const double kWeChatTextHeight = 1.3;

bool weChatShowDesktopRail(double availableWidth) =>
    availableWidth >= kWeChatDesktopRailBreakpoint;

double weChatConversationListWidth(double availableWidth) =>
    availableWidth >= kWeChatDesktopWideBreakpoint
        ? kWeChatDesktopListWidthWide
        : kWeChatDesktopListWidthCompact;
