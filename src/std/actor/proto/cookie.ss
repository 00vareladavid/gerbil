;;; -*- Gerbil -*-
;;; (C) vyzo
;;; actor rpc cookie authen protocol
package: std/actor/proto

(import :gerbil/gambit/ports
        :gerbil/gambit/hvectors
        :std/net/address
        :std/crypto/etc
        :std/crypto/digest
        :std/actor/xdr
        :std/actor/proto
        :std/actor/proto/message
        :std/actor/proto/null
        )

(export rpc-cookie-proto
        rpc-generate-cookie!
        rpc-cookie-proto-challenge
        rpc-cookie-proto-challenge-respond)

(def challenge-length 32)
(def challenge-digest digest::sha256)

(def (rpc-cookie-proto-accept sock cookie)
(def connection-closed "rpc accept error; connection closed")
  (def bad-hello "rpc accept error; bad hello")
  (let (e (read-u8 sock))
    (cond
     ((eof-object? e)
      (error connection-closed))
     ((eq? e rpc-proto-connect-hello)
      (let (e (read-u8 sock))
        (cond
         ((eq? e rpc-proto-cookie)
          (rpc-cookie-proto-challenge sock cookie)
          (values rpc-null-proto-read
                  rpc-null-proto-write))
         ((eof-object? e)
          (error connection-closed))
         (else
          (error bad-hello e sock)))))
     (else
      (write-u8/force-output rpc-proto-connect-reject sock)
      (error bad-hello e sock)))))

(def (rpc-cookie-proto-connect sock cookie)
  (def connection-closed "rpc connect error; connection closed")
  (def bad-hello "rpc connect error; bad hello")
  (write-u8 rpc-proto-connect-hello sock)
  (write-u8 rpc-proto-cookie sock)
  (force-output sock)
  (let (e (read-u8 sock))
    (cond
     ((eof-object? e)
      (error connection-closed))
     ((eq? e rpc-proto-challenge)
      (rpc-cookie-proto-challenge-respond sock cookie)
      (values rpc-null-proto-read
              rpc-null-proto-write))
     (else
      (error bad-hello e sock)))))

(def (rpc-cookie-proto-challenge sock cookie)
  (write-u8/force-output rpc-proto-challenge sock)
  (let ((challenge (random-bytes challenge-length))
        (digest (make-digest challenge-digest)))
    (xdr-binary-write challenge sock)
    (force-output sock)
    (let* ((response (xdr-binary-read sock))
           (secret
            (begin
              (digest-update! digest cookie)
              (digest-update! digest challenge)
              (digest-final! digest))))
      (if (equal? response secret)
        (write-u8/force-output rpc-proto-connect-accept sock)
        (error "rpc accept error; authentication failure" challenge response)))))

(def (rpc-cookie-proto-challenge-respond sock cookie)
  (let* ((challenge (xdr-binary-read sock))
         (digest (make-digest challenge-digest)))
    (digest-update! digest cookie)
    (digest-update! digest challenge)
    (let (response (digest-final! digest))
      (xdr-binary-write response sock)
      (force-output sock))
    (let (e (read-u8 sock))
      (cond
       ((eq? e rpc-proto-connect-accept)
        #!void)
       ((eof-object? e)
        (error "rpc connect error; connection closed"))
       (else
        (error "rpc connect error; authentication failure" e sock))))))

(def (rpc-cookie-proto (cookie-file "~/.gerbil/cookie"))
  (let (cookie (call-with-input-file cookie-file read))
    (if (u8vector? cookie)
      (make-!rpc-protocol
       rpc-null-proto-open-client
       rpc-null-proto-open-server
       (cut rpc-cookie-proto-connect <> cookie)
       (cut rpc-cookie-proto-accept <> cookie))
      (error "Invalid cookie; expected u8vector"
        cookie-file cookie))))

(def (rpc-generate-cookie! (cookie-file "~/.gerbil/cookie"))
  (let (cookie (random-bytes challenge-length))
    (call-with-output-file cookie-file
      (cut write cookie <>))))
