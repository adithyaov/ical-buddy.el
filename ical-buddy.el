;;; ical-buddy.el --- Bring macOS Calendar events into the Org agenda -*- lexical-binding: t; -*-

;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.0"))
;; Keywords: calendar, org, convenience

;;; Commentary:

;; Reads events from macOS Calendar.app through the `icalBuddy' command
;; line tool (brew install ical-buddy), converts them to Org headings
;; with active timestamps, and writes them to a file.
;;
;; Main entry points:
;;
;;   `ical-buddy-get-events'       => plain text from icalBuddy (FROM TO required)
;;   `ical-buddy-convert-to-org'   => Org text from that plain text
;;   `ical-buddy-refresh'          => get + convert + write `ical-buddy-org-file'
;;
;; You must set `ical-buddy-org-file' before calling `ical-buddy-refresh'.
;;
;; Add your Google (or other) account in System Settings > Internet
;; Accounts first, so Calendar.app has the events.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)

;;;; Customization

(defgroup ical-buddy nil
  "Org agenda from macOS Calendar via icalBuddy."
  :group 'org
  :prefix "ical-buddy-")

(defcustom ical-buddy-executable "icalBuddy"
  "Name or full path of the icalBuddy executable.
GUI Emacs on macOS often lacks your shell PATH; if icalBuddy is not
found, set this to e.g. \"/opt/homebrew/bin/icalBuddy\"."
  :type 'string
  :group 'ical-buddy)

(defcustom ical-buddy-calendars nil
  "List of calendar names to include, or nil for all calendars.
Run `icalBuddy calendars' in a terminal to see the exact names."
  :type '(repeat string)
  :group 'ical-buddy)

(defcustom ical-buddy-org-file nil
  "Org file that `ical-buddy-refresh' writes (it is overwritten each time).
Must be set by the user before calling `ical-buddy-refresh'."
  :type '(choice (const :tag "Not set" nil) file)
  :group 'ical-buddy)

;;;; Internals

(defconst ical-buddy--bullet "@@ "
  "Bullet string passed to icalBuddy so event starts are unambiguous.")

(defconst ical-buddy--properties "title,datetime,location,notes"
  "Properties requested from icalBuddy, in output order.")

(cl-defstruct (ical-buddy-event (:constructor ical-buddy-event--create))
  title when location notes)

;;;###autoload
(defun ical-buddy-date-string (offset-days)
  "Return today's date shifted by OFFSET-DAYS as YYYY-MM-DD."
  (format-time-string "%Y-%m-%d"
                      (time-add (current-time) (* offset-days 86400))))

(defun ical-buddy--weekday (date)
  "Return the abbreviated weekday name for DATE (YYYY-MM-DD)."
  ;; `split-string' clobbers the match data, which callers still need.
  (save-match-data
    (let* ((parts (mapcar #'string-to-number (split-string date "-")))
           (y (nth 0 parts)) (m (nth 1 parts)) (d (nth 2 parts)))
      (format-time-string "%a" (encode-time (list 0 0 0 d m y nil -1 nil))))))

(defun ical-buddy--stamp (date &optional time)
  "Return an Org active timestamp for DATE and optional TIME string."
  (format "<%s %s%s>" date (ical-buddy--weekday date)
          (if time (concat " " time) "")))

(defun ical-buddy--parse-when (s)
  "Turn an icalBuddy date line S into an Org timestamp, or nil.
Recognized forms (dates are YYYY-MM-DD, times HH:MM):
  DATE at T1 - T2
  DATE at T1
  DATE
  DATE [at T1] - DATE [at T2]"
  (let ((d "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)")
        (tm "\\([0-9]\\{2\\}:[0-9]\\{2\\}\\)"))
    (cond
     ((string-match (concat "\\`" d " at " tm " - " tm "\\'") s)
      (ical-buddy--stamp (match-string 1 s)
                         (concat (match-string 2 s) "-" (match-string 3 s))))
     ((string-match (concat "\\`" d " at " tm "\\'") s)
      (ical-buddy--stamp (match-string 1 s) (match-string 2 s)))
     ((string-match (concat "\\`" d "\\'") s)
      (ical-buddy--stamp (match-string 1 s)))
     ((string-match (concat "\\`" d "\\(?: at " tm "\\)? - "
                            d "\\(?: at " tm "\\)?\\'")
                    s)
      (concat (ical-buddy--stamp (match-string 1 s) (match-string 2 s))
              "--"
              (ical-buddy--stamp (match-string 3 s) (match-string 4 s)))))))

(defun ical-buddy--parse (text)
  "Parse icalBuddy TEXT into a list of `ical-buddy-event' structs."
  (let (events cur last-key)
    (dolist (line (split-string text "\n"))
      (let ((s (string-trim line)))
        (cond
         ;; Start of a new event.
         ((string-prefix-p ical-buddy--bullet line)
          (setq cur (ical-buddy-event--create
                     :title (string-trim
                             (substring line (length ical-buddy--bullet))))
                last-key nil)
          (push cur events))
         ;; Blank line or text before the first event.
         ((or (null cur) (string-empty-p s)) nil)
         ((string-prefix-p "location:" s)
          (setf (ical-buddy-event-location cur) (string-trim (substring s 9)))
          (setq last-key 'location))
         ((string-prefix-p "notes:" s)
          (setf (ical-buddy-event-notes cur)
                (append (ical-buddy-event-notes cur)
                        (list (string-trim (substring s 6)))))
          (setq last-key 'notes))
         (t
          (let ((w (and (null (ical-buddy-event-when cur))
                        (null last-key)
                        (ical-buddy--parse-when s))))
            (cond
             (w (setf (ical-buddy-event-when cur) w))
             ((eq last-key 'location)
              (setf (ical-buddy-event-location cur)
                    (concat (ical-buddy-event-location cur) " " s)))
             (t
              (setf (ical-buddy-event-notes cur)
                    (append (ical-buddy-event-notes cur) (list s))))))))))
    (nreverse events)))

(defun ical-buddy--format-event (event)
  "Return Org text for EVENT.
The property drawer comes directly after the heading, as Org requires;
the active timestamp follows it so the entry shows up in the agenda."
  (let ((title (ical-buddy-event-title event))
        (when-str (ical-buddy-event-when event))
        (loc (ical-buddy-event-location event)))
    (concat
     "* " (if (string-empty-p title) "(no title)" title) "\n"
     (when (and loc (not (string-empty-p loc)))
       (concat ":PROPERTIES:\n:LOCATION: " loc "\n:END:\n"))
     (when when-str (concat when-str "\n"))
     ;; Indent notes so a leading "*" can never become a headline.
     (mapconcat (lambda (n) (concat "  " n "\n"))
                (ical-buddy-event-notes event) ""))))

;;;; Public API

;;;###autoload
(defun ical-buddy-get-events (from to)
  "Return icalBuddy's plain-text output for events from FROM to TO.
FROM and TO are YYYY-MM-DD strings."
  (let* ((exe (or (executable-find ical-buddy-executable)
                  (user-error "Cannot find icalBuddy (see `ical-buddy-executable')")))
         (args (append
                (list "-b" ical-buddy--bullet
                      "-nc" "-nrd"
                      "-df" "%Y-%m-%d" "-tf" "%H:%M"
                      "-iep" ical-buddy--properties
                      "-po" ical-buddy--properties)
                (when ical-buddy-calendars
                  (list "-ic" (string-join ical-buddy-calendars ",")))
                (list (concat "eventsFrom:" from) (concat "to:" to))))
         (coding-system-for-read 'utf-8))
    (with-temp-buffer
      (let ((status (apply #'call-process exe nil t nil args)))
        (unless (eq status 0)
          (error "icalBuddy exited with status %s: %s"
                 status (string-trim (buffer-string))))
        (buffer-string)))))

;;;###autoload
(defun ical-buddy-convert-to-org (text)
  "Convert icalBuddy plain-text output TEXT into Org headings.
TEXT must have been produced with the options used by
`ical-buddy-get-events'.  Returns a string."
  (mapconcat #'ical-buddy--format-event (ical-buddy--parse text) ""))

;;;###autoload
(defun ical-buddy-refresh (from to)
  "Fetch events for FROM to TO, convert to Org, and write `ical-buddy-org-file'.
FROM and TO are YYYY-MM-DD strings.
Also reverts the file's buffer if it is already open."
  (interactive
   (list (org-read-date nil nil nil "Start date: ")
         (org-read-date nil nil nil "End date: ")))
  (unless ical-buddy-org-file
    (user-error "Set `ical-buddy-org-file' before calling `ical-buddy-refresh'"))
  (let* ((file (expand-file-name ical-buddy-org-file))
         (org (ical-buddy-convert-to-org (ical-buddy-get-events from to)))
         (coding-system-for-write 'utf-8))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert "#+TITLE: Calendar (icalBuddy)\n"
              "#+CATEGORY: calendar\n"
              "#+STARTUP: overview\n"
              (format-time-string "# Generated by ical-buddy at %F %R. Do not edit.\n\n")
              org))
    (when-let ((buf (find-buffer-visiting file)))
      (with-current-buffer buf (revert-buffer t t t)))
    (when (called-interactively-p 'interactive)
      (message "ical-buddy: wrote %s" file))
    file))

(provide 'ical-buddy)
;;; ical-buddy.el ends here
