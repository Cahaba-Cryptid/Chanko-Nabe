class_name ThemeColors
extends RefCounted

## ============================================================================
## CHANKO NABE - Theme Colors
## ============================================================================
## Central color definitions for the entire game.
## Use these constants instead of hardcoding colors in scenes/scripts.
## To change the game's color scheme, edit ONLY this file.
## ============================================================================

# ----------------------------------------------------------------------------
# BACKGROUNDS
# ----------------------------------------------------------------------------
## Main background color for screens
const BG_MAIN := Color(0.08, 0.08, 0.1, 1)
## Dimmer overlay for modal dialogs
const BG_DIMMER := Color(0, 0, 0, 0.7)
## Panel background
const BG_PANEL := Color(0.12, 0.12, 0.15, 1)
## Card/item background
const BG_CARD := Color(0.15, 0.15, 0.18, 1)
## Hover state background
const BG_HOVER := Color(0.2, 0.2, 0.25, 1)
## Selected state background
const BG_SELECTED := Color(0.25, 0.25, 0.3, 1)

# ----------------------------------------------------------------------------
# TEXT COLORS
# ----------------------------------------------------------------------------
## Primary text (bright)
const TEXT_PRIMARY := Color(0.9, 0.9, 0.9, 1)
## Secondary text (descriptions, details)
const TEXT_SECONDARY := Color(0.8, 0.8, 0.8, 1)
## Muted text (hints, disabled)
const TEXT_MUTED := Color(0.5, 0.5, 0.5, 1)
## Label text (column headers, form labels)
const TEXT_LABEL := Color(0.6, 0.6, 0.6, 1)
## Section headers
const TEXT_HEADER := Color(0.7, 0.7, 0.7, 1)

# ----------------------------------------------------------------------------
# ACCENT COLORS
# ----------------------------------------------------------------------------
## Gold - Primary accent (money, important values, hover states)
const ACCENT_GOLD := Color(1.0, 0.85, 0.4, 1)
## Gold darker - Pressed/active state
const ACCENT_GOLD_DARK := Color(0.8, 0.68, 0.32, 1)

# ----------------------------------------------------------------------------
# STAT COLORS (for quick visual identification)
# ----------------------------------------------------------------------------
## Green - Positive values (fullness, stamina, health gains)
const STAT_POSITIVE := Color(0.6, 0.8, 0.6, 1)
## Bright Green - Strong positive (effects, bonuses)
const STAT_POSITIVE_BRIGHT := Color(0.4, 0.9, 0.5, 1)
## Yellow/Tan - Resources (starting money, resources)
const STAT_RESOURCE := Color(0.9, 0.85, 0.5, 1)
## Orange - Weight stat
const STAT_WEIGHT := Color(0.9, 0.7, 0.5, 1)
## Purple - BB Factor
const STAT_BB := Color(0.8, 0.6, 0.8, 1)
## Light Blue - Time-based info
const STAT_TIME := Color(0.6, 0.7, 0.8, 1)
## Red - Negative values, warnings
const STAT_NEGATIVE := Color(0.9, 0.5, 0.5, 1)
## Mint Green - Energy
const STAT_ENERGY := Color(0.7, 0.85, 0.7, 1)

# ----------------------------------------------------------------------------
# UI ELEMENT COLORS
# ----------------------------------------------------------------------------
## Separator lines
const SEPARATOR := Color(0.3, 0.3, 0.35, 1)
## Border/outline
const BORDER := Color(0.25, 0.25, 0.3, 1)
## Placeholder portrait
const PORTRAIT_PLACEHOLDER := Color(0.6, 0.4, 0.5, 1)

# ----------------------------------------------------------------------------
# SHOP SPECIFIC (if you want different themed shops)
# ----------------------------------------------------------------------------
## Vendi shop accent
const SHOP_VENDI := Color(0.4, 0.7, 0.9, 1)
## Dr. Dan shop accent (green medical theme)
const SHOP_DR_DAN := Color(0.4, 0.8, 0.4, 1)
const SHOP_DR_DAN_DIMMER := Color(0, 0.05, 0, 0.75)
