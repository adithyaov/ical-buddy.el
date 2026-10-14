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
(use-package ical-buddy
  :straight (ical-buddy :host github :repo "adithyaov/ical-buddy.el")
  :config
  (setq ical-buddy-org-file "~/org/calendar.org")
  (setq ical-buddy-calendars '("work@example.com" "personal@example.com"))

  (add-to-list 'org-agenda-files ical-buddy-org-file)

  (cl-flet ((refresh (&rest _)
               (ical-buddy-refresh (ical-buddy-date-string 0)
                                   (ical-buddy-date-string 7))))
    (add-hook 'org-agenda-mode-hook #'refresh)
    (advice-add 'org-agenda-redo :before #'refresh)))
```

Or clone the repo, add it to your `load-path`, and use the `:config` block above
without the `:straight` line.

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

Or call `M-x ical-buddy-refresh` interactively. It opens Org's calendar picker
for the start and end dates.

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
