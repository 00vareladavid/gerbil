#!/usr/bin/env gxi-script
;; -*- Gerbil -*-
;; build-deps depgraph generator
(import "make")

(include "build-spec.ss")

(let (srcdir (path-normalize (path-directory (this-source-file))))
  (add-load-path (path-normalize (path-expand ".." srcdir))))
  
(let (depgraph (make-depgraph/spec build-spec))
  (call-with-output-file "build-deps" (cut pretty-print depgraph <>)))
