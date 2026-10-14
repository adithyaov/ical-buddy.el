# ical-buddy.el

Bring macOS Calendar.app events into the Org agenda via
[icalBuddy](https://hasseg.org/icalBuddy/).

## Requirements

- macOS with Calendar.app configured (add accounts in **System Settings →
  Internet Accounts**)
- [icalBuddy](https://hasseg.org/icalBuddy/) (`brew install ical-buddy`)
- Emacs 27.1+, Org 9.0+

## Installation

```elisp
;; With use-package + straight
(use-package ical-buddy
  :straight (:host github :repo "adithyaov/ical-buddy.el"))
```

Or clone the repo and add it to your `load-path`.

## Setup

```elisp
(setq ical-buddy-org-file "~/org/calendar.org")

;; Optional: restrict to specific calendars (run `icalBuddy calendars` to list them)
(setq ical-buddy-calendars '("Work" "Personal"))

;; Optional: if icalBuddy is not on Emacs's PATH
(setq ical-buddy-executable "/opt/homebrew/bin/icalBuddy")
```

## Usage

### Refresh the Org file

```elisp
;; Write today's events to ical-buddy-org-file
(ical-buddy-refresh (ical-buddy-date-string 0)
                    (ical-buddy-date-string 0))

;; Write the next 7 days
(ical-buddy-refresh (ical-buddy-date-string 0)
                    (ical-buddy-date-string 7))
```

Or call `M-x ical-buddy-refresh` interactively — it opens Org's calendar picker
for the start and end dates.

### Add to the Org agenda

```elisp
(add-to-list 'org-agenda-files "~/org/calendar.org")
```

### Auto-refresh with the agenda

This refreshes before the agenda opens and before every manual refresh (`g`):

```elisp
(defun my/ical-buddy-refresh (&rest _)
  (ical-buddy-refresh (ical-buddy-date-string 0)
                      (ical-buddy-date-string 7)))

(add-hook 'org-agenda-mode-hook #'my/ical-buddy-refresh)
(advice-add 'org-agenda-redo :before #'my/ical-buddy-refresh)
```

## Output format

Each event becomes an Org heading with an active timestamp (so it appears in the
agenda), an optional `LOCATION` property, and any notes as body text:

```org
* Team standup
:PROPERTIES:
:LOCATION: Zoom
:END:
<2025-01-15 Wed 09:00-09:30>
```
