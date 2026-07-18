import 'package:flutter/material.dart';

const Color kWeChatPrimaryColor = Color(0xFF07C160);
const Color kWeChatChromeColor = Color(0xFFE3E8E5);
const Color kWeChatListSurfaceColor = Color(0xFFF0F1F2);
const Color kWeChatCanvasColor = Color(0xFFF7F7F7);
const Color kWeChatIncomingBubbleColor = Color(0xFFFFFFFF);
const Color kWeChatOutgoingBubbleColor = Color(0xFF95EC69);
const Color kWeChatSelectedConversationColor = Color(0xFF07C160);
const Color kWeChatDividerColor = Color(0xFFE5E5E5);

const double kWeChatDesktopRailWidth = 64;
const double kWeChatDesktopRailButtonSize = 44;
const double kWeChatDesktopListWidthCompact = 264;
const double kWeChatDesktopListWidthWide = 284;
const double kWeChatDesktopRailBreakpoint = 820;
const double kWeChatDesktopWideBreakpoint = 1180;

bool weChatShowDesktopRail(double availableWidth) =>
    availableWidth >= kWeChatDesktopRailBreakpoint;

double weChatConversationListWidth(double availableWidth) =>
    availableWidth >= kWeChatDesktopWideBreakpoint
        ? kWeChatDesktopListWidthWide
        : kWeChatDesktopListWidthCompact;
