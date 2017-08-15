;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; extensible binary i/o buffers with port compatible interface
;;; Warning: Low level unsafe interface; let their be Dragons.
package: std/net/bio

(import :gerbil/gambit/bits
        :std/error)
(export #t)

(declare (not safe))

;;; Input buffers
;;; e: u8vector
;;; rlo: read range low mark, where the next read can begin
;;; rhi: read range hi mark, where the read must end
;;; fill: lambda (buf need) => fixnum?
;;;       fill the buffer with need bytes in read range
;;; read: lambda (bytes start end buf) => fixnum?
;;;       read unbuffered
;;;       precondition: buffer is empty
(defstruct input-buffer (e rlo rhi fill read)
  unchecked: #t)

(def (bio-read-u8 buf)
  (let ((rlo (&input-buffer-rlo buf))
        (rhi (&input-buffer-rhi buf)))
    (if (##fx< rlo rhi)
      (let (u8 (##u8vector-ref (&input-buffer-e buf) rlo))
        (set! (&input-buffer-rlo buf)
          (##fx+ rlo 1))
        u8)
      (let (rd ((&input-buffer-fill buf) buf 1))
        (if (##fxzero? rd)
          (eof-object)
          (let* ((rlo (&input-buffer-rlo buf))
                 (u8 (##u8vector-ref (&input-buffer-e buf) rlo)))
            (set! (&input-buffer-rlo buf)
              (##fx+ rlo 1))
            u8))))))

(def (bio-peek-u8 buf)
  (let ((rlo (&input-buffer-rlo buf))
        (rhi (&input-buffer-rhi buf)))
    (if (##fx< rlo rhi)
      (##u8vector-ref (&input-buffer-e buf) rlo)
      (let (rd ((&input-buffer-fill buf) buf 1))
        (if (##fxzero? rd)
          (eof-object)
          (let (rlo (&input-buffer-rlo buf))
            (##u8vector-ref (&input-buffer-e buf) rlo)))))))

(def (bio-read-subu8vector bytes start end buf)
  (let lp ((start start) (need (##fx- end start)) (count 0))
    (let* ((rlo (&input-buffer-rlo buf))
           (rhi (&input-buffer-rhi buf))
           (rlo+need (##fx+ rlo need)))
      (cond
       ((##fx<= rlo+need rhi)           ; have all
        (##subu8vector-move! (&input-buffer-e buf) rlo rlo+need bytes start)
        (set! (&input-buffer-rlo buf)
          rlo+need)
        (##fx+ need count))
       ((##fx< rlo rhi)                 ; have some
        (let (have (##fx- rhi rlo))
          (##subu8vector-move! (&input-buffer-e buf) rlo rhi bytes start)
          (set! (&input-buffer-rlo buf)
            rhi)
          (let* ((need (##fx- need have))
                 (rd ((&input-buffer-fill buf) buf need)))
            (if (##fxzero? rd)
              count
              (lp (##fx+ start have) need (##fx+ count have))))))
       ;; have none, does it make sense to buffer?
       ((##fx< need (##u8vector-length (&input-buffer-e buf)))
        (let (rd ((&input-buffer-fill buf) buf need))
          (if (##fxzero? rd)
            count
            (lp start need count))))
       (else                            ; too large, read unbuffered
        (##fx+ count ((&input-buffer-read buf) bytes start end buf)))))))

(def (bio-read-subu8vector* bytes start end buf)
  (let* ((want (##fx- end start))
         (rlo  (&input-buffer-rlo buf))
         (rhi  (&input-buffer-rhi buf))
         (have (##fx- rhi rlo))
         (copy (##fxmin want have)))
    (when (##fx> copy 0)
      (let (rlo+copy (##fx+ rlo copy))
        (##subu8vector-move! (&input-buffer-e buf) rlo rlo+copy bytes start)
        (set! (&input-buffer-rlo buf)
          rlo+copy)))
    copy))

(def (bio-read-subu8vector-unbuffered bytes start end buf)
  (let* ((need (##fx- end start))
         (rlo (&input-buffer-rlo buf))
         (rhi (&input-buffer-rhi buf))
         (rlo+need (##fx+ rlo need)))
    (cond
     ((##fx<= rlo+need rhi)             ; have all
      (##subu8vector-move! (&input-buffer-e buf) rlo rlo+need bytes start)
      (set! (&input-buffer-rlo buf)
        rlo+need)
      need)
     ((##fx< rlo rhi)                   ; have some
      (let (have (##fx- rhi rlo))
        (##subu8vector-move! (&input-buffer-e buf) rlo rhi bytes start)
        (set! (&input-buffer-rlo buf)
          rhi)
        (##fx+ have ((&input-buffer-read buf) bytes (##fx+ start have) end buf))))
     (else                              ; have none
      ((&input-buffer-read buf) bytes start end buf)))))

(def (bio-read-bytes bytes buf)
  (let* ((len (u8vector-length bytes))
         (rd (bio-read-subu8vector bytes 0 len buf)))
    (unless (##fx= rd len)
      (raise-io-error 'bio-read-bytes "premature end of input" buf rd len))))

(def (bio-read-bytes-unbuffered bytes buf)
  (let* ((len (u8vector-length bytes))
         (rd (bio-read-subu8vector-unbuffered bytes 0 len buf)))
    (unless (##fx= rd len)
      (raise-io-error 'bio-read-bytes "premature end of input" buf rd len))))

(def (bio-read-u32 buf)
  (let* ((rlo (&input-buffer-rlo buf))
         (rhi (&input-buffer-rhi buf))
         (rlo+4 (##fx+ rlo 4)))
    (if (##fx<= rlo+4 rhi)
      (let (u32 (bio-get-u32 (&input-buffer-e buf) rlo))
        (set! (&input-buffer-rlo buf)
          rlo+4)
        u32)
      (let* ((_ ((&input-buffer-fill buf) buf 4))
             (rlo (&input-buffer-rlo buf))
             (rhi (&input-buffer-rhi buf))
             (rlo+4 (##fx+ rlo 4)))
        (if (##fx<= rlo+4 rhi)
          (let (u32 (bio-get-u32 (&input-buffer-e buf) rlo))
            (set! (&input-buffer-rlo buf)
              rlo+4)
            u32)
          (raise-io-error 'bio-read-u32 "Premature end of input" buf rlo rhi))))))

(def (bio-get-u32 u8v start)
  (cond
   ((##fxarithmetic-shift-left? (##u8vector-ref u8v start) 24)
    => (lambda (bits)
         (##fxior bits
                  (##fxarithmetic-shift-left (##u8vector-ref u8v (##fx+ start 1)) 16)
                  (##fxarithmetic-shift-left (##u8vector-ref u8v (##fx+ start 2)) 8)
                  (##u8vector-ref u8v (##fx+ start 3)))))
   (else
    (bitwise-ior (arithmetic-shift (##u8vector-ref u8v start) 24)
                 (##fxarithmetic-shift-left (##u8vector-ref u8v (##fx+ start 1)) 16)
                 (##fxarithmetic-shift-left (##u8vector-ref u8v (##fx+ start 2)) 8)
                 (##u8vector-ref u8v (##fx+ start 3))))))
