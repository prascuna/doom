;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-one)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")


;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `with-eval-after-load' block, otherwise Doom's defaults may override your
;; settings. E.g.
;;
;;   (with-eval-after-load 'PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look them up).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.
;;
;; Paolo's settings ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(map! :m "H" #'evil-first-non-blank
      :m "L" #'evil-end-of-line)

(setq evil-escape-key-sequence "kj"
      evil-escape-delay 0.2)

(define-key key-translation-map (kbd "s-j") (kbd "<down>"))
(define-key key-translation-map (kbd "s-k") (kbd "<up>"))
(define-key key-translation-map (kbd "s-h") (kbd "<left>"))
(define-key key-translation-map (kbd "s-l") (kbd "<right>"))

;; IntelliJ's Navigate Back/Forward. Aliases for `C-o'/`C-i', which Doom remaps
;; onto better-jumper; the jump list holds markers, so these cross files, and
;; `+lookup/definition' (gd) records its origin, making gd -> s-[ a round trip.
;; Bound globally rather than per-evil-state so they also work mid-insert and in
;; non-evil buffers (magit, dired), the way a Cmd chord is expected to.
(map! "s-[" #'better-jumper-jump-backward
      "s-]" #'better-jumper-jump-forward)

(defun +diff-hl-show-hunk-fn (buffer &optional line)
  "Show the hunk in BUFFER in a child frame, falling back to an inline popup.
`diff-hl-show-hunk-posframe' hard-errors on a TTY, so dispatch at call time
rather than baking `display-graphic-p' in at startup (emacsclient -nw)."
  (if (and (display-graphic-p)
           (require 'posframe nil t)
           (posframe-workable-p))
      (diff-hl-show-hunk-posframe buffer line)
    (diff-hl-show-hunk-inline buffer line)))

;; `diff-hl-show-hunk-mouse-mode' is buffer-local, so enabling it once at load
;; time only affects whichever buffer happened to be current. Use the globalized
;; variant, which turns it on in every existing buffer *and* every future one.
(after! diff-hl
  (global-diff-hl-show-hunk-mouse-mode +1)

  ;; FIX: Doom sets `diff-hl-update-async' to 'thread on Emacs <=30, but on this
  ;; NS build every update thread hangs forever. diff-hl forces the git call to
  ;; be *synchronous* when `window-system' is ns (its own workaround for
  ;; debbugs#78946), and a blocking subprocess inside a Lisp thread never returns
  ;; here -- measured in a GUI frame: with 'thread the overlay is never set and
  ;; the `diff-hl--update-safe' thread is still alive minutes later; with nil the
  ;; same update lands in ~30ms and repaints. (A running session had accumulated
  ;; three stuck threads.) This is the real doomemacs/core#8554 symptom, and it
  ;; silently swallowed every gutter update, flydiff's included. Cost of running
  ;; on the main thread: 20-60ms for a file in the metabase repo, incurred only
  ;; after you have already paused for `diff-hl-flydiff-delay'.
  (setq diff-hl-update-async nil)

  ;; Without `diff-hl-flydiff-mode' the gutter diffs HEAD against the file *on
  ;; disk*, so a change only surfaces once super-save writes the buffer -- 5s of
  ;; idle. `:ui vc-gutter' skips flydiff on macOS over doomemacs/core#8554; with
  ;; the thread hang above out of the way, on-the-fly diffing behaves here, so opt
  ;; back in. NOTE: enabling the mode bakes `diff-hl-flydiff-delay' into an
  ;; idle timer, so the delay has to be set first. Enabling it also fires
  ;; vc-gutter's `+vc-gutter-init-flydiff-mode-h', which hangs
  ;; `diff-hl-flydiff-update' off `evil-insert-state-exit-hook' -- the bar then
  ;; also appears the instant you leave insert state.
  (setq diff-hl-flydiff-delay 0.2)  ; Doom sets 0.5, upstream default is 0.3
  (diff-hl-flydiff-mode +1)

  ;; The default inline backend sizes its popup to the number of *deleted* lines
  ;; in the hunk, so a one-line edit yields a one-line window you scroll a row at
  ;; a time. A posframe renders the whole hunk in a child frame auto-fitted to
  ;; its content (flipping above point when there's no room below), floating over
  ;; the buffer rather than pushing text down, with a header line of
  ;; Close/Prev/Next/Revert/Stage buttons.
  (setq diff-hl-show-hunk-function #'+diff-hl-show-hunk-fn
        diff-hl-show-hunk-posframe-internal-border-width 2)
  ;; Its border colour defaults to a hard-coded #00ffff; borrow the theme's.
  (add-hook! 'doom-load-theme-hook :append
    (defun +diff-hl-posframe-border-h ()
      (setq diff-hl-show-hunk-posframe-internal-border-color
            (let ((c (face-attribute 'vertical-border :foreground nil t)))
              (if (stringp c) c "#5B6268")))))
  (+diff-hl-posframe-border-h))
(map! :leader :desc "Show hunk at point" "g h" #'diff-hl-show-hunk)
;; Eric Dallo https://gist.github.com/ericdallo/09217734a925148976e13b872b91e134
(setq read-process-output-max (* 1024 1024)
      ;; doom-localleader-key "," ;; easier than <SPC m>
      ;; doom-font (font-spec :family "JetBrainsMono Nerd Font Mono" :size 18) ;; Make sure to use a font you have installed
      ;; doom-theme 'doom-dracula
      projectile-project-search-path '("~/Documents/workspace") ;; Change this to your base path for projects
      projectile-enable-caching nil)

(add-to-list 'default-frame-alist '(fullscreen . maximized))

;; Emacs packs lines tighter than IntelliJ, which uses a 1.2 line height. A float
;; `line-spacing' adds that fraction of the line height below every line; 0.15
;; lands close to IntelliJ once Emacs' own font leading is counted, and scales
;; automatically with `doom-font' size and `doom-big-font-mode'.
(setq-default line-spacing 0.15)

;; macOS' default is Menlo 12; 13 is one notch up without the jump you get from
;; `doom/increase-font-size', which steps by `doom-font-increment' (2) at a time.
;; Drop that to 1 so `SPC =' style adjustments are fine-grained too.
(setq doom-font (font-spec :family "Menlo" :size 13)
      doom-font-increment 1)

(after! lsp-mode
  (setq lsp-semantic-tokens-enable t)
  (add-hook 'lsp-after-apply-edits-hook (lambda (&rest _) (save-buffer))) ;; save buffers after renaming

  ;; Metabase is huge; keep lsp-mode's file watcher from choking on it.
  ;; (node_modules, .git, target, .clj-kondo etc. are already in lsp-mode's
  ;; default list -- `lsp-file-watch-ignored-directories' is matched against each
  ;; directory's absolute path as the tree is walked.)
  (setq lsp-file-watch-threshold 10000)
  (dolist (dir '(;; The worktrees live *inside* the main checkout
                 ;; (<repo>/.claude/worktrees/<branch>) and each is a full
                 ;; checkout, so from the main root they are ~20,000 of the
                 ;; ~25,600 directories lsp would watch -- over the threshold
                 ;; above, hence the "watch all files?" prompt. That prompt's
                 ;; answer is never persisted, so it returns on every restart;
                 ;; pruning is the only real fix. Leaves ~5,200.
                 ;;
                 ;; This one entry also scopes the *other* direction: the walk
                 ;; in `lsp--all-watchable-directories' seeds its stack with the
                 ;; root and never ignore-tests it, so from inside a worktree
                 ;; (which has no .claude/worktrees of its own) only that
                 ;; worktree is watched.
                 "[/\\\\]\\.claude[/\\\\]worktrees\\'"
                 "[/\\\\]resources[/\\\\]frontend_client\\'"))
    (add-to-list 'lsp-file-watch-ignored-directories dir)))

;; Doom's `(clojure +lsp)` hands completion/eldoc/navigation entirely to
;; clojure-lsp. Undo that: CIDER's capf/eldoc/lookup no-op when there's no REPL,
;; so keeping both in the chain means CIDER wins while connected and LSP
;; transparently covers everything else.
(after! cider
  (remove-hook 'cider-mode-hook #'+clojure--cider-disable-completion)
  (setq cider-eldoc-display-for-symbol-at-point t)
  (set-lookup-handlers! '(cider-mode cider-repl-mode)
    :definition    #'+clojure-cider-lookup-definition
    :documentation #'cider-doc))

;; lsp-mode starts from `clojure-mode-local-vars-hook', which runs *after*
;; `clojure-mode-hook' where `cider-mode' turns on. Both push onto the front of
;; the capf/lookup lists, so LSP would otherwise always end up first. Re-assert
;; the order from whichever side happens to start last.
(defun +clojure--prioritize (var fn)
  (when (memq fn (symbol-value var))
    (set (make-local-variable var) (cons fn (remq fn (symbol-value var))))))

(defun +clojure-cider-first-h ()
  "Rank CIDER ahead of clojure-lsp for completion, docs and navigation.
CIDER's handlers return nil (or error) without a REPL, and Doom's
`+lookup--run-handlers' falls through on error, so LSP still answers
whenever no REPL is connected."
  (when (bound-and-true-p cider-mode)
    (+clojure--prioritize 'completion-at-point-functions #'cider-complete-at-point)
    (+clojure--prioritize '+lookup-definition-functions #'+clojure-cider-lookup-definition)
    (+clojure--prioritize '+lookup-documentation-functions #'cider-doc)))

(add-hook 'cider-mode-hook #'+clojure-cider-first-h 'append)
(add-hook 'lsp-mode-hook #'+clojure-cider-first-h 'append)
(add-hook 'lsp-completion-mode-hook #'+clojure-cider-first-h 'append)

;; Save automatically instead of formatting automatically: `:editor format' no
;; longer carries +onsave, so reformatting is a deliberate `SPC c f'. super-save
;; writes the buffer at natural pauses (window/buffer switch, losing focus) plus
;; a short idle timer, so `:w' becomes unnecessary without hammering
;; clojure-lsp's didSave on every keystroke pause.
(use-package! super-save
  :hook (doom-first-file . super-save-mode)
  :config
  (setq super-save-auto-save-when-idle t
        super-save-idle-duration 5
        ;; Saves are constant now; don't echo "Wrote ..." over everything else.
        super-save-silent t
        ;; Saving over TRAMP on a timer will freeze Emacs on a slow link.
        super-save-remote-files nil)
  ;; NOTE: `super-save-triggers' is deliberately left empty. Since 0.5.0 the
  ;; defaults `super-save-when-buffer-switched' and `super-save-when-focus-lost'
  ;; hook `window-selection-change-functions' and `after-focus-change-function',
  ;; which already catch every evil/Doom window motion regardless of command.
  )

;; Magit ships `magit-insert-worktrees' but leaves it out of
;; `magit-status-sections-hook', so worktrees are invisible in `SPC g g'. Slot it
;; in right after the status headers: it's repo-level information, and it inserts
;; nothing at all when the repo has only one worktree, so ordinary repos are
;; unaffected. RET visits a worktree, k deletes it (`magit-worktree-section-map').
(after! magit
  (magit-add-section-hook 'magit-status-sections-hook
                          #'magit-insert-worktrees
                          #'magit-insert-status-headers
                          'append))

;; `magit-worktree-status' completes over `magit-list-worktrees' (minus the
;; current one), so it doubles as a list-and-jump command. Unlike the
;; `magit-worktree' transient it carries no autoload cookie, so declare one.
(autoload 'magit-worktree-status "magit-worktree" nil t)
(map! :leader :desc "List worktrees" "g l w" #'magit-worktree-status)

;; `+worktree/switch' (SPC g w) goes further: it moves every open buffer to the
;; same relative path in the target worktree, keeping the window layout, and
;; adds a modeline segment naming the worktree you are in.
(load! "worktree")

;; Metabase settings ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(add-to-list 'exec-path (expand-file-name "~/.local/share/mise/shims"))
(setenv "PATH" (concat (expand-file-name "~/.local/share/mise/shims") ":" (getenv "PATH")))

