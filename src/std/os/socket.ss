;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; OS socket interface
package: std/os

(import :std/os/_socket
        :std/os/error
        :std/os/fd
        :std/os/fcntl
        :std/net/address
        :std/sugar
        (only-in :gerbil/gambit/ports close-port))

(export #t)

(def (open-socket domain type proto)
  (let (fd (check-os-error (_socket domain type proto)
             (socket domain type proto)))
    (fdopen fd 'inout 'socket)))

(def (socket domain type (proto 0))
  (let (raw (open-socket domain type proto))
    (fd-set-nonblock raw)
    (fd-set-closeonexec raw)
    raw))

(def (socket? obj)
  (fd-type? obj 'socket))

(def (socket-bind sock addr)
  (check-os-error (_bind (fd-e sock) (socket-address addr))
    (socket-bind sock addr)))

(def (socket-listen sock (backlog 10))
  (check-os-error (_listen (fd-e sock) backlog)
    (socket-listen sock backlog)))

(def (socket-accept sock (sa #f))
  (alet (fd (do-retry-nonblock (_accept (fd-e sock) sa)
             (_accept sock sa)))
    (let (raw (fdopen fd 'inout 'socket))
      (fd-set-nonblock raw)
      (fd-set-closeonexec raw)
      raw)))

(def (socket-connect sock sa)
  (let (sa (socket-address sa))
    (do-retry-nonblock (_connect (fd-e sock) sa)
      (socket-connect sock sa))))

(def (socket-shutdown sock how)
  (check-os-error (_shutdown (fd-e sock) how)
    (socket-shutdown sock how))
  (cond
   ((eq? how SHUT_RD)
    (close-input-port sock))
   ((eq? how SHUT_WR)
    (close-output-port sock))
   ((eq? how SHUT_RDWR)
    (close-port sock))))

(def (socket-close sock)
  (with-catch void (cut close-port sock)))

(def (socket-send sock bytes (start 0) (end (u8vector-length bytes)) (flags 0))
  (do-retry-nonblock (_send (fd-e sock) bytes start end flags)
    (socket-send sock bytes start end flags)))

(def (socket-sendto sock bytes sa (start 0) (end (u8vector-length bytes)) (flags 0))
  (let (sa (and sa (socket-address sa)))
    (do-retry-nonblock (_sendto (fd-e sock) bytes start end flags sa)
      (socket-sendto sock bytes sa start end flags))))

;; TODO socket-sendmsg

(def (socket-recv sock bytes (start 0) (end (u8vector-length bytes)) (flags 0))
  (do-retry-nonblock (_recv (fd-e sock) bytes start end flags)
    (socket-recv sock bytes start end flags)))

(def (socket-recvfrom sock bytes sa (start 0) (end (u8vector-length bytes)) (flags 0))
  (do-retry-nonblock (_recvfrom (fd-e sock) bytes start end flags sa)
    (socket-recvfrom sock bytes sa start end flags)))

;; TODO socket-recvmsg

(def (socket-getpeername sock)
  (let* ((af (socket-getsockopt sock SOL_SOCKET SO_DOMAIN))
         (sa (make-socket-address af)))
    (check-os-error (_getpeername (fd-e sock) sa)
      (socket-getpeername sock))
    sa))

(def (socket-getsockname sock)
  (let* ((af (socket-getsockopt sock SOL_SOCKET SO_DOMAIN))
         (sa (make-socket-address af)))
    (check-os-error (_getsockname (fd-e sock) sa)
      (socket-getsockname sock))
    sa))

;;; Socket addresses
(def (socket-address? obj)
  (_sockaddr? obj))

(def (make-socket-address af)
  (cond
   ((eq? af AF_INET)
    (make-socket-address-in))
   ((eq? af AF_INET6)
    (make-socket-address-in6))
   ((eq? af AF_UNIX)
    (make-socket-address-un))
   (else
    (error "Unknown address family" af))))

(def (make-socket-address-in)
  (_make_sockaddr_in))

(def (make-socket-address-in6)
  (_make_sockaddr_in6))

(def (make-socket-address-un)
  (_make_sockaddr_un))

(def (socket-address-in host port)
  (let (ip4 (ip4-address host))
    (_sockaddr_in ip4 port)))

(def (socket-address-in6 host port)
  (let (ip6 (ip6-address host))
    (_sockaddr_in6 ip6 port)))

(def (socket-address-un path)
  (path->socket-address path))

(def (socket-address addr)
  (cond
   ((socket-address? addr) addr)
   ((or (inet-address? addr)
        (inet-address-string? addr))
    (inet-address->socket-address addr))
   (else
    (path->socket-address addr))))

(def (inet-address->socket-address addr)
  (let lp ((addr (inet-address addr)))
    (with ([ip . port] addr)
      (cond
       ((ip4-address? ip)
        (_sockaddr_in ip port))
       ((ip6-address? ip)
        (_sockaddr_in6 ip port))
       (else
        (error "Bad address; expected resolved inet-address" addr))))))

(def (path->socket-address path)
  (let (pathlen (u8vector-length (string->bytes path)))
    (if (fx< pathlen UNIX_MAX_PATH)
      (_sockaddr_un path)
      (error "Malformed address; path is too long"))))

(def (socket-address->address sa)
  (let (saf (_sockaddr_fam sa))
    (cond
     ((eq? saf AF_INET)
      (let* ((ip4 (make-u8vector 4))
             (_ (_sockaddr_in_addr sa ip4))
             (port (_sockaddr_in_port sa)))
        (cons ip4 port)))
     ((eq? saf AF_INET6)
      (let* ((ip6 (make-u8vector 16))
             (_ (_sockaddr_in6_addr sa ip6))
             (port (_sockaddr_in6_port sa)))
        (cons ip6 port)))
     ((eq? saf AF_UNIX)
      (_sockaddr_un_path sa))
     (else
      (error "Unknown address family" sa saf)))))

(def (socket-address->string sa)
  (let (saf (_sockaddr_fam sa))
    (cond
     ((eq? saf AF_INET)
      (let* ((ip4 (make-u8vector 4))
             (_ (_sockaddr_in_addr sa ip4))
             (port (_sockaddr_in_port sa)))
        (string-append (ip4-address->string ip4) ":" (number->string port))))
     ((eq? saf AF_INET6)
      (let* ((ip6 (make-u8vector 16))
             (_ (_sockaddr_in6_addr sa ip6))
             (port (_sockaddr_in6_port sa)))
        (string-append (ip6-address->string ip6) ":" (number->string port))))
     ((eq? saf AF_UNIX)
      (_sockaddr_un_path sa))
     (else
      (error "Unknown address family" sa saf)))))

;;; sockopts
(def (socket-getsockopt sock level opt . args)
  (cond
   ((hash-get socket-sockopts level)
    => (lambda (ht)
         (cond
          ((hash-get ht opt)
           => (match <>
                ((values getf setf)
                 (if getf
                   (apply getf sock level opt args)
                   (error "No getsockopt operation defined for option" level opt)))))
          (else
           (error "Unknown socket option" level opt)))))
   (else
    (error "Unknown socket level" level opt))))

(def (socket-setsockopt sock level opt val . args)
  (cond
   ((hash-get socket-sockopts level)
    => (lambda (ht)
         (cond
          ((hash-get ht opt)
           => (match <>
                ((values getf setf)
                 (if setf
                   (apply setf sock level opt val args)
                   (error "No setsockopt operation defined for option" level opt)))))
          (else
           (error "Unknown socket option" level opt)))))
   (else
    (error "Unknown socket level" level opt))))

(def (socket-getsockopt-int sock level opt)
  (check-os-error (_getsockopt_int (fd-e sock) level opt)
    (socket-getsockopt sock level opt)))

(def (socket-setsockopt-int sock level opt val)
  (if (fixnum? val)
    (check-os-error (_setsockopt_int (fd-e sock) level opt val)
      (socket-setsockopt sock level opt val))
    (error "Bad argument; expected fixnum" val)))

(def (socket-getsockopt-tv sock level opt)
  (let (tv (_make_tv))
    (check-os-error (_getsockopt_tv (fd-e sock) level opt tv)
      (socket-getsockopt sock level opt))
    (+ (_tv_sec tv) (/ (_tv_usec tv) 1e6))))

(def (socket-setsockopt-tv sock level opt tm)
  (if (real? tm)
    (let* ((tm-sec (floor tm))
           (tm-frac (- tm tm-sec))
           (tm-usec (floor (* tm-frac 1e6)))
           (tv (_make_tv)))
      (_tv_sec_set tv (inexact->exact tm-sec))
      (_tv_usec_set tv (inexact->exact tm-usec))
      (check-os-error (_setsockopt_tv (fd-e sock) level opt tv)
        (socket-setsockopt sock level opt tm)))
    (error "Bad argument; expected real" tm)))

(def (socket-getsockopt-addr-in sock level opt)
  (let (sa (make-socket-address-in))
    (check-os-error (_getsockopt_sa (fd-e sock) level opt sa)
      (socket-getsockopt sock level opt))
    sa))

(def (socket-getsockopt-addr-in6 sock level opt)
  (let (sa (make-socket-address-in6))
    (check-os-error (_getsockopt_sa (fd-e sock) level opt sa)
      (socket-getsockopt sock level opt))
    sa))

(def (socket-setsockopt-addr sock level opt addr)
  (let (sa (socket-address addr))
    (check-os-error (_setsockopt_sa (fd-e sock) level opt sa)
      (socket-setsockopt sock level opt addr))))

(def (socket-getsockopt-bytes sock level opt bytes)
  (if (u8vector? bytes)
    (check-os-error (_getsockopt_bytes (fd-e sock) level opt bytes)
      (socket-getsockopt sock level opt bytes))
    (error "Bad argument; expected bytes" bytes)))

(def (socket-setsockopt-bytes sock level opt bytes)
  (if (u8vector? bytes)
    (check-os-error (_setsockopt_bytes (fd-e sock) level opt bytes)
      (socket-setsockopt sock level opt bytes))
    (error "Bad argument; expected bytes" bytes)))

(def (socket-setsockopt-mreq sock level opt ips)
  (match ips
    ((cons maddr laddr)
     (let ((maddr (ip4-address maddr))
           (laddr (ip4-address laddr)))
     (check-os-error (_setsockopt_mreq (fd-e sock) level opt maddr laddr)
       (socket-setsockopt sock level opt ips))))
    (else
     (error "Bad argument; expected pair of ip4 addresses" ips))))

(def (socket-setsockopt-mreq-src sock level opt ips)
  (match ips
    ([maddr iaddr saddr]
     (let ((maddr (ip4-address maddr))
           (iaddr (ip4-address iaddr))
           (saddr (ip4-address saddr)))
     (check-os-error (_setsockopt_mreq_src (fd-e sock) level opt maddr iaddr saddr)
       (socket-setsockopt sock level opt ips))))
    (else
     (error "Bad argument; expected list with 3 ip4 addresses" ips))))

(def (socket-setsockopt-mreq6 sock level opt ips)
  (match ips
    ((cons maddr laddr)
     (let ((maddr (ip6-address maddr))
           (laddr (ip6-address laddr)))
     (check-os-error (_setsockopt_mreq6 (fd-e sock) level opt maddr laddr)
       (socket-setsockopt sock level opt ips))))
    (else
     (error "Bad argument; expected pair of ip6 addresses" ips))))

(def (socket-setsockopt-mreq6-src sock level opt ips)
  (match ips
    ([maddr iaddr saddr]
     (let ((maddr (ip6-address maddr))
           (iaddr (ip6-address iaddr))
           (saddr (ip6-address saddr)))
     (check-os-error (_setsockopt_mreq6_src (fd-e sock) level opt maddr iaddr saddr)
       (socket-setsockopt sock level opt ips))))
    (else
     (error "Bad argument; list with 3 ip6 addresses" ips))))

(def (socket-getsockopt-linger sock level opt)
  (let (linger (_make_linger))
    (check-os-error (_getsockopt_linger sock level opt linger)
      (socket-getsockopt sock level opt))
    (if (fxzero? (_linger_onoff linger))
      #f
      (_linger_linger linger))))

(def (socket-setsockopt-linger sock level opt val)
  (let (linger (_make_linger))
    (cond
     ((fixnum? val)
      (_linger_onoff_set linger 1)
      (_linger_linger_set val))
     ((not val))
     (else
      (error "Bad argument; expected fixnum or #f" val)))
    (check-os-error (_setsockopt_linger sock level opt linger)
      (socket-setsockopt sock level opt val))))

(def socket-sockopts
  (hash-eq (,SOL_SOCKET (make-hash-table-eq))
           (,IPPROTO_IP (make-hash-table-eq))
           (,IPPROTO_IPV6 (make-hash-table-eq))
           (,IPPROTO_TCP (make-hash-table-eq))))

(defrules defsockopt ()
  ((_ level opt getf setf)
   (unless (fxnegative? opt)
     (hash-put! (hash-ref socket-sockopts level)
                opt
                (values (@sockopt-getf getf) (@sockopt-setf setf))))))

(defsyntax (@sockopt-getf stx)
  (syntax-case stx ()
    ((_ id) (identifier? #'id) (stx-identifier #'id "socket-getsockopt-" #'id))
    ((_ #f) #f)))

(defsyntax (@sockopt-setf stx)
  (syntax-case stx ()
    ((_ id) (identifier? #'id) (stx-identifier #'id "socket-setsockopt-" #'id))
    ((_ #f) #f)))

;; this list is invariably incomplete, new ones get added all the time
;; add to it and _socket.{ssi,scm} if you are missing something!
(defsockopt SOL_SOCKET SO_ACCEPTCONN            int    #f)
(defsockopt SOL_SOCKET SO_BINDTODEVICE          bytes  bytes)
(defsockopt SOL_SOCKET SO_BROADCAST             int    int)     
(defsockopt SOL_SOCKET SO_DEBUG                 int    int)
(defsockopt SOL_SOCKET SO_DOMAIN                int    #f)
(defsockopt SOL_SOCKET SO_DONTROUTE             int    int)
(defsockopt SOL_SOCKET SO_ERROR                 int    #f)
(defsockopt SOL_SOCKET SO_KEEPALIVE             int    int)
(defsockopt SOL_SOCKET SO_LINGER                linger linger)
(defsockopt SOL_SOCKET SO_OOBLINE               int    int)
(defsockopt SOL_SOCKET SO_PASSCRED              int    int)
(defsockopt SOL_SOCKET SO_PEERCRED              bytes  bytes)
(defsockopt SOL_SOCKET SO_PEEK_OFF              int    int)
(defsockopt SOL_SOCKET SO_PROTOCOL              int    int)
(defsockopt SOL_SOCKET SO_RCVBUF                int    int)
(defsockopt SOL_SOCKET SO_SNDBUF                int    int)
(defsockopt SOL_SOCKET SO_RCVLOWAT              int    int)
(defsockopt SOL_SOCKET SO_SNDLOWAT              int    int)
(defsockopt SOL_SOCKET SO_RCVTIMEO              tv     tv)
(defsockopt SOL_SOCKET SO_SNDTIMEO              tv     tv)
(defsockopt SOL_SOCKET SO_REUSEADDR             int    int)
(defsockopt SOL_SOCKET SO_REUSEPORT             int    int)
(defsockopt SOL_SOCKET SO_TYPE                  int    int)
(defsockopt SOL_SOCKET SO_TIMESTAMP             int    int)
(defsockopt SOL_SOCKET SO_USELOOPBACK           int    int)

(defsockopt IPPROTO_IP IP_ADD_MEMBERSHIP         #f     mreq)
(defsockopt IPPROTO_IP IP_DROP_MEMBERSHIP        #f     mreq)
(defsockopt IPPROTO_IP IP_ADD_SOURCE_MEMBERSHIP  #f     mreq-src)
(defsockopt IPPROTO_IP IP_DROP_SOURCE_MEMBERSHIP #f     mreq-src)
(defsockopt IPPROTO_IP IP_BLOCK_SOURCE           #f     mreq-src)
(defsockopt IPPROTO_IP IP_UNBLOCK_SOURCE         #f     mreq-src)
(defsockopt IPPROTO_IP IP_FREEBIND               int    int)
(defsockopt IPPROTO_IP IP_HDRINCL                int    int)
(defsockopt IPPROTO_IP IP_MTU                    int    #f)
(defsockopt IPPROTO_IP IP_MTU_DISCOVER           int    int)
(defsockopt IPPROTO_IP IP_MULTICAST_ALL          int    int)
(defsockopt IPPROTO_IP IP_MULTICAST_IF           #f     mreq)
(defsockopt IPPROTO_IP IP_MULTICAST_LOOP         int    int)
(defsockopt IPPROTO_IP IP_MULTICAST_TTL          int    int)
(defsockopt IPPROTO_IP IP_NODEFRAG               int    int)
(defsockopt IPPROTO_IP IP_OPTIONS                bytes  bytes)
(defsockopt IPPROTO_IP IP_PKTINFO                bytes  bytes)
(defsockopt IPPROTO_IP IP_RECVERR                int    int)
(defsockopt IPPROTO_IP IP_RECVORIGDSTADDR        int    int)
(defsockopt IPPROTO_IP IP_RECVOPTS               int    int)
(defsockopt IPPROTO_IP IP_RECVTOS                int    int)
(defsockopt IPPROTO_IP IP_RECVTTL                int    int)
(defsockopt IPPROTO_IP IP_RETOPTS                int    int)
(defsockopt IPPROTO_IP IP_ROUTER_ALERT           int    int)
(defsockopt IPPROTO_IP IP_TOS                    int    int)
(defsockopt IPPROTO_IP IP_TTL                    int    int)

(defsockopt IPPROTO_IPV6 IPV6_ADDRFORM           #f     int)
(defsockopt IPPROTO_IPV6 IPV6_ADD_MEMBERSHIP     #f     mreq6)
(defsockopt IPPROTO_IPV6 IPV6_DROP_MEMBERSHIP    #f     mreq6)
(defsockopt IPPROTO_IPV6 IPV6_MTU                int    int)
(defsockopt IPPROTO_IPV6 IPV6_MTU_DISCOVER       int    int)
(defsockopt IPPROTO_IPV6 IPV6_MULTICAST_HOPS     int    int)
(defsockopt IPPROTO_IPV6 IPV6_MULTICAST_IF       int    int)
(defsockopt IPPROTO_IPV6 IPV6_MULTICAST_LOOP     int    int)
(defsockopt IPPROTO_IPV6 IPV6_RECVPKTINFO        int    int)
(defsockopt IPPROTO_IPV6 IPV6_RTHDR              int    int)
(defsockopt IPPROTO_IPV6 IPV6_AUTHHDR            int    int)
(defsockopt IPPROTO_IPV6 IPV6_DSTOPTS            int    int)
(defsockopt IPPROTO_IPV6 IPV6_HOPOPTS            int    int)
(defsockopt IPPROTO_IPV6 IPV6_FLOWINFO           int    int)
(defsockopt IPPROTO_IPV6 IPV6_HOPLIMIT           int    int)
(defsockopt IPPROTO_IPV6 IPV6_ROUTER_ALERT       int    int)
(defsockopt IPPROTO_IPV6 IPV6_UNICAST_HOPS       int    int)
(defsockopt IPPROTO_IPV6 IPV6_V6ONLY             int    int)

(defsockopt IPPROTO_TCP TCP_CONGESTION           #f     bytes)
(defsockopt IPPROTO_TCP TCP_CORK                 int    int)
(defsockopt IPPROTO_TCP TCP_DEFER_ACCEPT         int    int)
(defsockopt IPPROTO_TCP TCP_KEEPCNT              int    int)
(defsockopt IPPROTO_TCP TCP_KEEPIDLE             int    int)
(defsockopt IPPROTO_TCP TCP_KEEPINTVL            int    int)
(defsockopt IPPROTO_TCP TCP_MAXSEG               int    int)
(defsockopt IPPROTO_TCP TCP_NODELAY              int    int)
(defsockopt IPPROTO_TCP TCP_SYNCNT               int    int)
