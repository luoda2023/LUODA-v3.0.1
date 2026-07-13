---
name: LUODA Remote Center
description: A calm and precise desktop control surface for secure remote access.
colors:
  primary: "#0B6EF3"
  primary-hover: "#095FCC"
  primary-soft: "#EAF2FF"
  canvas: "#F5F8FC"
  surface: "#FFFFFF"
  surface-dark: "#1B2029"
  text: "#141A24"
  text-muted: "#5D687A"
  border: "#DCE5F2"
  success: "#22B85A"
  warning: "#F08A00"
typography:
  headline:
    fontFamily: "Segoe UI, system-ui, sans-serif"
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "0"
  title:
    fontFamily: "Segoe UI, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 600
    lineHeight: 1.35
    letterSpacing: "0"
  body:
    fontFamily: "Segoe UI, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.45
    letterSpacing: "0"
  label:
    fontFamily: "Segoe UI, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 500
    lineHeight: 1.3
    letterSpacing: "0"
rounded:
  sm: "6px"
  md: "8px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.surface}"
    rounded: "{rounded.md}"
    padding: "12px 18px"
    height: "44px"
  button-primary-hover:
    backgroundColor: "{colors.primary-hover}"
    textColor: "{colors.surface}"
    rounded: "{rounded.md}"
  input:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    rounded: "{rounded.md}"
    padding: "12px 14px"
    height: "44px"
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    rounded: "{rounded.md}"
    padding: "24px"
---

# Design System: LUODA Remote Center

## Overview

**Creative North Star: "The Quiet Control Room"**

LUODA should feel like a focused control surface: clear enough for first-time users and efficient enough for repeated support work. Information is grouped by task, visual emphasis is reserved for the primary connection action, and security state remains explicit. The interface rejects the current fragmented legacy layout, marketing-style dashboard composition, decorative glass effects, and oversized display typography.

**Key Characteristics:**

- Restrained blue accent on clean neutral surfaces.
- Dense but calm desktop information hierarchy.
- Familiar controls with explicit hover, focus, active, disabled, and error states.
- Structural responsive behavior rather than viewport-scaled typography.

## Colors

The palette uses one technical blue for actions and selection, supported by cool neutral surfaces and semantic status colors.

### Primary

- **Control Blue:** Primary actions, selected navigation, focus rings, and active controls only.
- **Control Blue Soft:** Selected navigation backgrounds and low-emphasis information states.

### Neutral

- **Cool Canvas:** Application background and separation between work areas.
- **Clear Surface:** Cards, inputs, menus, and primary content areas.
- **Deep Ink:** Headings, values, and important labels.
- **Operational Gray:** Supporting copy and secondary metadata.
- **Cool Divider:** Structural separators and input outlines.

### Named Rules

**The One Accent Rule.** Control Blue is used for actions and state, never as ambient decoration.

**The Semantic State Rule.** Online and warning colors always include a text label or icon; color alone never communicates state.

## Typography

**Display Font:** Segoe UI (with system UI fallback)
**Body Font:** Segoe UI (with system UI fallback)
**Label/Mono Font:** Platform monospace for IDs, addresses, and passwords only

**Character:** A single familiar sans-serif keeps the product quiet and readable. Weight and spacing establish hierarchy without decorative typography.

### Hierarchy

- **Headline** (700, 24px, 1.25): Page titles only.
- **Title** (600, 18px, 1.35): Card and section titles.
- **Body** (400, 14px, 1.45): Settings descriptions and device metadata.
- **Label** (500, 13px, 1.3): Navigation, field labels, and compact controls.

### Named Rules

**The Data Clarity Rule.** IDs and network addresses may use monospace; navigation and settings labels never do.

## Elevation

The system is flat by default. Depth comes from tonal separation and precise outlines; a restrained shadow is reserved for menus and transient overlays.

### Named Rules

**The Flat Workspace Rule.** Permanent cards use either a cool divider outline or tonal separation, never a wide decorative shadow combined with a border.

## Components

### Buttons

- **Shape:** Compact, gently curved rectangle (8px radius).
- **Primary:** Control Blue with white content and a stable 44px height.
- **Hover / Focus:** Darker blue on hover; a visible blue focus ring for keyboard use.
- **Secondary / Ghost:** White or transparent surface with a Cool Divider outline and Deep Ink content.

### Cards / Containers

- **Corner Style:** Restrained desktop radius (8px).
- **Background:** Clear Surface over Cool Canvas.
- **Shadow Strategy:** Flat by default; menus may use a short ambient shadow.
- **Border:** One-pixel Cool Divider where separation is required.
- **Internal Padding:** 16px compact, 24px standard.

### Inputs / Fields

- **Style:** White field, one-pixel Cool Divider outline, and 8px radius.
- **Focus:** Control Blue outline with no layout shift.
- **Error / Disabled:** Semantic error outline; disabled content remains legible and clearly inactive.

### Navigation

The main shell uses icon-and-label navigation with a soft blue selected state. Settings use a stable left category rail and a scrollable content pane. Navigation selection changes in 180ms and does not animate layout.

### Identity Panel

Local ID, password, and IP:port appear together. Each value has an explicit label and copy action; password visibility and refresh remain separate controls.

## Do's and Don'ts

### Do:

- **Do** keep the primary remote connection action visible without scrolling.
- **Do** preserve every existing permission, platform condition, and disabled state when restyling settings.
- **Do** use 8px card, input, and button radii consistently.
- **Do** verify compact and wide desktop layouts with fixed control heights and bounded text.

### Don't:

- **Don't** reproduce the current fragmented legacy layout with weak hierarchy and inconsistent control styling.
- **Don't** use marketing-style dashboards, oversized typography, decorative glass effects, or excessive gradients.
- **Don't** hide important security state behind vague labels or low-contrast controls.
- **Don't** place cards inside cards or combine a permanent card border with a wide soft shadow.
- **Don't** use colored side-stripe borders, gradient text, or decorative motion.
