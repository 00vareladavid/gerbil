;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; R7RS prelude
package: scheme

(import (only-in :scheme/base begin cond-expand include include-ci and or not))
(export
  (rename: r7rs-import import)
  (rename: r7rs-export export)
  define-library
  begin cond-expand include include-ci include-library-declarations and or not
  r7rs)

(provide r7rs)

(defsyntax (r7rs-import stx)
  (def (import-spec-e set)
    (syntax-case set (only except prefix rename)
      ((only in id ...)
       (with-syntax ((spec (import-spec-e #'in)))
         (stx-wrap-source
          #'(only-in spec id ...)
          (stx-source set))))
      ((except in id ...)
       (with-syntax ((spec (import-spec-e #'in)))
         (stx-wrap-source
          #'(except-in spec id ...)
          (stx-source set))))
      ((prefix in pre)
       (with-syntax ((spec (import-spec-e #'in)))
         (stx-wrap-source
          #'(prefix-in spec pre)
          (stx-source set))))
      ((rename in (id new-id) ...)
       (with-syntax ((spec (import-spec-e #'in)))
         (stx-wrap-source
          #'(rename-in spec (id new-id) ...)
          (stx-source set))))
      ((id ids ...)
       (identifier-list? #'(id ids ...))
       (let* ((spath (map stx-e #'(id ids ...)))
              (spath (map symbol->string spath))
              (spath (string-join spath #\/))
              (spath (string-append ":" spath))
              (mpath (string->symbol spath)))
         (stx-wrap-source mpath (stx-source set))))))
  
  (syntax-case stx ()
    ((_ import-set ...)
     (with-syntax (((import-spec ...)
                    (map import-spec-e #'(import-set ...))))
       #'(import import-spec ...)))))

(defrules include-library-declarations ()
  ((_ path ...)
   (begin (include path) ...)))

(defsyntax (define-library stx)
  (def (library-module-id ids )
    (let* ((spath (map stx-e ids))
           (spath (map symbol->string spath))
           (spath (string-join spath #\/)))
      (string->symbol spath)))
  
  (def (expand-decls decls)
    (let lp ((rest decls) (body []))
      (match rest
        ([decl . rest]
         (syntax-case decl (r7rs-import r7rs-export cond-expand begin include include-ci include-library-declarations)
           ((r7rs-import import-set ...)
            (lp rest (cons decl body)))
           ((r7rs-export export-set ...)
            (lp rest (cons decl body)))
           ((cond-expand clause ...)
            (lp rest (cons decl body)))
           ((begin library-body ...)
            (lp rest (cons decl body)))
           ((include path ...)
            (lp rest (cons decl body)))
           ((include-ci path ...)
            (lp rest (cons decl body)))
           ((include-library-declarations path ...)
            (lp rest (cons decl body)))))
        (else
         (reverse body)))))
  
  (syntax-case stx ()
    ((_ (id ids ...) decl ...)
     (identifier-list? #'(id ids ...))
     (let (ctx (current-expander-context))
       (cond
        ((module-context? ctx)
         (unless (eq? (expander-context-id ctx)
                      (library-module-id #'(id ids ...)))
           (raise-syntax-error #f "Bad syntax; module id mismatch"
                               stx #'(id ids ...) (expander-context-id ctx)))
         (with-syntax (((body ...) (expand-decls #'(decl ...))))
           #'(begin body ...)))
        (else
         (raise-syntax-error #f "Bad syntax; illegal context" stx)))))))

(defsyntax (r7rs-export stx)
  (def (export-spec-e spec)
    (syntax-case spec (rename)
      ((rename id new-id)
       (identifier? #'id)
       #'(rename: id new-id))
      (id
       (identifier? #'id)
       #'id)))
  
  (syntax-case stx ()
    ((_ exports ...)
     (with-syntax (((export-spec ...) (map export-spec-e #'(exports ...))))
       #'(export export-spec ...)))))
