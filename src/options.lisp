(defvar import (require "sibilant/import"))

(import (require "sibilant/functional"))

(defun extract-options (config &optional args)
  (defvar args (or args (process.argv.slice 2))
    default-label 'unlabeled
    current-label default-label
    config (or config (hash))
    unlabeled (list))

  (defun label? (item) (and (string? item) (send /^-/ test item)))

  (defun synonym-lookup (item)
    (defvar config-entry (get config item))
    (if (string? config-entry)
	(synonym-lookup config-entry)
      item))

  (defun takes-args? (item)
    (!= false (get config (label-for item))))

  (setf default-label (synonym-lookup default-label)
	current-label default-label)

  (defun label-for (item)
    (synonym-lookup (item.replace /^-+/ "")))

  (defun add-value (hash key value)
    (defvar current-value (get hash key))
    (when (undefined? current-value)
      (setf current-value (list))
      (set hash key current-value))
    (when (!= true value)
      (current-value.push value)))

  (defun reset-label ()
    (setf current-label default-label))

  (inject (hash) args
	  (lambda (return-hash item index)
	    (if (label? item)
		(progn
		  (setf current-label (label-for item))
		  (add-value return-hash current-label true)
		  (when (not (takes-args? item)) (reset-label)))
	      (progn
		(add-value return-hash current-label item)
		(reset-label)))
	    return-hash)))

(defun process-options (&optional config)
  (defvar options (extract-options config))
  (when config
    (defun handle-pair (key value)
       (defvar handle (get config key))
       (when (string? handle) (handle-pair handle value))
       (when (function? handle) (apply handle value)))
     (send (keys options) for-each
	   (lambda (key) (handle-pair key (get options key)))))

  options)
    
(set module 'exports process-options)
