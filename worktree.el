;;; worktree.el -*- lexical-binding: t; -*-
;;
;; Switch between the git worktrees of the current repo, carrying the whole
;; editing session across: every buffer visiting <old-root>/x/y ends up visiting
;; <new-root>/x/y, in the same windows, at roughly the same place.
;;
;; Nothing on MELPA/ELPA does this. Magit ships the plumbing
;; (`magit-list-worktrees') but only ever *visits* a worktree, leaving every
;; other buffer pointed at the checkout you came from.
;;
;; The wrinkle this file is shaped around: worktrees here are *nested inside*
;; the main checkout (<repo>/.claude/worktrees/<branch>, gitignored). So "is
;; this file under the current root?" is not a usable ownership test -- a file
;; in a sibling worktree is also under the main root, and mapping it by its
;; main-relative path yields a path that doesn't exist in the target (nested
;; worktrees have no .claude/worktrees/ of their own), which would silently kill
;; it. Every path question here is therefore answered by LONGEST matching root.

(require 'cl-lib)
(require 'seq)

(defconst +worktree-fold-case-p (memq system-type '(darwin windows-nt))
  "Whether path comparison must ignore case.
APFS is case-insensitive by default, and `file-truename' does not
normalise case, so `magit-toplevel' and `buffer-file-name' can disagree
in spelling for the same file.  Comparing case-sensitively there would
classify live files as orphans -- and orphans get killed.")


;;; Worktree resolution

(defun +worktree--dir (path)
  "PATH as a truename'd, slash-terminated directory."
  (file-name-as-directory (file-truename path)))

(defun +worktree--roots ()
  "Roots of every live worktree of this repo, LONGEST FIRST.
Longest-first is what makes the nested layout resolve correctly in
`+worktree--owner'.  Bare and deleted-but-unpruned worktrees are dropped:
they have no working tree to move buffers into."
  (require 'magit)
  (sort (cl-loop for wt in (magit-list-worktrees)
                 unless (nth 3 wt)                    ; BARE
                 when (file-directory-p (car wt))     ; deleted but unpruned
                 collect (+worktree--dir (car wt)))
        (lambda (a b) (> (length a) (length b)))))

(defun +worktree--owner (path roots)
  "Which of ROOTS contains PATH.  ROOTS must be longest-first."
  (when path
    (let ((path (file-truename path)))
      (seq-find (lambda (root) (string-prefix-p root path +worktree-fold-case-p))
                roots))))

(defun +worktree--counterpart (path from to &optional dir-p)
  "PATH relocated from worktree FROM to worktree TO, or nil if absent there.
Uses `substring' on the truename rather than `file-relative-name', which
can silently produce a \"../..\" escape when the prefix does not match."
  (let* ((true (file-truename path))
         (dest (concat to (substring true (min (length from) (length true))))))
    (and (if dir-p (file-directory-p dest) (file-regular-p dest))
         dest)))

(defun +worktree--dired-dir ()
  "This dired buffer's directory.  `dired-directory' may be (DIR . FILES)."
  (let ((d (if (consp dired-directory) (car dired-directory) dired-directory)))
    (and (stringp d) d)))


;;; Planning

(defun +worktree--plan (from to roots)
  "Return (MOVES . DOOMED) for a switch from FROM to TO.
MOVES is a list of (BUFFER DEST DIR-P); DOOMED is a list of buffers with
no counterpart in TO."
  (let (moves doomed)
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (let* ((dired-dir (and (derived-mode-p 'dired-mode) (+worktree--dired-dir)))
               (path (or buffer-file-name dired-dir default-directory)))
          (when (equal from (+worktree--owner path roots))
            (cond
             (buffer-file-name
              (if-let ((dest (+worktree--counterpart buffer-file-name from to)))
                  (push (list buf dest nil) moves)
                (push buf doomed)))
             (dired-dir
              (if-let ((dest (+worktree--counterpart dired-dir from to t)))
                  (push (list buf dest t) moves)
                (push buf doomed)))
             ;; magit-status, CIDER REPL, compilation, *scratch* rooted here:
             ;; nothing to remap them onto, so they go.
             (t (push buf doomed)))))))
    (cons (nreverse moves) (nreverse doomed))))


;;; Windows

(defun +worktree--remappable-window-p (w)
  "Whether W is an ordinary window we may swap a buffer into.
Popups, treemacs and other side windows are left alone: `set-window-buffer'
resets a window's dedicated flag, which permanently breaks them."
  (and (window-live-p w)
       (not (window-dedicated-p w))
       (not (window-parameter w 'window-side))))

(defun +worktree--windows ()
  "Ordinary windows across all real frames.
Child frames (corfu, lsp-ui-doc, cfrs) are skipped."
  (cl-loop for frame in (frame-list)
           unless (frame-parameter frame 'parent-frame)
           append (seq-filter #'+worktree--remappable-window-p
                              (window-list frame 'no-minibuf))))

(defun +worktree--snapshot ()
  "Record (WINDOW BUFFER POINT-LINE COLUMN START-LINE) for every window.
Line/column, not raw point: the same byte offset means nothing in another
branch's version of a file.  Window-local positions, not buffer `point':
two windows showing one buffer have different points."
  (cl-loop for w in (+worktree--windows)
           collect (with-current-buffer (window-buffer w)
                     (save-excursion
                       (goto-char (window-point w))
                       (let ((line (line-number-at-pos nil t))
                             (col  (current-column)))
                         (goto-char (window-start w))
                         (list w (window-buffer w) line col
                               (line-number-at-pos nil t)))))))

(defun +worktree--position (buf line col)
  "Position in BUF at LINE and COL, clamped to what exists."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- line))
      (move-to-column col)
      (point))))

