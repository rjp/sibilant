(defvar tokenize
  (setf sibilant.tokenize
	(lambda (string)
	  (defvar tokens (list)
	    parse-stack (list tokens)
	    specials (list))

	  (defun accept-token (token)
	    (send (get parse-stack 0) push token))

	  (defun increase-nesting ()
	    (defvar new-arr (list))
	    (accept-token new-arr)
	    (parse-stack.unshift new-arr))

	  (defun decrease-nesting ()
	    (specials.shift)
	    (parse-stack.shift)
	    (when (zero? parse-stack.length)
	      (throw (concat "unbalanced parens:\n"
			     (call inspect parse-stack)))))

	  (defun handle-token (token)
	    (defvar special (first token)
	      token token)
	    (if (= special "'")
		(progn
		  (setf token (token.slice 1))
		  (increase-nesting)
		  (accept-token 'quote))
	      (setf special false))
	    (specials.unshift (as-boolean special))
	    (if (= token "(") (increase-nesting)
	      (progn
		(if (= token ")") (decrease-nesting)
		  (if (token.match /^-?[0-9.]+$/)
		      (accept-token (parse-float token))
		    (accept-token token)))
		(when (specials.shift)
		  (decrease-nesting)))))

          (defvar regexen (list "(\\/(\\\\\\\/|[^\\/\\n])+\\/[glim]*)"
                                "(;.*)"
                                "(\"(([^\"]|(\\\\\"))*[^\\\\])?\")"
                                "(-?[0-9.]+)"
                                "[&']?[*.$a-z-][*.a-z0-9-]*(\\?|!)?"
                                "([><=!\\+\\/\\*-]+)"
                                "(\\'?\\()" "\\)")
            master-regex (regex (join "|" regexen) 'g))

	  (chain string
		 (match master-regex)
                 (for-each handle-token))
			     
	  (when (> parse-stack.length 1)
	    (error "unexpected EOF, probably missing a )\n"
		   (call inspect (first parse-stack))))
	  tokens)))

(force-semi)

(defun indent (&rest args)
  (concat
   (chain (compact args)
	  (join "\n")
	  (replace /^/ "\n")
	  (replace /\n/g "\n  "))
   "\n"))

(defun construct-hash (array-of-arrays)
  (inject (hash) array-of-arrays
	  (lambda (object item)
	    (set object (first item) (get object (second item)))
	    object)))

(defvar macros (hash))
(set sibilant 'macros macros)

(set macros 'return
     (lambda (token)
       (defvar default-return (concat "return " (translate token)))
       
       (if (array? token)
	   (switch (first token)
		   ('(return throw progn) (translate token))
                   ('delete
                    (defvar delete-macro (get macros 'delete))
                    (if (< token.length 3) default-return
                      (concat (apply delete-macro (token.slice 1 -1))
                              "\nreturn "
                              (delete-macro (last token)))))
		   ('setf
		    (if (< token.length 4) default-return
		      (concat (apply macros.setf
				     (token.slice 1 (- token.length 2)))
			      "\nreturn "
			      (apply macros.setf (token.slice -2)))))
		   ('set
		    (if (< token.length 5) default-return
		      (progn
			(defvar obj (second token)
			  non-return-part (token.slice 2 (- token.length 2))
			  return-part (token.slice -2))
			(non-return-part.unshift obj)
			(return-part.unshift obj)
			(concat (apply macros.set non-return-part)
				"\nreturn "
				(apply macros.set return-part)))))
		   (default default-return))
	 default-return)))


(defun macros.statement (&rest args)
  (concat (apply macros.call args) ";\n"))

(defun macros.progn (&rest body)
  (set body (- body.length 1)
       (list 'return (get body (- body.length 1))))
  (join "\n"
	(map body (lambda (arg)
		    (concat (translate arg) ";")))))

(defun macros.call (fn-name &rest args)
  (concat (translate fn-name)
	  "(" (join ", " (map args translate)) ")"))

(defun macros.defun (fn-name &rest args-and-body)
  (defvar fn-name-tr (translate fn-name)
    start (if (/\./ fn-name-tr) "" "var "))
  (concat start fn-name-tr " = "
	  (apply macros.lambda args-and-body)
	  ";\n"))

(defun macros.defmacro (name &rest args-and-body)
  (defvar js (apply macros.lambda args-and-body)
    name (translate name))
  (try (set macros name (eval js))
       (error (concat "error in parsing macro "
		      name ":\n" (indent js))))
  undefined)

(defun macros.concat (&rest args)
  (concat "(" (join " + " (map args translate)) ")"))

(defun transform-args (arglist)
  (defvar last undefined
          args (list))
  (each (arg) arglist
	(if (= (first arg) "&") (setf last (arg.slice 1))
	  (progn
	    (args.push (list (or last 'required) arg))
	    (setf last null))))

  (when last
    (error (concat "unexpected argument modifier: " last)))

  args)


(defun macros.reverse (arr)
  (defvar reversed (list))
  (each (item) arr (reversed.unshift item))
  reversed)

(defvar reverse macros.reverse)

(defun build-args-string (args rest)
  (defvar args-string ""
          optional-count 0)

  (each (arg option-index) args
      (when (= (first arg) 'optional)
	(setf
	 args-string
	 (concat
	  args-string
	  "if (arguments.length < "
	  (- args.length optional-count) ")"
	  " // if " (translate (second arg)) " is missing"
	  (indent
	   (concat "var "
		   (chain
		    (map (args.slice (+ option-index 1))
			 (lambda (arg arg-index)
			   (concat (translate (second arg)) " = "
				   (translate (second (get args
							   (+ option-index
							      arg-index)))))))
		    (reverse)
		    (concat (concat (translate (second arg)) " = undefined"))
		    (join ", "))
		   ";"))))
	(incr optional-count)))

  (if (defined? rest)
      (concat args-string
	      "var " (translate (second rest))
	      " = Array.prototype.slice.call(arguments, "
	      args.length ");\n")
    args-string))

(defun build-comment-string (args)
  (if (empty? args) ""
    (concat "// "
	    (join " "
		  (map args
		       (lambda (arg)
			 (concat (translate (second arg)) ":" (first arg))))))))

;; brain 'splode
(defun macros.lambda (arglist &rest body)
  (defvar args (transform-args arglist)
    rest (first (select args
			(lambda (arg)
			  (= 'rest (first arg)))))
    doc-string undefined)

  (set body (- body.length 1)
       (list 'return (get body (- body.length 1))))

  (when (and (= (typeof (first body)) 'string)
	     (send (first body) match /^".*"$/))
    (setf doc-string
	  (concat "/* " (eval (body.shift)) " */\n")))

  (defvar no-rest-args (if rest (args.slice 0 -1) args)
    args-string (build-args-string no-rest-args rest)
    comment-string (build-comment-string args))

  (concat "(function("
	  (join ", " (map args (lambda (arg) (translate (second arg)))))
	  ") {"
	  (indent comment-string doc-string args-string
		  (join "\n"
			(map body
			     (lambda (stmt)
			       (concat (translate stmt) ";")))))
	  "})"))


(defun macros.quote (item)
  (if (= "Array" item.constructor.name)
      (concat "[ " (join ", " (map item macros.quote)) " ]")
    (if (= 'number (typeof item)) item
      (concat "\"" (literal item) "\""))))

(defun macros.hash (&rest pairs)
  (when (odd? pairs.length)
    (error (concat
	    "odd number of key-value pairs in hash: "
	    (call inspect pairs))))
  (defvar pair-strings
    (bulk-map pairs (lambda (key value)
		      (concat (translate key) ": "
			      (translate value)))))
  (if (>= 1 pair-strings.length)
      (concat "{ " (join ", " pair-strings) " }")
    (concat "{" (indent (join ",\n" pair-strings)) "}")))


(defun literal (string)
  (inject (chain string
		 (replace /\*/g "_")
		 (replace /\?$/ "__QUERY")
		 (replace /!$/  "__BANG"))
	  (string.match /-(.)/g)
	  (lambda (return-string match)
	    (return-string.replace match
		  (send (second match) to-upper-case)))))


(defun translate (token hint)
  (defvar hint hint)
  (when (and hint (undefined? (get macros hint)))
    (setf hint undefined))

  (when (defined? token)
    (try
     (if (array? token)
	 (if (defined? (get macros (translate (first token))))
	     (apply (get macros (translate (first token))) (token.slice 1))
	   (apply (get macros (or hint 'call)) token))
       (if (and (string? token) (token.match /^\$?[*\.a-z-]+([0-9])*(!|\?)?$/))
	   (literal token)
	 (if (and (string? token) (token.match /^;/
					))
	     (token.replace /^;+/ "//"
		   )
	   (if (and (string? token)
                    (= "\"" (first token))
                    (= "\"" (last token)))
	       (chain token (split "\n") (join "\\n\" +\n\""))
	     token))))
     (error (concat e.stack "\n"
		    "Encountered when attempting to process:\n"
		    (indent (call inspect token)))))))


(set sibilant 'translate translate)

(defun translate-all (contents)
  (defvar buffer "")
  (each (token) (tokenize contents)
	(defvar line (translate token "statement"))
	(when line (setf buffer (concat buffer line "\n"))))
  buffer)

(set sibilant 'translate-all translate-all)

