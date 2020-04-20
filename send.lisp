#|
 This file is a part of Courier
 (c) 2019 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:courier)

(defun compile-mail (template &rest args)
  ;; FIXME: softdrink apply stylesheet
  (apply #'r-clip:process
         (etypecase template
           (string template)
           (pathname (@template (namestring template))))
         :copyright (config :copyright)
         :software-title (config :title)
         :software-version (asdf:component-version (asdf:find-system :courier))
         args))

(defun extract-plaintext (html)
  ;; KLUDGE: This is real dumb.
  ;; FIXME: links do not get retained
  (with-output-to-string (out)
    (lquery:$ html "body" (text) (each (lambda (text) (write-line text out))))))

(defun extract-subject (html)
  (lquery:$1 html "head title" (text)))

(defun format-mail (text)
  (etypecase text
    (string
     (values text))
    (plump:node
     (values (extract-plaintext text)
             (plump:serialize text NIL)))))

(defun send (host to subject message &key plain reply-to message-id campaign unsubscribe)
  (multiple-value-bind (extracted html) (format-mail message)
    (l:trace :courier.mail "Sending to ~a via ~a/~a:~a"
             to
             (dm:field host "address")
             (dm:field host "hostname")
             (dm:field host "port"))
    (let ((cl-smtp::*x-mailer* #.(format NIL "Courier Mailer ~a" (asdf:component-version (asdf:find-system :courier)))))
      (cl-smtp:send-email
       (copy-seq (dm:field host "hostname"))
       (dm:field host "address")
       to subject (or plain extracted)
       :html-message html
       :extra-headers `(,@(when campaign
                            `(("X-Campaign" ,(princ-to-string campaign))
                              ("X-campaignid" ,(princ-to-string campaign))
                              ("List-ID" ,(princ-to-string campaign))
                              ("Message-ID" ,(format NIL "<~a@courier.~a>"
                                                     (hash (format NIL "~a-~a" message-id campaign))
                                                     (dm:field host "hostname")))))
                        ,@(when unsubscribe
                            `(("List-Unsubscribe" ,unsubscribe)
                              ("List-Unsubscribe-Post" "List-Unsubscribe=One-Click"))))
       :ssl (ecase (dm:field host "encryption")
              (0 NIL) (1 :starttls) (2 :tls))
       :port (dm:field host "port")
       :reply-to reply-to
       :authentication (when (dm:field host "username")
                         (list :plain
                               (dm:field host "username")
                               (decrypt (dm:field host "password"))))
       :display-name (dm:field host "display-name")))))

(defun mail-template-args (campaign mail subscriber)
  (list* :mail-receipt-image (mail-receipt-url mail subscriber)
         :mail-url (mail-url mail subscriber)
         :archive-url (archive-url subscriber)
         :unsubscribe-url (unsubscribe-url subscriber)
         :title (dm:field mail "title")
         :subject (dm:field mail "subject")
         :campaign (dm:field campaign "title")
         :description (dm:field campaign "description")
         :reply-to (dm:field campaign "reply-to")
         :to (dm:field subscriber "address")
         :name (dm:field subscriber "name")
         :tags (list-tags subscriber)
         :time (get-universal-time)
         :address (dm:field campaign "address")
         (subscriber-attributes subscriber)))

(defun compile-mail-content (campaign mail subscriber &key (template (dm:field campaign "template")) (format 'html-format))
  (let ((args (mail-template-args campaign mail subscriber)))
    (apply #'compile-mail template
           (list* :body (compile-mail-body (dm:field mail "body") args
                                           :campaign campaign
                                           :subscriber subscriber
                                           :mail mail
                                           :format format)
                  args))))

(defun send-mail (mail subscriber)
  (l:debug :courier.mail "Sending ~a to ~a" mail subscriber)
  (let* ((campaign (ensure-campaign (dm:field mail "campaign")))
         (host (ensure-host (dm:field campaign "host")))
         html plain)
    (handler-bind ((error (lambda (e)
                            (declare (ignore e))
                            (mark-mail-sent mail subscriber :compile-falied))))
      (setf html (compile-mail-content campaign mail subscriber))
      (setf plain (compile-mail-content campaign mail subscriber :template #p"email/text-template.ctml" :format 'plain-format)))
    (handler-bind ((error (lambda (e)
                            (declare (ignore e))
                            (mark-mail-sent mail subscriber :send-failed))))
      (send host (dm:field subscriber "address")
            (extract-subject html)
            html
            :plain (plump:text plain)
            :reply-to (dm:field campaign "reply-to")
            :message-id (dm:id mail)
            :campaign (dm:field mail "campaign")
            :unsubscribe (unsubscribe-url subscriber)))
    (mark-mail-sent mail subscriber)))

(defun send-system-mail (body address host campaign &rest args)
  (let ((html (apply #'compile-mail #p"email/system-template.ctml"
                     (list* :body (compile-mail-body body args)
                            args))))
    (send host address
          (extract-subject html)
          html
          :reply-to (if campaign
                        (dm:field campaign "reply-to")
                        (dm:field host "address"))
          :campaign (when campaign
                      (dm:id campaign)))))