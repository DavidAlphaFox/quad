#lang debug racket/base
(require (for-syntax racket/base)
         racket/match
         pollen/tag
         racket/system
         racket/class
         syntax/strip-context
         scribble/reader
         quadwriter/core
         txexpr)
(provide (all-defined-out))

(define q (default-tag-function 'q))

(define ((make-read-syntax expander-mod pt-proc) path-string p)
  (strip-context
   (with-syntax ([PATH-STRING path-string]
                 [PT (pt-proc path-string p)]
                 [EXPANDER-MOD expander-mod])
     #'(module _ EXPANDER-MOD
         PATH-STRING
         . PT))))

(define-syntax-rule (make-module-begin DOC-PROC)
  (begin
    (provide (rename-out [new-module-begin #%module-begin]))
    (define-syntax (new-module-begin stx)
      (syntax-case stx ()
        [(_ PATH-STRING . EXPRS)
         (with-syntax ([DOC (datum->syntax #'PATH-STRING 'doc)]
                       [VIEW-RESULT (datum->syntax #'PATH-STRING 'view-result)])
           #'(#%module-begin
              (provide DOC VIEW-RESULT)
              (define DOC (DOC-PROC (list . EXPRS)))
              (define pdf-path (path-string->pdf-path 'PATH-STRING))
              (define (VIEW-RESULT)
                (when (file-exists? pdf-path)
                  (void (system (format "open ~a" pdf-path)))))
              (module+ main
                (render-pdf DOC pdf-path))))]))))

(define (path-string->pdf-path path-string)
  (match (format "~a" path-string)
    ;; weird test but sometimes DrRacket calls the unsaved file
    ;; 'unsaved-editor and sometimes "unsaved editor"
    [(regexp #rx"unsaved.editor")
     (build-path (find-system-path 'desk-dir) "untitled.pdf")]
    [_ (path-replace-extension path-string #".pdf")]))

(define quad-at-reader (make-at-reader
                        #:syntax? #t 
                        #:inside? #t
                        #:command-char #\◊))

(define (xexpr->parse-tree x)
  ;; an ordinary txexpr can't serve as a parse tree because of the attrs list fails when passed to #%app.
  ;; so stick an `attr-list` identifier on it which can hook into the expander.
  ;; sort of SXML-ish.
  (let loop ([x x])
    (match x
      [(txexpr tag attrs elems) (list* tag (cons 'attr-list attrs) (map loop elems))]
      [(? list? xs) (map loop xs)]
      [_ x])))

(define (get-info in mod line col pos)
  ;; DrRacket caches source file information per session,
  ;; so we can do the same to avoid multiple searches for the command char.
  (define command-char-cache (make-hash))
  (define my-command-char #\◊)
  (λ (key default)
    (case key
      [(color-lexer)
       (match (dynamic-require 'syntax-color/scribble-lexer 'make-scribble-inside-lexer (λ () #false))
         [(? procedure? make-lexer) (make-lexer #:command-char my-command-char)]
         [_ default])]
      [(drracket:toolbar-buttons)
       (match (dynamic-require 'pollen/private/drracket-buttons 'make-drracket-buttons (λ () #false))
         [(? procedure? make-buttons) (make-buttons my-command-char)])]
      [(drracket:indentation)
       (λ (text pos)
         (define line-idx (send text position-line pos))
         (define line-start-pos (send text line-start-position line-idx))
         (define line-end-pos (send text line-end-position line-idx))
         (define first-vis-pos
           (or
            (for/first ([pos (in-range line-start-pos line-end-pos)]
                        #:unless (char-blank? (send text get-character pos)))
              pos)
            line-start-pos))
         (- first-vis-pos line-start-pos))]      
      [else default])))