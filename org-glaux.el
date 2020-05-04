;;; org-glaux.el --- Desktop wiki extension for org-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2020 Firmin Martin

;; Author: Firmin Martin
;; Maintainer: Firmin Martin
;; Version: 0.1
;; Keywords: outlines, files, convenience
;; URL: https://www.github.com/firmart/org-glaux'
;; Package-Requires: ((cl-lib "0.5") (emacs "25.1") (org "9.0"))


;; This program is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of
;; the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Org-glaux is an org-mode extension that provides tools to manage and
;; build a desktop wiki where each wiki page is an org-mode file.

;; external libraries
(require 'org)
(require 'ox-html)

;; built-in Emacs lib
(require 'cl-lib)     ;; Common-lisp emulation library
(require 'easymenu)
(require 'subr-x)     ;; Provides string trim functions.

;;; Code:
;;; Custom group
;;;; General settings

(defgroup org-glaux nil
  "Org-glaux Settings"
  :group 'tools)

(defcustom org-glaux-location-list '("~/org/wiki")
  "List of org-glaux root directories."
  :type  '(repeat directory)
  :group 'org-glaux)

(defvar org-glaux-location nil
  "Current wiki directory.  If nil, set it to the CAR of `org-glaux-location-list' in runtime.")

(defvar org-glaux--page-history nil "Stack of wiki pages visited.")

(defcustom org-glaux-default-read-only nil
  "If this variable is non-nil all org-glaux pages will be read-only by default.
You can toggle read-only mode with \\<read-only-mode>."
  :type  'boolean
  :group 'org-glaux)

(defcustom org-glaux-close-root-switch t
  "If set, all org-glaux pages are closed when root directory is switched.
\(Default value: true)"
  :type  'boolean
  :group 'org-glaux)

(defcustom org-glaux-template
  (string-trim
   "
#+OPTIONS: d:nil tags:nil todo:nil toc:t ^:nil
#+TITLE: %n
#+DESCRIPTION:
#+KEYWORDS:
#+STARTUP:  overview
#+DATE: %d
")
  "Default template used to create org-glaux pages/files.
- %n - is replaced by the page name.
- %d - is replaced by current date in the format year-month-day."

  :type 'string
  :group 'org-glaux)

;; Default index page (index.org) accessed with M-x org-glaux-index
(defvar org-glaux-index-file-basename "index")

;;;; Python webserver settings
(defcustom org-glaux-server-port "8000"
  "Default port to server org-glaux static files server."
  :type  'string
  :group 'org-glaux)

(defcustom org-glaux-server-host "0.0.0.0"
  "Default address that the server listens to."
  :type  'string
  :group 'org-glaux)

;;;; Async export settings
(defcustom org-glaux-emacs-path "emacs"
  "Path to Emacs executable.  Default value 'Emacs'."
  :type 'file
  :group 'org-glaux)


;; Additional publishing options
(defcustom org-glaux-publish-plist '()
  "Additional options passed to `org-publish'."
  :type 'plist
  :group 'org-glaux)


;;;; Backup settings
(defcustom org-glaux-backup-location nil
  "Path to backup directory."
  :type 'directory
  :group 'org-glaux)

;;; Interactive functions
;;;; Backup
(defun org-glaux-backup ()
  "Make a org-glaux backup."
  (interactive)
  (let* ((zipfile            (concat "org-glaux-" (format-time-string "%Y-%m-%d") ".zip"))
         (destfile           (concat (file-name-directory org-glaux-backup-location) zipfile))
         (default-directory  org-glaux-location))
    (switch-to-buffer "*org-glaux-backup*")

    ;; Crate org-glaux backup location directory if doesn't exist.
    (if (not (file-exists-p org-glaux-backup-location))
        (make-directory org-glaux-backup-location t))

    (if (file-exists-p destfile) (delete-file destfile))
    (if (file-exists-p zipfile)  (delete-file zipfile))

    ;; Clear buffer removing all lines
    (delete-region (point-min) (point-max))
    (set-process-sentinel
     (start-process
      "org-glaux-backup" ;; Process name
      "*org-glaux-backup*" ;; Buffer where output is displayed.
      ;; Shell command
      "zip" "-r" "-9" zipfile ".")
     (lexical-let ((zipfile  zipfile)
                   (destfile destfile))
       (lambda (process)
         (when (equal (process-exit-status process) 0)
           (switch-to-buffer "*org-glaux-backup*")
           (rename-file zipfile org-glaux-backup-location t)
           (message "Backup done.")
           (insert  "\nBackup done.  Run M-x org-glaux-backup-dir to open backup directory.")))))))

;;;; Close
(defun org-glaux-close-images ()
  "Close all image/picture buffers which files are in org-glaux directory."
  (interactive)
  (mapc (lambda (b)
          (with-current-buffer b
            (when (and (org-glaux--is-buffer-in b)
		       (equal major-mode 'image-mode))
              (kill-this-buffer))))
        (buffer-list))
  (message "All wiki images closed."))

(defun org-glaux-close-pages ()
  "Close all opened wiki pages buffer and save them."
  (interactive)
  (mapc (lambda (b)
          (with-current-buffer b
            (when (org-glaux--is-buffer-in b)
              ;; save the buffer if it is bound to a file
              ;; and it is not read-only
              (when (and (buffer-file-name b)
			 (not buffer-read-only))
                (save-buffer))
              (kill-this-buffer))))
        (buffer-list))
  (message "All wiki files closed."))

;;;; Dired
(defun org-glaux-dired-assets ()
  "Open the asset directory of current wiki page."
  (interactive)
  (let ((pagename (org-glaux--current-page-name)))
    ;; TODO check if it is a wiki-page
    (org-glaux--assets-make-dir pagename)
    (dired (org-glaux--assets-get-dir buffer-file-name))))

(defun org-glaux-dired-backup ()
  "Open org-glaux backup directory in dired mode."
  (interactive)
  ;; Create org-glaux backup location directory if doesn't exist.
  (if (not (file-exists-p org-glaux-backup-location))
      (make-directory org-glaux-backup-location t))
  ;; Open backup location
  (dired org-glaux-backup-location)
  ;; Update buffer
  (revert-buffer))

(defun org-glaux-dired-files ()
  "Show all wiki files in all sub-directories of `org-glaux-location'."
  (interactive)
  (find-dired org-glaux-location "-name '*.org'"))

;;;; Export
(defun org-glaux-export-as (org-exporter)
  "Export all pages to a given format.
ORG-EXPORTER is a function that exports an `org-mode' page to a specific format
like html.  It can be for instance:

`org-html-publish-to-html',`org-latex-publish-to-pdf',
`org-latex-publish-to-latex', etc.

WARN: This is a synchronous function and can freeze Emacs.  Emacs will freeze
while the exporting doesn't finish.  Type \\<keyboard-quit> to abort the
execution."
  (interactive)
  (let ((org-html-htmlize-output-type "css")
        (org-html-htmlize-font-prefix "org-")
        (pub-plist (org-glaux--make-org-publish-plist org-exporter)))
    (org-publish pub-plist t)))

(defun org-glaux-export-html-async ()
  "Export all pages to html in asynchronous mode."
  (interactive)
  (let ((org-html-htmlize-output-type "css")
	(org-html-htmlize-font-prefix "org-"))
    (org-publish (org-glaux--make-org-publish-plist 'org-html-publish-to-html) t t)))

(defun org-glaux-export-html-page ()
  "Export the current wiki page to html and opens it in the browser."
  (interactive)
  (org-html-export-to-html)
  (browse-url (org-glaux--replace-extension buffer-file-name "html")))

(defun org-glaux-export-html-sync ()
  "Export all pages to html in synchronous mode."
  (interactive)
  (let ((org-html-htmlize-output-type "css")
        (org-html-htmlize-font-prefix "org-"))
    (org-publish (org-glaux--make-org-publish-plist 'org-html-publish-to-html)
		 t)))

;;;; Index
(defun org-glaux-index ()
  "Open the index page: <org-glaux-location>/index.org.

The page is created if it doesn't exist."
  (interactive)
  (org-glaux--init-location)
  (org-glaux--wiki-follow org-glaux-index-file-basename))

(defun org-glaux-index-frame ()
  "Open the index page in a new frame."
  (interactive)
  (with-selected-frame (make-frame)
    (org-glaux-index)))

(defun org-glaux-index-html ()
  "Open the Wiki (Index) in the default web browser."
  (interactive)
  (browse-url (concat "file://"
		      (org-glaux--page->html-file
		       org-glaux-index-file-basename))))

;;;; Insert
(defun org-glaux-insert-asset ()
  "Insert at point a file link to a current page's asset file.
The link type file is opened with Emacs."
  (interactive)
  (org-glaux--assets-select
   (lambda (file)
     (insert (if (fboundp 'org-link-make-string)
		 (org-link-make-string (format "file:%s/%s" (org-glaux--current-page-name) (file-name-nondirectory file)) (read-string "Description: " (file-name-nondirectory file)))
	       (org-make-link-string (format "file:%s/%s" (org-glaux--current-page-name) (file-name-nondirectory file)) (read-string "Description: " (file-name-nondirectory file))) ;; obsolete since org 9.3
	       (file-name-nondirectory file))))))

(defun org-glaux-insert-download ()
  "Download a file from a URL in the clibpoard and insert a link file link.
Note: This function is synchronous and blocks Emacs."
  (interactive)
  (org-glaux--assets-download-hof
   (lambda (output-file)
     (save-excursion (insert (format "[[file:%s/%s][%s]]"
				     (org-glaux--current-page-name) output-file output-file))))))

(defun org-glaux-insert-new-link ()
  "Create a new wiki page and insert a link to it at point."
  (interactive)
  (let ((page-name (read-string  "Page: ")))
    (save-excursion (insert (if (fboundp 'org-link-make-string)
				(org-link-make-string (concat "wiki:" page-name))
			      (org-make-link-string (concat "wiki:" page-name)) ;; obsolete since org 9.3
			      page-name)))))

(defun org-glaux-insert-select-link ()
  "Insert a Wiki link at point for a existing page."
  (interactive)
  (org-glaux--select
   (lambda (wiki-path)
     (insert (org-glaux--make-link wiki-path)))))

;;;; Miscellaneous
(defun org-glaux-help ()
  "Show org-glaux commands."
  (interactive)
  (command-apropos "org-glaux-"))

(defun org-glaux-menu-enable ()
  "Build a menu for org-glaux."
  (interactive)
  (easy-menu-define org-glaux-menu global-map "Org-glaux"
    (list "org-glaux"
	  (org-glaux--easy-menu-entry "Backup" "org-glaux-backup")
	  (org-glaux--easy-menu-entry "Close" "org-glaux-close")
	  (org-glaux--easy-menu-entry "Dired" "org-glaux-dired")
	  (org-glaux--easy-menu-entry "Export" "org-glaux-export")
	  (org-glaux--easy-menu-entry "Index" "org-glaux-index")
	  (org-glaux--easy-menu-entry "Insert" "org-glaux-insert")
	  (org-glaux--easy-menu-entry "Navigation" "org-glaux-navi")
	  (org-glaux--easy-menu-entry "Search" "org-glaux-search")
	  (org-glaux--easy-menu-entry "Select" "org-glaux-select")
	  (org-glaux--easy-menu-entry "Server" "org-glaux-server")
	  ["---" nil]
	  (list "Miscellaneous"
		(vector (documentation 'org-glaux-new-page) 'org-glaux-new-page)
		(vector (documentation 'org-glaux-website) 'org-glaux-website)))))

(defun org-glaux-new-page ()
  "Create a new wiki page and open it without inserting a link."
  (interactive)
  (org-glaux--wiki-follow (read-string "Page Name: ")))

(defun org-glaux-website ()
  "Open org-glaux github repository."
  (interactive)
  (browse-url "https://firmart.github.io/org-glaux"))

;;;; Navigation
(defun org-glaux-navi-back ()
  "Navigate back to the previous wiki page in the history.

- Skip previous page which doesn't exist until found an existing one.
- If there is no wiki page in the history, come back to the index page."
  (interactive)
  (let ((prev-page (pop org-glaux--page-history)))
    (while (not (and prev-page (file-exists-p prev-page)))
      (setq prev-page (pop org-glaux--page-history))
      (unless prev-page
	(org-glaux--init-location)
	(setq prev-page (org-glaux--page->file org-glaux-index-file-basename))))
    (find-file prev-page)))

;;;; Search
(defun org-glaux-search-regex (pattern)
  "Search all wiki pages that contain a PATTERN (regexp or name)."
  (interactive "sorg-glaux - Search for: ")
  (grep-compute-defaults) ;; Set up grep-find-command
  (rgrep pattern "*.org" org-glaux-location))
;;;; Select
(defun org-glaux-select-asset ()
  "Open in Emacs a selected asset file of the current page from a menu."
  (interactive)
  (org-glaux--assets-select #'org-open-file))

(defun org-glaux-select-assets-dired ()
  "Select and open with dired the assets directory of a wiki page."
  (interactive)
  (org-glaux--select
   (lambda (page)
     (org-glaux--assets-make-dir page)
     (dired (org-glaux--assets-get-dir page)))))

(defun org-glaux-select-buffer ()
  "Switch between org-glaux page buffers."
  (interactive)
  (let ((target (completing-read "Wiki pages:"
				 (mapcar (lambda (b) (org-glaux--file-wiki-path (buffer-file-name b)))
					 (org-glaux--get-buffers))))
	(action 'org-glaux--wiki-follow))
    (funcall action target)))

(defun org-glaux-select-frame ()
  "Select a wiki page and open it in a new frame."
  (interactive)
  (org-glaux--select  (lambda (act)
			(with-selected-frame (make-frame)
			  (set-frame-name (concat "Org-glaux: " act))
			  (org-glaux--wiki-follow act)))))

(defun org-glaux-select-html ()
  "Select a wiki page and open it in html.

The html page is created if it doesn't exist yet."
  (interactive)
  (let ((target (completing-read "Wiki pages:" (org-glaux--page-files)))
	(action
	 (lambda (fpath)
	   (let ((html-file   (org-glaux--replace-extension fpath "html")))
	     (if (not (file-exists-p html-file))
		 (with-current-buffer (find-file fpath)
		   (org-html-export-to-html)))
	     (browse-url html-file)))))
    (funcall action target)))

(defun org-glaux-select-page ()
  "Select and open a wiki page."
  (interactive)
  (org-glaux--select #'org-glaux--wiki-follow))

(defun org-glaux-select-root ()
  "Switch org-glaux root directory."
  (interactive)
  (let ((target (completing-read "Org-glaux root directories:" org-glaux-location-list))
	(action
	 (lambda (p)
	   ;; If the selected wiki is the same, no need to erase navigation history
	   (unless (eq p org-glaux-location)
	     ;; Close all current org-glaux pages if custom value set
	     (when org-glaux-close-root-switch
	       (org-glaux-close-pages)
	       (message (format "Org-glaux pages under directory %s are saved" org-glaux-location)))
	     (setq org-glaux--page-history nil) ;; clean history of the previous wiki
	     (setq org-glaux-location p)
	     (org-glaux-index)
	     (message (format "Org-glaux root directory set to: %s" p))))))
    (funcall action target)))
;;;; Server

;; Despite this function was implemented as a interface to
;; Python3 simple http server, it can be refactored to work
;; with another more powerful http server such as Nginx.

(defun org-glaux-server-toggle ()
  "Start/stop org-glaux http server.  It requires Python3.
Note: This command requires Python3 installed."
  (interactive)
  (let (;; Process name
        (pname  "org-glaux-server")
        ;; Buffer name - Display process output (stdout)
        (bname   "*org-glaux-server*")
        ;; Set current directory to org-glaux repository.
        (default-directory org-glaux-location))
    (if (not (get-buffer bname))
        (progn
          (sit-for 0.1)
          (switch-to-buffer bname)
          (save-excursion ;; Save cursor position
	    (insert "Server started ...\n\n")
	    (message "\nServer started ...\n"))
          (start-process pname
                         bname
                         "python3"
                         "-m"
                         "http.server"
                         "--bind"
                         org-glaux-server-host
                         org-glaux-server-port)
          (when (y-or-n-p "Open server in browser ? ")
            (browse-url (format "http://localhost:%s" org-glaux-server-port))))
      (progn  (switch-to-buffer bname)
	      (kill-process (get-process pname))
	      (message "Server stopped.")))))

(provide 'org-glaux)
;;; Internal functions
;;;; Internal -- Download
(defun org-glaux--assets-download-hof (callback)
  "Higher order function to download a file.

CALLBACK is a function with this signature: (callback <filename>)

This function works as follows:
1. Ask the user for the URL (suggested URL comes from the clipboard).
2. Ask the user for the filename to be downloaded (suggested filename comes from
the URL).
3. Call the callback function passing the current page name and the file name."
  (let* ;; Get the URL suggestion from clibpoard
      ((text (with-temp-buffer
	       (clipboard-yank)
	       (buffer-substring-no-properties (point-min)
					       (point-max))))
       (url (read-string "Url: " text))
       (default-directory (org-glaux--assets-get-dir buffer-file-name))

       (output-file  (read-string "File name: "
				  (car  (last (split-string url "/"))))))

    (org-glaux--assets-make-dir buffer-file-name)
    (url-copy-file url output-file)
    (funcall callback output-file)))

;;;; Internal -- Initialization
(defun org-glaux--insert-header ()
  "Insert a header at the top of the file."
  ;; Save current cursor location and restore it
  ;; after completion of block insider save-excursion.
  (save-excursion
    (let*
	;; replace '%n' by page title
	((text1 (replace-regexp-in-string
		 "%n"
		 (org-glaux--current-page-name)
		 org-glaux-template))
	 ;; Replace %d by current date in the format %Y-%m-%d
	 (text2 (replace-regexp-in-string
		 "%d"
		 (format-time-string "%Y-%m-%d")
		 text1)))
      ;; Got to top of file
      (goto-char (point-min))
      (insert text2))))

(defun org-glaux--init-location ()
  "Initialize `org-glaux-location' variable if not set yet."
  (if (not org-glaux-location)
      (let ((fst-loc (car org-glaux-location-list)))
	(unless (or org-glaux-location-list (file-exists-p fst-loc))
	  (error (format "`org-glaux-location-list' is nil or it contains non-existent directory '%s'" fst-loc)))
	(setq org-glaux-location fst-loc))))

;;;; Internal -- Wiki Link
(defun org-glaux--make-link (wiki-path)
  "Return a string containing a wiki link [[wiki:WIKI-PATH][TITLE]].
Argument WIKI-PATH: the link which is a wiki-path."
  (format "[[wiki:%s][%s]]"
	  wiki-path
	  (org-glaux--global-prop-value (org-glaux--page->file wiki-path) "TITLE")))

(defun org-glaux--wiki-follow (wiki-path)
  "Open or create if it doesn't exist an org-glaux page given its WIKI-PATH.

It pushes current wiki buffer into history so that `org-glaux-navi-back' can
come back to it."
  (let ((page-fpath (org-glaux--page->file wiki-path)))
    ;; push current file in page history stack
    (when (org-glaux--is-buffer-in (current-buffer))
      (push buffer-file-name org-glaux--page-history))
    (if (file-exists-p page-fpath)
	;; if the page exists, open it
	(progn (find-file page-fpath)
	       (when org-glaux-default-read-only (read-only-mode t)))
      ;; if the page doesn't exist, create it
      (find-file page-fpath)
      (org-glaux--insert-header)
      (save-buffer)
      (org-glaux--assets-make-dir page-fpath))))

(defun org-glaux--wiki-export (wiki-path desc format)
  "Export a wiki page WIKI-PATH from Org files.
Argument DESC wiki link description.
Argument FORMAT format to export."
  (cl-case format
    (html (format "<a href='%s'>%s</a>" (file-relative-name (org-glaux--page->html-file wiki-path) ".") (or desc wiki-path)))
    (ascii (format "%s (%s)" (or desc wiki-path) wiki-path))
    (latex (format "\\href{%s}{%s}"
		   (file-relative-name
		    (expand-file-name wiki-path org-glaux-location) ".")
		   (or desc wiki-path)))))

;;;; Internal -- List
(defun org-glaux--assets-page-files (dirpath)
  "Return all asset files from a given page's asset DIRPATH."
  (org-glaux--assets-make-dir dirpath)
  (let* ((dir-files (directory-files dirpath nil
				     ;; exclude ".", "..", "ltximg"
				     "^\\([^.]\\|\\.[^.]\\|\\.\\..\\|ltximg\\)"))
	 (org-files (directory-files dirpath nil "\\.org$")))
    (cl-remove-if
     (lambda (f) (or (file-directory-p ;; remove directories
		(expand-file-name f dirpath))
	       (some
		(lambda (org-file)
		  ;; remove suffix or prefix of children org-file name
		  (or (string-prefix-p (file-name-base org-file) f)
		     ;; exclude auto-generated latex dirs such as _minted-<page-name>
		     (string-suffix-p (file-name-base org-file) f)))
		org-files)))
     dir-files)))

(defun org-glaux--get-buffers ()
  "Return all org-glaux page buffers filename under `org-glaux-location`."
  (org-glaux--init-location)
  (cl-remove-if-not
   (lambda (buffer)
     (let* ((fp (buffer-file-name buffer))
	    (fpath (if fp (expand-file-name fp))))
       ;; test if file exists
       (and  fpath
	   ;; test if buffer file is under current wiki location
	   (string-prefix-p (expand-file-name org-glaux-location) fpath)
	   ;; test if buffer file has extension .org
	   (string-suffix-p ".org" fpath))))
   (buffer-list)))

(defun org-glaux--page-files ()
  "Return a list containing all wiki-pages under `org-glaux-location`."
  (org-glaux--init-location)
  (cl-remove-if
   (lambda (f)
     (let ((b (file-name-base f)))
       (or (string-prefix-p ".#" b)
	  (string-suffix-p "~"  b)
	  (string-prefix-p "#"  b)
	  (string-suffix-p "#"  b))))
   (directory-files-recursively org-glaux-location "\\.org$")))

(defun org-glaux--wiki-face (wiki-path)
  "Dynamic face for file links."
  (let ((fpath (org-glaux--page->file wiki-path)))
    (unless (file-remote-p fpath) ;; Do not connect to remote files
      (if (file-exists-p fpath)
          'org-link
	;; file link broken
        'org-warning))))

(defun org-glaux--url-face (url)
  "Dynamic face for URL links."
  (let ((https+url (if (string-match "https?://" url)
		       url
		     (concat "https://" url))))
    (condition-case nil 
	(when (url-file-exists-p https+url)
	  'org-link)
      ;; url broken or FIXME: connection error...
      (error 'org-warning))))
;;;; Internal -- Make dir
(defun org-glaux--assets-buffer-make-dir ()
  "Create asset directory of current buffer page if it doesn't exit."
  (if (not (org-glaux--is-buffer-in (current-buffer)))
      (error "Not in a wiki page")
    (org-glaux--assets-make-dir (org-glaux--current-page-name))))

(defun org-glaux--assets-make-dir (filepath)
  "Create the asset directory from a page's FILEPATH if it doesn't exist."
  (let ((assets-dir (org-glaux--assets-get-dir filepath)))
    (if (not (file-exists-p assets-dir))
	(make-directory assets-dir t))))

;;;; Internal -- Menu
(defun org-glaux--easy-menu-entry (entry-name prefix)
  "Create a menu entry with ENTRY-NAME including functions prefixed by PREFIX."
  ;; (entry-name [doc_f1 f1] [doc_f2 f2] ...)
  (cons entry-name
	(mapcar 
	 (lambda (f)
	   ;; [<func-doc_first_line> <func>]
	   (vector (car (split-string (documentation (intern f)) "\n"))
		   (intern f)))
	 ;; list of functions prefixed by PREFIX
	 (let (glaux-list)
	   (mapatoms (lambda (x)
		       (when (and (fboundp x)
				(string-prefix-p prefix (symbol-name x))) 
			 (push (symbol-name x) glaux-list ))))
	   glaux-list))))


;;;; Internal -- Org properties
(defun org-glaux--global-props (fpath &optional property)
  "Return the plists of global org properties of a FPATH.

Argument FPATH: filepath.
Optional argument PROPERTY: the property seeking."
  (let* ((bp (get-file-buffer fpath))
	 (buffer (find-file fpath)))
    (unless property (setq property "PROPERTY"))
    (with-current-buffer (or buffer (current-buffer))
      (let ((value (org-element-map (org-element-parse-buffer)
		       'keyword (lambda (el) (when (string-match property (org-element-property :key el)) el)))))
	;; close the file if it was opened by this function
	(unless bp
	  (with-current-buffer buffer
	    (save-buffer)
	    (kill-this-buffer)))
	value))))

(defun org-glaux--global-prop-value (fpath key)
  "Return global org property KEY of current buffer.
Argument FPATH: filepath."
  (org-element-property :value (car (org-glaux--global-props fpath key))))

;;;; Internal -- Path computing
(defun org-glaux--file-wiki-path (fpath)
  "Return the wiki-path of FPATH (filepath)."
  (file-relative-name (file-name-sans-extension fpath) org-glaux-location))

(defun org-glaux--replace-extension (fpath extension)
  "Replace FPATH's extension by a new EXTENSION."
  (concat (file-name-directory fpath)
	  (file-name-base fpath)
	  "."
	  extension))

  ;; TODO rename this function
  (defun org-glaux--page->file (wiki-path)
    "Return filepath of given WIKI-PATH.
- Relative wiki-path:
    - Children page: \"/test\" -> \"<current-file-assets-dir>/test.org\"
    - Sibling page: \"../test\" -> \"<current-dir>/test.org\"
- Absolute wiki-path: \"test\" -> \"<org-glaux-location>/test.org\""
    (expand-file-name
     (concat
      (concat
       ;; if wiki-path starts with (../)+ or / then it's a relative wiki-path
       (if (string-match "^\\(\\(\\.\\.\\/\\)+\\|\\/\\)" wiki-path)
	   (file-name-as-directory (file-name-sans-extension buffer-file-name))
	 (file-name-as-directory org-glaux-location))
       wiki-path) ".org")))

(defun org-glaux--current-page-name ()
  "Return current org-glaux page's name bound to current buffer."
  (file-name-base buffer-file-name))

;; TODO rename this function
(defun org-glaux--current-page-assets-dir ()
  "Return current org-glaux page's asset directory path."
  (expand-file-name (org-glaux--current-page-name)
		    (file-name-directory buffer-file-name)))

;; TODO rename this function
(defun org-glaux--current-page-assets-file (filename)
  "Return current page's asset path given its FILENAME."
  (expand-file-name filename (org-glaux--current-page-assets-dir)))

(defun org-glaux--page->html-file (wiki-path)
  "Convert a page's WIKI-PATH to corresponding html filepath."
  (org-glaux--replace-extension (org-glaux--page->file wiki-path) "html"))

(defun org-glaux--assets-get-dir (filepath)
  "Return the page's asset directory path given its FILEPATH."
  (file-name-sans-extension filepath))

;;;; Internal -- Predicate
(defun org-glaux--is-buffer-in (buffer)
  "Return non-nil if BUFFER is an org-glaux buffer under `org-glaux-location`."
  (string-prefix-p
   (expand-file-name org-glaux-location)
   (buffer-file-name buffer)))

;;;; Internal -- Publish
(defun org-glaux--make-org-publish-plist (org-exporter)
  "Prepare plist for use with `org-publish'.
Argument ORG-EXPORTER an org-exporter."
  (let ((plist-base
	 `("html"
	   :base-directory        ,org-glaux-location
	   :base-extension        "org"
	   :recursive             t
	   :publishing-directory  ,org-glaux-location
	   :publishing-function   ,org-exporter)))
    (setcdr plist-base
	    ;; combine with custom publish settings
	    (org-combine-plists (cdr plist-base) org-glaux-publish-plist))
    plist-base))

;;;; Internal -- Selection
(defun org-glaux--select (callback)
  "Select a wiki page and invokes the CALLBACK function on it."
  (let ((target (completing-read "Wiki pages: "
				 (mapcar (lambda (file) (org-glaux--file-wiki-path file))
					 (org-glaux--page-files)))))
    (funcall callback target)))

(defun org-glaux--assets-select (callback)
  "Select an asset of the current page and invokes the CALLBACK function on it."
  (let ((target (completing-read "Wiki pages: "
				 (org-glaux--assets-page-files
				  (org-glaux--assets-get-dir buffer-file-name)))))
    (funcall callback (org-glaux--current-page-assets-file target))))

;;; Links
;;;; Wiki link
;; Hyperlinks to other wiki pages.
;; wiki:<wiki-path> or [[wiki:<wiki-path>][<description>]]
(org-link-set-parameters "wiki"
			 :follow #'org-glaux--wiki-follow
			 :export #'org-glaux--wiki-export
			 :face #'org-glaux--wiki-face)

;;;; Http link
;; (org-link-set-parameters "http"
;;  			 :face #'org-glaux--url-face)
;; 
;; (org-link-set-parameters "https"
;;  			 :face #'org-glaux--url-face)

;;; org-glaux.el ends here

