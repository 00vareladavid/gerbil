#!/usr/bin/env gxi
;; -*- Gerbil -*-

(import :std/make)

(include "build-spec.ss")

(let ((srcdir (path-directory (this-source-file)))
      (depgraph (call-with-input-file "build-deps" read)))
  (make srcdir: srcdir
        prefix: "tutorial/lang"
        optimize: #t
        depgraph: depgraph
        build-spec))
