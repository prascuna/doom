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

;; `diff-hl-show-hunk-mouse-mode' is buffer-local, so enabling it once at load
;; time only affects whichever buffer happened to be current. Use the globalized
;; variant, which turns it on in every existing buffer *and* every future one.
(after! diff-hl
  (global-diff-hl-show-hunk-mouse-mode +1))
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
  ;; (node_modules, .git etc. are already in lsp-mode's default list.)
  (setq lsp-file-watch-threshold 10000)
  (dolist (dir '("[/\\\\]target\\'"
                 "[/\\\\]\\.clj-kondo/\\.cache\\'"
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

;; Metabase settings ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(add-to-list 'exec-path (expand-file-name "~/.local/share/mise/shims"))
(setenv "PATH" (concat (expand-file-name "~/.local/share/mise/shims") ":" (getenv "PATH")))

