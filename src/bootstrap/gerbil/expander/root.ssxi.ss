prelude: :gerbil/compiler/ssxi
package: gerbil/expander

(begin
  (declare-type
   gx#root-context:::init!
   (@case-lambda
    (1 gx#root-context:::init!__0)
    (2 gx#root-context:::init!__opt-lambda12627)))
  (declare-method gx#root-context::t :init! gx#root-context:::init! #f)
  (declare-type
   gx#top-context:::init!
   (@case-lambda
    (1 gx#top-context:::init!__0)
    (2 gx#top-context:::init!__opt-lambda12605)))
  (declare-method gx#top-context::t :init! gx#top-context:::init! #f)
  (declare-type
   gx#expander-context::bind-core-syntax-expanders!
   (@case-lambda
    (1 gx#expander-context::bind-core-syntax-expanders!__0)
    (2 gx#expander-context::bind-core-syntax-expanders!__opt-lambda12458)))
  (declare-method
   gx#expander-context::t
   bind-core-syntax-expanders!
   gx#expander-context::bind-core-syntax-expanders!
   #f)
  (declare-type
   gx#expander-context::bind-core-macro-expanders!
   (@case-lambda
    (1 gx#expander-context::bind-core-macro-expanders!__0)
    (2 gx#expander-context::bind-core-macro-expanders!__opt-lambda12352)))
  (declare-method
   gx#expander-context::t
   bind-core-macro-expanders!
   gx#expander-context::bind-core-macro-expanders!
   #f))
