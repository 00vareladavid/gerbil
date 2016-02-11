;;; -*- Scheme -*-
;;; (C) vyzo at hackzen.org
;;; libcrypto FFI

;; compile: -ld-options "-lcrypto"

(declare
  (block)
  (standard-bindings)
  (extended-bindings)
  (not safe)
  (not run-time-bindings))

(namespace ("std/crypto/libcrypto#"))
(##namespace ("" define-macro define let let* if or and
              quote quasiquote unquote unquote-splicing
              c-lambda c-define-type c-declare c-initialize 
              macro-foreign-tags macro-slot))

(c-declare #<<END-C
#include <openssl/evp.h>
#include <openssl/err.h>
#include <openssl/dh.h>
#include <openssl/bn.h>
END-C
)

(c-initialize #<<END-C
ERR_load_crypto_strings ();
OpenSSL_add_all_ciphers ();
OpenSSL_add_all_digests ();
END-C
)

(c-declare #<<END-C
#define U8_DATA(obj) ___CAST (___U8*, ___BODY_AS (obj, ___tSUBTYPED))
#define U8_LEN(obj) ___HD_BYTES (___HEADER (obj))
END-C
)

(define-macro (define-c-lambda id args ret #!optional (name #f))
  (let ((name (or name (##symbol->string id))))
    `(define ,id
       (c-lambda ,args ,ret ,name))))

;; funky decls to apease the compiler for discarding const
;; sometimes I really hate gcc (which apparently has no working option to turn
;;  that shit off -- -Wno-cast-qual doesn't fucking work, at least with 4.5.x)
;; other times I hate gsc for not having a const qualifier
(define-macro (define-c-lambda/const-pointer id args ret #!optional (result #f))
  (let ((result (or result "___result_voidstar"))
        (c-args
         (let lp ((rest args) (n 1) (c-args ""))
           (if (##pair? rest)
             (let* ((next (##string-append "___arg" (##number->string n)))
                    (c-args
                     (if (##fx> n 1)
                       (##string-append c-args "," next)
                       next)))
               (lp (##cdr rest) (##fx+ n 1) c-args))
             c-args))))
    `(define ,id
       (c-lambda ,args ,ret
         ,(##string-append result " = (void*)"
                           (##symbol->string id) "(" c-args ");")))))

(define-macro (define-c-type-predicate pred tag)
  `(define (,pred x)
     (and (##foreign? x)
          (##memq ',tag (macro-foreign-tags x)))))

;; error handling
(define-c-lambda ERR_get_error () unsigned-long)
(define-c-lambda ERR_peek_last_error () unsigned-long)
(define-c-lambda/const-pointer ERR_lib_error_string (unsigned-long) char-string
  "___result")
(define-c-lambda/const-pointer ERR_func_error_string (unsigned-long) char-string
  "___result")
(define-c-lambda/const-pointer ERR_reason_error_string (unsigned-long) char-string
  "___result")

;; Message Digests
(c-declare #<<END-C
static ___SCMOBJ ffi_release_EVP_MD_CTX (void *ptr);
static int ffi_EVP_DigestInit (EVP_MD_CTX *ctx, EVP_MD *type);
static int ffi_EVP_DigestUpdate (EVP_MD_CTX *ctx, ___SCMOBJ bytes, int start, int end);
static int ffi_EVP_DigestFinal (EVP_MD_CTX *ctx, ___SCMOBJ bytes);
END-C
)

(c-define-type EVP_MD "EVP_MD")
(c-define-type EVP_MD*
  (pointer EVP_MD (EVP_MD*)))
(c-define-type EVP_MD_CTX "EVP_MD_CTX")
(c-define-type EVP_MD_CTX*
  (pointer EVP_MD_CTX (EVP_MD_CTX*) "ffi_release_EVP_MD_CTX"))

(define-c-type-predicate EVP_MD? EVP_MD*)
(define-c-type-predicate EVP_MD_CTX? EVP_MD_CTX*)

(define-c-lambda EVP_MD_CTX_create () EVP_MD_CTX*)
(define-c-lambda EVP_DigestInit (EVP_MD_CTX* EVP_MD*) int
  "ffi_EVP_DigestInit")
(define-c-lambda EVP_DigestUpdate (EVP_MD_CTX* scheme-object int int) int
  "ffi_EVP_DigestUpdate")
(define-c-lambda EVP_DigestFinal (EVP_MD_CTX* scheme-object) int
  "ffi_EVP_DigestFinal")
(define-c-lambda EVP_MD_CTX_copy (EVP_MD_CTX* EVP_MD_CTX*) int
  "EVP_MD_CTX_copy_ex")

(define-c-lambda/const-pointer EVP_md5 () EVP_MD*)
(define-c-lambda/const-pointer EVP_sha1 () EVP_MD*)
(define-c-lambda/const-pointer EVP_dss1 () EVP_MD*)
(define-c-lambda/const-pointer EVP_sha224 () EVP_MD*)
(define-c-lambda/const-pointer EVP_sha256 () EVP_MD*)
(define-c-lambda/const-pointer EVP_sha384 () EVP_MD*)
(define-c-lambda/const-pointer EVP_sha512 () EVP_MD*)

(define-c-lambda EVP_MD_type (EVP_MD*) int)
(define-c-lambda EVP_MD_pkey_type (EVP_MD*) int)
(define-c-lambda EVP_MD_size (EVP_MD*) int)
(define-c-lambda EVP_MD_block_size (EVP_MD*) int)
(define-c-lambda/const-pointer EVP_MD_name (EVP_MD*) char-string
  "___result")

(define-c-lambda/const-pointer EVP_MD_CTX_md (EVP_MD_CTX*) EVP_MD*)
(define-c-lambda EVP_MD_CTX_type (EVP_MD_CTX*) int)
(define-c-lambda EVP_MD_CTX_size (EVP_MD_CTX*) int)
(define-c-lambda EVP_MD_CTX_block_size (EVP_MD_CTX*) int)

(define-c-lambda/const-pointer EVP_get_digestbyname (char-string) EVP_MD*)
(define-c-lambda/const-pointer EVP_get_digestbynid (int) EVP_MD*)

;;; Ciphers
(c-declare #<<END-C
static ___SCMOBJ ffi_release_EVP_CIPHER_CTX (void *ptr);
static EVP_CIPHER_CTX *ffi_create_EVP_CIPHER_CTX ();           
static int ffi_EVP_EncryptInit (EVP_CIPHER_CTX *ctx, EVP_CIPHER *type,
                                ___SCMOBJ key, ___SCMOBJ iv);
static int ffi_EVP_EncryptUpdate (EVP_CIPHER_CTX *ctx, ___SCMOBJ out,
                                  ___SCMOBJ in, int start, int end);
static int ffi_EVP_EncryptFinal (EVP_CIPHER_CTX *ctx, ___SCMOBJ out);
static int ffi_EVP_DecryptInit (EVP_CIPHER_CTX *ctx, EVP_CIPHER *type,
                                ___SCMOBJ key, ___SCMOBJ iv);
static int ffi_EVP_DecryptUpdate (EVP_CIPHER_CTX *ctx, ___SCMOBJ out,
                                  ___SCMOBJ in, int start, int end);
static int ffi_EVP_DecryptFinal (EVP_CIPHER_CTX *ctx, ___SCMOBJ out);
END-C
)

(c-define-type EVP_CIPHER "EVP_CIPHER")
(c-define-type EVP_CIPHER*
  (pointer EVP_CIPHER (EVP_CIPHER*)))
(c-define-type EVP_CIPHER_CTX "EVP_CIPHER_CTX")
(c-define-type EVP_CIPHER_CTX*
  (pointer EVP_CIPHER_CTX (EVP_CIPHER_CTX*) "ffi_release_EVP_CIPHER_CTX"))

(define-c-type-predicate EVP_CIPHER? EVP_CIPHER*)
(define-c-type-predicate EVP_CIPHER_CTX? EVP_CIPHER_CTX*)

(define-c-lambda EVP_CIPHER_CTX_create () EVP_CIPHER_CTX*
  "ffi_create_EVP_CIPHER_CTX")
(define-c-lambda EVP_EncryptInit (EVP_CIPHER_CTX* EVP_CIPHER* scheme-object scheme-object) int
  "ffi_EVP_EncryptInit")
(define-c-lambda EVP_EncryptUpdate (EVP_CIPHER_CTX* scheme-object scheme-object int int) int
  "ffi_EVP_EncryptUpdate")
(define-c-lambda EVP_EncryptFinal (EVP_CIPHER_CTX* scheme-object) int
  "ffi_EVP_EncryptFinal")
(define-c-lambda EVP_DecryptInit (EVP_CIPHER_CTX* EVP_CIPHER* scheme-object scheme-object) int
  "ffi_EVP_DecryptInit")
(define-c-lambda EVP_DecryptUpdate (EVP_CIPHER_CTX* scheme-object scheme-object int int) int
  "ffi_EVP_DecryptUpdate")
(define-c-lambda EVP_DecryptFinal (EVP_CIPHER_CTX* scheme-object) int
  "ffi_EVP_DecryptFinal")
(define-c-lambda EVP_CIPHER_CTX_copy (EVP_CIPHER_CTX* EVP_CIPHER_CTX*) int
  "EVP_CIPHER_CTX_copy")

(define-c-lambda/const-pointer EVP_aes_128_ecb () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_128_cbc () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_128_cfb () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_128_ofb () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_128_ctr () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_128_ccm () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_128_gcm () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_128_xts () EVP_CIPHER*)

(define-c-lambda/const-pointer EVP_aes_192_ecb () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_192_cbc () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_192_cfb () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_192_ofb () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_192_ctr () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_192_ccm () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_192_gcm () EVP_CIPHER*)

(define-c-lambda/const-pointer EVP_aes_256_ecb () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_256_cbc () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_256_cfb () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_256_ofb () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_256_ctr () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_256_ccm () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_256_gcm () EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_aes_256_xts () EVP_CIPHER*)

(define-c-lambda EVP_CIPHER_nid (EVP_CIPHER*) int)
(define-c-lambda EVP_CIPHER_block_size (EVP_CIPHER*) int)
(define-c-lambda EVP_CIPHER_key_length (EVP_CIPHER*) int)
(define-c-lambda EVP_CIPHER_iv_length (EVP_CIPHER*) int)
(define-c-lambda/const-pointer EVP_CIPHER_name (EVP_CIPHER*) char-string
  "___result")

(define-c-lambda/const-pointer EVP_CIPHER_CTX_cipher (EVP_CIPHER_CTX*) EVP_CIPHER*)
(define-c-lambda EVP_CIPHER_CTX_nid (EVP_CIPHER_CTX*) int)
(define-c-lambda EVP_CIPHER_CTX_block_size (EVP_CIPHER_CTX*) int)
(define-c-lambda EVP_CIPHER_CTX_key_length (EVP_CIPHER_CTX*) int)
(define-c-lambda EVP_CIPHER_CTX_iv_length (EVP_CIPHER_CTX*) int)

(define-c-lambda/const-pointer EVP_get_cipherbyname (char-string) EVP_CIPHER*)
(define-c-lambda/const-pointer EVP_get_cipherbynid (int) EVP_CIPHER*)

;;; BN
(c-declare #<<END-C
static ___SCMOBJ ffi_BN_free (void *bn);
static BIGNUM *ffi_BN_bin2bn (___SCMOBJ data, int, int);
static int ffi_BN_bn2bin (BIGNUM  *bn, ___SCMOBJ data);
END-C
)           

(c-define-type BN "BIGNUM")
(c-define-type BN* (pointer BN (BN*) "ffi_BN_free"))
(define-c-type-predicate BN? BN*)

(define-c-lambda BN_num_bytes (BN*) int)
(define-c-lambda BN_bin2bn (scheme-object int int) BN*
  "ffi_BN_bin2bn")
(define-c-lambda BN_bn2bin (BN* scheme-object) int
  "ffi_BN_bn2bin")

;;; DH

;;; ffi helpers
(c-declare #<<END-C
static ___SCMOBJ ffi_release_EVP_MD_CTX (void *ptr)
{
  EVP_MD_CTX_destroy (ptr);
  return ___FIX (___NO_ERR);
}

static int ffi_EVP_DigestInit (EVP_MD_CTX *ctx, EVP_MD *type) {
  return EVP_DigestInit_ex (ctx, type, NULL);
}

static int ffi_EVP_DigestUpdate (EVP_MD_CTX *ctx, ___SCMOBJ bytes, int start, int end)
{
  return EVP_DigestUpdate (ctx, U8_DATA (bytes) + start, end - start);
}

static int ffi_EVP_DigestFinal (EVP_MD_CTX *ctx, ___SCMOBJ bytes)
{
  return EVP_DigestFinal_ex (ctx, U8_DATA (bytes), NULL);
}

/* like EVP_MD_CTX_create, no EVP_CIPHER_CTX_create available */
static EVP_CIPHER_CTX *ffi_create_EVP_CIPHER_CTX ()
{
  EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new ();
  if (ctx) {              
    EVP_CIPHER_CTX_init (ctx);
  }                            
  return ctx;
}

/* like EVP_MD_CTX_destroy, no EVP_CIPHER_CTX_destroy available */
static ___SCMOBJ ffi_release_EVP_CIPHER_CTX (void *ptr)
{
  EVP_CIPHER_CTX_cleanup (ptr);
  EVP_CIPHER_CTX_free (ptr);
  return ___FIX (___NO_ERR);
}

static int ffi_EVP_EncryptInit (EVP_CIPHER_CTX *ctx, EVP_CIPHER *type,
                                ___SCMOBJ key, ___SCMOBJ iv)
{
  return EVP_EncryptInit_ex (ctx, type, NULL, U8_DATA (key), U8_DATA (iv));      
}

static int ffi_EVP_EncryptUpdate (EVP_CIPHER_CTX *ctx, ___SCMOBJ out,
                                  ___SCMOBJ in, int start, int end)
{
  int r, olen;
  r = EVP_EncryptUpdate (ctx, U8_DATA (out), &olen,
                         U8_DATA (in) + start, end - start);
  if (r) {
    return olen;
  } else {
    return -1;
  } 
}

static int ffi_EVP_EncryptFinal (EVP_CIPHER_CTX *ctx, ___SCMOBJ out)
{
  int r, olen;
  r = EVP_EncryptFinal_ex (ctx, U8_DATA (out), &olen);
  if (r) {
    return olen;
  } else {
    return -1;
  } 
}

static int ffi_EVP_DecryptInit (EVP_CIPHER_CTX *ctx, EVP_CIPHER *type,
                                ___SCMOBJ key, ___SCMOBJ iv)
{
  return EVP_DecryptInit_ex (ctx, type, NULL, U8_DATA (key), U8_DATA (iv));      
}

static int ffi_EVP_DecryptUpdate (EVP_CIPHER_CTX *ctx, ___SCMOBJ out,
                                  ___SCMOBJ in, int start, int end)
{
  int r, olen;
  r = EVP_DecryptUpdate (ctx, U8_DATA (out), &olen,
                         U8_DATA (in) + start, end - start);    
  if (r) {
    return olen;
  } else {
    return -1;
  } 
}

static int ffi_EVP_DecryptFinal (EVP_CIPHER_CTX *ctx, ___SCMOBJ out)
{
  int r, olen;
  r = EVP_DecryptFinal_ex (ctx, U8_DATA (out), &olen);
  if (r) {
    return olen;
  } else {
    return -1;
  } 
}

static ___SCMOBJ ffi_BN_free (void *bn)
{
 BN_free (bn);
 return ___FIX (___NO_ERR);
}

static BIGNUM *ffi_BN_bin2bn (___SCMOBJ data, int start, int end)
{
  return BN_bin2bn (U8_DATA (data) + start, end -start, NULL);
}

static int ffi_BN_bn2bin (BIGNUM *bn, ___SCMOBJ data)
{
 return BN_bn2bin (bn, U8_DATA (data));
}
END-C
)
