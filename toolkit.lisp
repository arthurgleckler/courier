#|
 This file is a part of Courier
 (c) 2019 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:courier)

(defun encrypt (thing)
  (cryptos:encrypt thing (config :private-key)))

(defun decrypt (thing)
  (cryptos:decrypt thing (config :private-key)))

(defun hash (thing)
  (let ((thing (etypecase thing
                 (string thing)
                 (integer (princ-to-string thing)))))
    (cryptos:pbkdf2-hash thing (config :private-key))))

(defun check-hash (hash thing &optional (argument 'token))
  (unless (equal hash (hash thing))
    (error 'api-argument-invalid :argument argument)))

(defun url> (uri &key query fragment)
  (uri-to-url uri :representation :external
                  :query query
                  :fragment fragment))

(defmacro setf-dm-fields (model &rest vars)
  (let ((modelg (gensym "MODEL")))
    `(let ((,modelg ,model))
       ,@(loop for var in vars
               collect (destructuring-bind (var field) (radiance::enlist var (string-downcase var))
                         `(etypecase ,var
                            (null)
                            ((or string integer)
                             (setf (dm:field ,modelg ,field) ,var))
                            (dm:data-model
                             (setf (dm:field ,modelg ,field) (dm:id ,var))))))
       ,modelg)))

(defun check-title (title)
  (when (string= title "")
    (error 'api-argument-invalid :argument 'title :message "The title cannot be empty."))
  (when (string-equal title "new")
    (error 'api-argument-invalid :argument 'title :message "The title cannot be \"new\"."))
  (when (find #\/ title)
    (error 'api-argument-invalid :argument 'title :message "The title cannot contain a slash.")))

(defun check-title-exists (collection title query)
  (check-title title)
  (when (and title (< 0 (db:count collection query)))
    (error 'api-argument-invalid
           :argument 'title
           :message (format NIL "A ~(~a~) titled ~s already exists."
                            collection title))))
