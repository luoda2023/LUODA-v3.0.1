# PRODUCT.md

## Register
product

## What this is
点聊 / DotChat - a peer-to-peer direct-chat and remote-assistance app (Rust core + Flutter UI).
Primary surfaces: chat list (Messages), contacts, chat conversation, remote control.

## Who uses it
Individuals and small teams who want to chat, transfer files and remotely assist each other
over LAN or the public Internet without a centralized server. Used on Windows, Android phone/tablet.

## Primary task
Send/receive messages, see who is online, start a direct (ID/IP/Bluetooth) chat, and assist or be assisted remotely.

## Brand personality
Trustworthy, minimal, warm, familiar (WeChat-grade polish).
Three words: clean, reliable, friendly.

## Anti-references
- Cluttered permission banners stacked above content
- ID numbers dumped into list rows
- Mixed/inconsistent font sizes and colors
- Heavy borders and shadows on cards
- English labels leaking into a Chinese UI

## Strategic design principles
1. The list IS the home: minimal chrome, WeChat-like rows (avatar, name, time, preview, badge).
2. Permissions and status belong in settings / subtle indicators, never a blocking banner.
3. Same person = one row; connection details (ID/IP/port) live in the details dialog, not the list.
4. Chinese-first: every customer-visible string shows 中文 when the UI language is Chinese.
5. Green accent (#057A3A) is the brand color; backgrounds stay light and quiet.