(defun +worktree--restore (snapshot remap)
  "Swap the buffers in SNAPSHOT's windows for their REMAP counterparts."
  (pcase-dolist (`(,w ,old ,line ,col ,start-line) snapshot)
    (when-let ((new (gethash old remap)))
      (when (window-live-p w)
        (set-window-buffer w new t)
        (set-window-point w (+worktree--position new line col))
        ;; NOFORCE: let redisplay correct an impossible start.
        (set-window-start w (+worktree--position new start-line 0) t)))))


;;; Opening and killing

(defun +worktree--visit (path dir-p)
  "Open PATH, reusing an existing buffer.  Nil if it cannot be opened."
  (condition-case err
      (if dir-p
          (dired-noselect path)
        (or (get-file-buffer path)
            ;; This file was already open in the old worktree, so the size
            ;; warning has effectively been answered already.
            (let ((large-file-warning-threshold nil))
              (find-file-noselect path))))
    (error (message "worktree: cannot open %s: %s"
                    (abbreviate-file-name path) (error-message-string err))
           nil)))

(defun +worktree--kill (buffers)
  "Kill BUFFERS.  Returns the list that could not be killed.
Two things get in the way.  persp-mode installs
`persp-kill-buffer-query-function' on `kill-buffer-query-functions', and
for a buffer that also lives in another workspace it *vetoes* the kill --
returning nil and merely dropping the buffer from the current
perspective.  And a buffer with a live process (CIDER REPL, nrepl server,
compilation) prompts.  Unlink from every perspective first, clear the
process query flag, then kill with the hook suppressed."
  (let (failed)
    (dolist (buf buffers)
      (when (buffer-live-p buf)
        (if (and (buffer-file-name buf) (buffer-modified-p buf))
            ;; Step 1 saved these; if one is still modified the save failed,
            ;; and killing it would discard the user's work.
            (push buf failed)
          (when (bound-and-true-p persp-mode)
            (let (persp-autokill-buffer-on-remove)
              (dolist (p (persp--buffer-in-persps buf))
                (ignore-errors (persp-remove-buffer buf p nil nil nil nil)))))
          (when-let ((proc (get-buffer-process buf)))
            (set-process-query-on-exit-flag proc nil))
          (let ((kill-buffer-query-functions nil))
            (kill-buffer buf))
          (when (buffer-live-p buf) (push buf failed)))))
    failed))



;;; LSP

(defun +worktree--lsp-adopt (root)
  "Register ROOT as its own lsp session folder.

`lsp-find-session-folder' (lsp-mode.el:9691) keeps every registered folder
that is an ancestor of the file and picks the LONGEST.  Only the main repo
is registered by default, so a file in a nested worktree binds to the *main*
checkout's clojure-lsp -- namespaces resolve against the wrong tree, and the
watch covers main's whole directory tree rather than the worktree's own.
Registering the worktree makes it the longer match: its own server, rooted
correctly, watching only its own directories.

Called before the counterpart buffers are opened, so the root is in place by
the time `find-file-noselect' triggers `lsp!'."
  (when (and (featurep 'lsp-mode) (fboundp 'lsp-workspace-folders-add))
    ;; `lsp-workspace-folders-add' prompts only via its `interactive' spec; with
    ;; an argument it just `cl-pushnew'es (tested with `equal', so idempotent)
    ;; and persists. Session folders carry no trailing slash.
    (ignore-errors (lsp-workspace-folders-add (directory-file-name root)))))


;;; Commands

(defun +worktree--read ()
  "Prompt for a worktree of this repo other than the current one."
  (require 'magit)
  (let* ((roots (+worktree--roots))
         (current (+worktree--owner default-directory roots))
         (cands (cl-loop for wt in (magit-list-worktrees)
                         unless (nth 3 wt)
                         when (file-directory-p (car wt))
                         for root = (+worktree--dir (car wt))
                         unless (equal root current)
                         collect (cons (format "%-40s %s"
                                               (file-name-nondirectory
                                                (directory-file-name root))
                                               (or (nth 2 wt)
                                                   (substring (or (nth 1 wt) "") 0 8)))
                                       root))))
    (unless current (user-error "Not inside a git worktree"))
    (unless cands (user-error "This repo has no other worktrees"))
    (cdr (assoc (completing-read "Switch to worktree: " cands nil t) cands))))

;;;###autoload
(defun +worktree/switch (target)
  "Switch to the worktree at TARGET, moving the whole session with it.

Every buffer under the current worktree is re-pointed at the same
relative path in TARGET, keeping the window layout and roughly the same
cursor position.  Modified buffers are saved first.  Buffers with no
counterpart in TARGET -- files that exist only on the other branch, and
magit/REPL/compilation buffers rooted in the old worktree -- are killed."
  (interactive (list (+worktree--read)))
  (let* ((roots (+worktree--roots))
         (from (+worktree--owner default-directory roots))
         (to (+worktree--dir target)))
    (unless from (user-error "Not inside a git worktree"))
    (unless (member to roots) (user-error "%s is not a worktree of this repo" to))
    (when (equal from to) (user-error "Already in %s" (abbreviate-file-name to)))

    ;; 1. Save, so nothing is stranded in the worktree we are leaving.
    (let ((inhibit-message t))
      (save-some-buffers
       t (lambda () (and buffer-file-name
                    (equal from (+worktree--owner buffer-file-name roots))))))

    ;; 2. Give the target its own lsp root before any of its files are opened.
    (+worktree--lsp-adopt to)

    (pcase-let* ((`(,moves . ,doomed) (+worktree--plan from to roots))
                 (snapshot (+worktree--snapshot))
                 (remap (make-hash-table :test #'eq)))
      ;; 3. Open every counterpart BEFORE touching any window, so no window
      ;;    ever has to fall back to a replacement buffer.
      (pcase-dolist (`(,buf ,dest ,dir-p) moves)
        (if-let ((new (+worktree--visit dest dir-p)))
            (puthash buf new remap)
          ;; Couldn't open it -- keep the original rather than lose it.
          (setq doomed (delq buf doomed))))
      ;; 4. Swap windows over, then kill the originals.
      (+worktree--restore snapshot remap)
      (let* ((replaced (cl-loop for b being the hash-keys of remap collect b))
             (failed (+worktree--kill (append replaced doomed)))
             (moved (- (hash-table-count remap) (length failed))))
        ;; 5. Leave the user somewhere sensible.
        (let ((b (window-buffer (selected-window))))
          (if (buffer-live-p b)
              (set-buffer b)
            (dired to)))
        (when (zerop (hash-table-count remap))
          (dired to))
        (message "Worktree %s → %s: %d moved, %d killed%s"
                 (file-name-nondirectory (directory-file-name from))
                 (file-name-nondirectory (directory-file-name to))
                 moved
                 (- (length doomed) (length failed))
                 (if failed
                     (format ", %d LEFT BEHIND (%s)" (length failed)
                             (mapconcat #'buffer-name failed ", "))
                   ""))))))


;;; Modeline

;; doom-modeline's `vcs' segment already shows a bare "WT" badge when the file
;; is in a linked worktree, but never says *which* -- and shows nothing at all
;; in the main checkout. Show the worktree's directory name instead, just left
;; of the branch. `doom-modeline--project-root' is already `defvar-local'-cached
;; per buffer and resolves via projectile, which finds the nearest .git (a plain
;; file in a linked worktree) and so returns the worktree root, not the repo
;; root. Never call `magit-toplevel' from a segment: it shells out to git, and
;; segments run on every redisplay.
(after! doom-modeline
  (doom-modeline-def-segment worktree
    "Directory name of the current worktree."
    (when-let ((root (doom-modeline--project-root)))
      (concat (doom-modeline-spc)
              (propertize (concat "⑂ " (file-name-nondirectory
                                        (directory-file-name root)))
                          'face (doom-modeline-face 'doom-modeline-project-dir)
                          'help-echo root))))
  ;; Must run after the segment exists: `doom-modeline-add-segment' rebuilds the
  ;; modeline and errors on an undefined segment.
  (doom-modeline-add-segment 'worktree 'vcs :before))

(map! :leader :desc "Switch worktree (move buffers)" "g w" #'+worktree/switch)

(provide 'worktree)
;;; worktree.el ends here
