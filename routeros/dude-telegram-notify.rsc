# ==============================================================================
# dude-telegram-notify.rsc
#
# RouterOS script for The Dude network monitor.
# Sends probe state-change events to one or more Telegram
# chats — groups, channels, or individual users.
#
# HOW THE DUDE CALLS THIS SCRIPT
# ─────────────────────────────────────────────────────────────────────────────
# The Dude performs text substitution of %Variable% tokens in the script
# source before sending it to RouterOS for execution.  This means the script
# body you store in The Dude's notification editor is the template; the live
# device/probe values are spliced in at runtime by The Dude itself.
#
# Consequence: device names, probe names, and addresses must not contain
# RouterOS-special characters ( " \ [ ] { } ) because the substitution happens
# before RouterOS parses the script.  Standard naming conventions (alphanumeric,
# spaces, hyphens, underscores) are safe.
#
# SETUP
# ─────────────────────────────────────────────────────────────────────────────
# 1. Edit the Configuration block below (botToken, chatIds).
#
# 2. Copy the full script content into The Dude:
#      Notifications → Add  →  Type: Script
#      Paste this file into the "Script" field.
#      Name the notification (e.g. "Telegram").
#
# 3. Assign the notification to probes:
#      Select probe(s) → Notifications → add "Telegram".
#
# Alternatively, import as a named RouterOS script and reference it by name
# (some Dude versions support "Script name" instead of inline body):
#      /import file-name=dude-telegram-notify.rsc
#    Then set The Dude notification Script field to "dude-telegram-notify".
#
# TESTED WITH
# ─────────────────────────────────────────────────────────────────────────────
# RouterOS 7.x  •  The Dude 7.x (RouterOS package)
# ==============================================================================


# ── Configuration ─────────────────────────────────────────────────────────────

# Bot token obtained from @BotFather on Telegram.
:local botToken "8668018075:AAHeT1fuyQi1Ik6wTq_vmlS6R-VEtrUXKa0"

# One or more recipients.  Separate with semicolons.
#   Group / supergroup chat ID  →  negative integer, e.g. -1001234567890
#   Individual user ID          →  positive integer, e.g. 987654321
#   Public channel username     →  string with @,  e.g. @mychannel
:local chatIds {"-4861266729"; "7555918769"}


# ── Dude event variables ───────────────────────────────────────────────────────
# The Dude replaces %Placeholder% tokens before RouterOS sees this script.
# Consult your Dude version's documentation if a variable appears verbatim
# (i.e. The Dude does not recognise that placeholder name).

:local deviceName  "%DeviceName%"
:local deviceAddr  "%Address%"
:local probeName   "%ProbeName%"
:local probeType   "%ProbeType%"
:local probeStatus "%ProbeStatus%"
:local eventTime   "%Time%"
:local eventDate   "%Date%"


# ── Status label ───────────────────────────────────────────────────────────────

:local label
:if ($probeStatus = "down")         do={ :set label "DOWN" }
:if ($probeStatus = "up")           do={ :set label "UP" }
:if ($probeStatus = "unknown")      do={ :set label "UNKNOWN" }
:if ($probeStatus = "not polled")   do={ :set label "NOT POLLED" }
:if ([:len $label] = 0)             do={ :set label $probeStatus }


# ── Build message ──────────────────────────────────────────────────────────────
# Real newlines are fine here — [:convert to=url] encodes them as %0A.

:local msg ("--------------------\n[ " . $label . " ]  " . $deviceName . \
            "\nAddress : " . $deviceAddr . \
            "\nProbe   : " . $probeName . " (" . $probeType . ")" . \
            "\nTime    : " . $eventDate . " " . $eventTime . \
            "\n--------------------")


# ── Deliver to each recipient ──────────────────────────────────────────────────
# [:convert to=url] handles all URL encoding (spaces, newlines, special chars).
# \3F resolves to "?" inside a single quoted string — RouterOS requires the
# escape to live in one string literal, not across concatenation boundaries.

:local text [:convert $msg to=url]

:foreach chatId in=$chatIds do={
    :local sendUrl "https://api.telegram.org/bot$botToken/sendMessage\3Fchat_id=$chatId&text=$text&disable_web_page_preview=true"
    /tool fetch url=$sendUrl keep-result=no

    :log info ("dude-telegram-notify: notified " . $chatId . " — " . $deviceName . " " . $label)
}
