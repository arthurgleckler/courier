#|
 This file is a part of Courier
 (c) 2019 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:courier)

(defvar *file-directory*
  (environment-module-pathname #.*package* :data "files/"))

(defun campaign-file-directory (campaign)
  (merge-pathnames
   (make-pathname :directory `(:relative ,(princ-to-string (ensure-id campaign))))
   *file-directory*))

(defparameter *attribute-types*
  '((0 "text" "Free-Form Text")
    (1 "number" "Number")
    (2 "url" "URL")
    (3 "date" "Date")
    (4 "color" "Color")
    (5 "tel" "Telephone Number")))

(define-trigger db:connected ()
  (db:create 'host
             '((author :id)
               (title (:varchar 32))
               (display-name (:varchar 32))
               (address (:varchar 64))
               (hostname (:varchar 64))
               (port :integer)
               (username (:varchar 32))
               (password (:varchar 128))
               (encryption (:integer 1))
               (batch-size :integer)
               (batch-cooldown :integer)
               (last-send-time (:integer 5))
               (confirmed :boolean))
             :indices '(author title))

  (db:create 'campaign
             '((host (:id host))
               (author :id)
               (title (:varchar 32))
               (description :text)
               (time (:integer 5))
               (reply-to (:varchar 64))
               (template :text)
               (address :text))
             :indices '(author title))

  (db:create 'campaign-access
             '((campaign (:id campaign))
               (user :id)
               (access-field (:integer 2))))

  (db:create 'subscriber
             '((campaign (:id campaign))
               (name (:varchar 64))
               (address (:varchar 64))
               (signup-time (:integer 5))
               (status (:integer 1)))
             :indices '(campaign status))

  (db:create 'attribute
             '((campaign (:id campaign))
               (title (:varchar 32))
               (type (:integer 1))
               (required :boolean))
             :indices '(campaign))

  (db:create 'attribute-value
             '((attribute (:id attribute))
               (subscriber (:id subscriber))
               (value (:varchar 64)))
             :indices '(attribute subscriber))

  (db:create 'mail
             '((campaign (:id campaign))
               (title (:varchar 32))
               (subject (:varchar 128))
               (body :text)
               (time (:integer 5)))
             :indices '(campaign title))

  (db:create 'mail-receipt
             '((mail (:id mail))
               (subscriber (:id subscriber))
               (time (:integer 5)))
             :indices '(mail subscriber))

  (db:create 'mail-log
             '((mail (:id mail))
               (subscriber (:id subscriber))
               (send-time (:integer 5))
               (status (:integer 1)))
             :indices '(mail subscriber))

  (db:create 'mail-queue
             '((host (:id host))
               (subscriber (:id subscriber))
               (mail (:id mail))
               (send-time (:integer 5))
               (attempts (:integer 1)))
             :indices '(host subscriber))

  (db:create 'tag
             '((campaign (:id campaign))
               (title (:varchar 32))
               (description :text))
             :indices '(campaign))

  (db:create 'tag-table
             '((tag (:id tag))
               (subscriber (:id subscriber)))
             :indices '(tag subscriber))

  (db:create 'link
             '((campaign (:id campaign))
               (hash (:varchar 44))
               (url (:varchar 256)))
             :indices '(campaign hash))

  (db:create 'link-receipt
             '((link (:id link))
               (subscriber (:id subscriber))
               (time (:integer 5)))
             :indices '(link subscriber))

  (db:create 'trigger
             '((campaign (:id campaign))
               (description :text)
               (source-type (:integer 1))
               (source-id :id)
               (target-type (:integer 1))
               (target-id :id)
               (delay (:integer 5))
               (tag-constraint (:varchar 64))
               (normalized-constraint :text))
             :indices '(campaign source-type source-id))

  (db:create 'sequence
             '((campaign (:id campaign))
               (title :text))
             :indices '(campaign))
  
  (db:create 'sequence-trigger
             '((sequence (:id sequence))
               (trigger (:id trigger)))
             :indices '(sequence))

  (db:create 'file
             '((campaign (:id campaign))
               (author :id)
               (filename (:varchar 64))
               (mime-type (:varchar 32)))
             :indices '(campaign)))

(defun ensure-id (id-ish)
  (etypecase id-ish
    (db:id id-ish)
    (dm:data-model (dm:id id-ish))
    (T (db:ensure-id id-ish))))

(defun make-host (&key author title display-name address hostname port username password (encryption 1) (batch-size 10) (batch-cooldown 60) (save T))
  (check-title-exists 'host title (db:query (:and (:= 'author author)
                                                  (:= 'title title))))
  (dm:with-model host ('host NIL)
    (setf-dm-fields host author title display-name address hostname port username encryption batch-size batch-cooldown)
    (when password (setf (dm:field host "password") (encrypt password)))
    (setf (dm:field host "confirmed") NIL)
    (setf (dm:field host "last-send-time") 0)
    (when save (dm:insert host))
    host))

(defun edit-host (host &key author title display-name address hostname port username password encryption batch-size batch-cooldown confirmed save)
  (let ((host (ensure-host host)))
    (setf-dm-fields host author title display-name address hostname port username password encryption batch-size batch-cooldown confirmed)
    (when save (dm:save host))
    host))

(defun ensure-host (host-ish &optional (user (auth:current)))
  (or
   (etypecase host-ish
     (dm:data-model host-ish)
     (db:id (dm:get-one 'host (db:query (:= '_id host-ish))))
     (T (or (dm:get-one 'host (db:query (:and (:= 'author (user:id user))
                                              (:= 'title host-ish))))
            (dm:get-one 'host (db:query (:= '_id (db:ensure-id host-ish)))))))
   (error 'request-not-found :message "No such host.")))

(defun delete-host (host)
  (db:with-transaction ()
    ;; Don't delete campaigns, just set the host to NULL
    (db:update 'campaign (db:query (:= 'host (dm:id host))) `(("host" . NIL)))
    (dm:delete host)
    host))

(defun list-hosts (&optional user &key amount (skip 0))
  (if user
      (dm:get 'host (db:query (:= 'author (user:id user)))
              :sort '((title :asc)) :amount amount :skip skip)
      (dm:get 'host (db:query :all)
              :sort '((title :asc)) :amount amount :skip skip)))

(defun make-campaign (author host title &key description reply-to template attributes address (save T))
  (check-title-exists 'campaign title (db:query (:and (:= 'author author)
                                                      (:= 'title title))))
  (dm:with-model campaign ('campaign NIL)
    (setf-dm-fields campaign title host description reply-to template address)
    (setf (dm:field campaign "author") (user:id author))
    (when save
      (db:with-transaction ()
        (dm:insert campaign)
        (loop for (attribute type required) in attributes
              do (setf type (etypecase type
                              (string (parse-integer type))
                              (integer type)))
                 (unless (find type *attribute-types* :key #'car)
                   (error "Invalid attribute type ~s.~%Must be one of ~s." type (mapcar #'car *attribute-types*)))
                 (db:insert 'attribute `(("campaign" . ,(dm:id campaign))
                                         ("title" . ,attribute)
                                         ("type" . ,type)
                                         ("required" . ,required))))
        (make-subscriber campaign
                         (or (user:field "name" author) (user:username author))
                         reply-to
                         :status :active)))
    campaign))

(defun edit-campaign (campaign &key host author title description reply-to template attributes address (save T))
  (let ((campaign (ensure-campaign campaign)))
    (setf-dm-fields campaign host author title description reply-to template address)
    (when save
      (db:with-transaction ()
        (dm:save campaign)
        (let ((existing (list-attributes campaign)))
          (loop for (attribute type required) in attributes
                for previous = (find attribute existing :key (lambda (dm) (dm:field dm "name")) :test #'string=)
                do (setf type (etypecase type
                                (string (parse-integer type))
                                (integer type)))
                   (unless (find type *attribute-types* :key #'car)
                     (error "Invalid attribute type ~s.~%Must be one of ~s." type (mapcar #'car *attribute-types*)))
                   (cond (previous
                          (setf existing (delete previous existing))
                          (setf (dm:field previous "title") attribute)
                          (setf (dm:field previous "type") type)
                          (setf (dm:field previous "required") required)
                          (dm:save previous))
                         (T
                          (db:insert 'attribute `(("campaign" . ,(dm:id campaign))
                                                  ("title" . ,attribute)
                                                  ("type" . ,type)
                                                  ("required" . ,required))))))
          (dolist (attribute existing)
            (db:remove 'attribute-value (db:query (:= 'attribute (dm:id attribute))))
            (dm:delete attribute)))))
    campaign))

(defun campaign-author (campaign)
  (dm:get-one 'subscriber (db:query (:and (:= 'campaign (dm:id campaign))
                                          (:= 'address (dm:field campaign "reply-to"))))))

(defun ensure-campaign (campaign-ish &optional (user (auth:current)))
  (or
   (etypecase campaign-ish
     (dm:data-model campaign-ish)
     (db:id (dm:get-one 'campaign (db:query (:= '_id campaign-ish))))
     (string (or (dm:get-one 'campaign (db:query (:and (:= 'author (user:id user))
                                                       (:= 'title campaign-ish))))
                 (dm:get-one 'campaign (db:query (:= '_id (db:ensure-id campaign-ish)))))))
   (error 'request-not-found :message "No such campaign.")))

(defun delete-campaign (campaign)
  (db:with-transaction ()
    (let ((directory (campaign-file-directory campaign)))
      (mapcar #'delete-sequence (list-sequences campaign))
      (mapcar #'delete-subscriber (list-subscribers campaign))
      (mapcar #'delete-trigger (list-triggers campaign))
      (mapcar #'delete-mail (list-mails campaign))
      (mapcar #'delete-tag (list-tags campaign))
      (mapcar #'delete-link (list-links campaign))
      (db:remove 'file (db:query (:= 'campaign (dm:id campaign))))
      (db:remove 'attribute (db:query (:= 'campaign (dm:id campaign))))
      (dm:delete campaign)
      (uiop:delete-directory-tree directory :validate (constantly T) :if-does-not-exist :ignore))))

(defun list-campaigns (&optional user &key amount (skip 0))
  (if user
      (append ;; KLUDGE: workaround for JOIN thrashing _id when not inner join
       (dm:get 'campaign (db:query (:= 'author (user:id user)))
               :sort '((title :asc)) :amount amount :skip skip)
       (dm:get (rdb:join (campaign _id) (campaign-access campaign))
               (db:query (:= 'user (user:id user)))
               :sort '((title :asc)) :amount amount :skip skip :hull 'campaign))
      (dm:get 'campaign (db:query :all)
              :sort '((title :asc)) :amount amount :skip skip)))

(defun list-attributes (campaign &key amount (skip 0))
  (when (dm:id campaign)
    (dm:get 'attribute (db:query (:= 'campaign (ensure-id campaign)))
            :sort '((title :asc)) :amount amount :skip skip)))

(defun set-access (user campaign &key access-field (access-level 0))
  (let ((access (or (dm:get-one 'campaign-access (db:query (:and (:= 'campaign (ensure-id campaign))
                                                                 (:= 'user (user:id user)))))
                    (dm:hull 'campaign-access)))
        (access-field (or access-field (access-field access-level))))
    (cond ((<= access-field 0)
           (unless (dm:hull-p access)
             (dm:delete access)))
          (T
           (setf-dm-fields access campaign access-field)
           (setf (dm:field access "user") (user:id user))
           (if (dm:hull-p access)
               (dm:insert access)
               (dm:save access))))))

(defun list-access (campaign &key amount (skip 0))
  (dm:get 'campaign-access (db:query (:= 'campaign (ensure-id campaign)))
          :sort `((user :asc)) :amount amount :skip skip))

(defun make-subscriber (campaign name address &key attributes tags (status :unconfirmed) (signup-time (get-universal-time)) (save t))
  (db:with-transaction ()
    (when (< 0 (db:count 'subscriber (db:query (:and (:= 'campaign (dm:id campaign))
                                                     (:= 'address address)))))
      (error 'api-argument-invalid :argument 'address :message "This email address is already subscribed."))
    (dm:with-model subscriber ('subscriber NIL)
      (setf-dm-fields subscriber campaign name address)
      (setf (dm:field subscriber "status") (user-status-id status))
      (setf (dm:field subscriber "signup-time") signup-time)
      (when save
        (dm:insert subscriber)
        (loop for (attribute . value) in attributes
              do (dm:with-model attribute-value ('attribute-value NIL)
                   (setf (dm:field attribute-value "attribute") (ensure-id attribute))
                   (setf (dm:field attribute-value "subscriber") (dm:id subscriber))
                   (setf (dm:field attribute-value "value") value)
                   (dm:insert attribute-value)))
        (loop for tag in tags
              do (tag subscriber tag))
        (when (eql :active status)
          (process-triggers subscriber campaign)))
      subscriber)))

(defun edit-subscriber (subscriber &key name address attributes tags status (save T))
  (db:with-transaction ()
    (let ((subscriber (ensure-subscriber subscriber)))
      (setf-dm-fields subscriber name address)
      (setf (dm:field subscriber "status") (user-status-id status))
      (when save
        (dm:save subscriber)
        (loop for (attribute . value) in attributes
              do (let ((attribute-value (or (dm:get-one 'attribute-value (db:query (:and (:= 'attribute (ensure-id attribute))
                                                                                         (:= 'subscriber (dm:id subscriber)))))
                                            (dm:hull 'attribute-value))))
                   (setf (dm:field attribute-value "attribute") (ensure-id attribute))
                   (setf (dm:field attribute-value "subscriber") (dm:id subscriber))
                   (setf (dm:field attribute-value "value") value)
                   (if (dm:hull-p attribute-value)
                       (dm:insert attribute-value)
                       (dm:save attribute-value))))
        (db:remove 'tag-table (db:query (:= 'subscriber (dm:id subscriber))))
        (loop for tag in tags
              do (tag subscriber tag))
        (when (eql :active status)
          (process-triggers subscriber (ensure-campaign (dm:field subscriber "campaign")))))
      subscriber)))

(defun ensure-subscriber (subscriber-ish)
  (or
   (etypecase subscriber-ish
     (dm:data-model subscriber-ish)
     (T (dm:get-one 'subscriber (db:query (:= '_id (db:ensure-id subscriber-ish))))))
   (error 'request-not-found :message "No such subscriber.")))

(defun delete-subscriber (subscriber)
  (db:with-transaction ()
    (db:remove 'attribute-value (db:query (:= 'subscriber (dm:id subscriber))))
    (db:remove 'mail-receipt (db:query (:= 'subscriber (dm:id subscriber))))
    (db:remove 'mail-log (db:query (:= 'subscriber (dm:id subscriber))))
    (db:remove 'mail-queue (db:query (:= 'subscriber (dm:id subscriber))))
    (db:remove 'tag-table (db:query (:= 'subscriber (dm:id subscriber))))
    (db:remove 'mail-receipt (db:query (:= 'subscriber (dm:id subscriber))))
    (dm:delete subscriber)))

(defun list-subscribers (thing &key amount (skip 0) query)
  (macrolet ((query (clause)
               `(if query
                    (let ((query (prepare-query query)))
                      (db:query (:and ,clause
                                      (:or (:matches 'name query)
                                           (:matches 'address query)))))
                    (db:query ,clause))))
    (ecase (dm:collection thing)
      (campaign
       (dm:get 'subscriber (query (:= 'campaign (dm:id thing)))
               :sort '((signup-time :DESC)) :amount amount :skip skip))
      (tag
       (dm:get (rdb:join (subscriber _id) (tag-table subscriber)) (query (:= 'tag (dm:id thing)))
               :sort '((signup-time :DESC)) :amount amount :skip skip :hull 'subscriber))
      (link
       (dm:get (rdb:join (subscriber _id) (link-receipt subscriber)) (query (:= 'link (dm:id thing)))
               :sort '((signup-time :DESC)) :amount amount :skip skip :hull 'subscriber)))))

(defun subscriber-attributes (subscriber)
  (loop for attribute in (db:select (rdb:join (attribute _id) (attribute-value attribute))
                                    (db:query (:= 'subscriber (ensure-id subscriber))))
        collect (gethash "title" attribute)
        collect (gethash "value" attribute)))

(defun make-mail (campaign &key title subject body (save T))
  (let ((campaign (ensure-campaign campaign)))
    (dm:with-model mail ('mail NIL)
      (setf-dm-fields mail title subject body campaign)
      (setf (dm:field mail "time") (get-universal-time))
      (when save
        (dm:insert mail))
      mail)))

(defun edit-mail (mail &key title subject body (save T))
  (let ((mail (ensure-mail mail)))
    (setf-dm-fields mail title subject body)
    (when save (dm:save mail))
    mail))

(defun ensure-mail (mail-ish)
  (or
   (etypecase mail-ish
     (dm:data-model mail-ish)
     (db:id (dm:get-one 'mail (db:query (:= '_id mail-ish))))
     (string (ensure-mail (db:ensure-id mail-ish))))
   (error 'request-not-found :message "No such mail.")))

(defun delete-mail (mail)
  (let ((mail (ensure-mail mail)))
    (db:with-transaction ()
      (db:remove 'mail-queue (db:query (:= 'mail (dm:id mail))))
      (db:remove 'mail-log (db:query (:= 'mail (dm:id mail))))
      (db:remove 'mail-receipt (db:query (:= 'mail (dm:id mail))))
      (delete-triggers-for mail)
      (dm:delete mail))))

(defun list-mails (thing &key amount (skip 0) query)
  (macrolet ((query (clause)
               `(if query
                    (let ((query (prepare-query query)))
                      (db:query (:and ,clause
                                      (:or (:matches 'title query)
                                           (:matches 'subject query)
                                           (:matches 'body query)))))
                    (db:query ,clause))))
    (ecase (dm:collection thing)
      (campaign
       (dm:get 'mail (query (:= 'campaign (dm:id thing)))
               :sort '((time :desc)) :amount amount :skip skip))
      (subscriber
       (dm:get (rdb:join (mail _id) (mail-log mail)) (query (:= 'subscriber (dm:id thing)))
               :sort '(("send-time" :desc)) :hull 'mail)))))

(defun make-tag (campaign &key title description (save T))
  (let ((campaign (ensure-campaign campaign)))
    (check-title-exists 'tag title (db:query (:and (:= 'campaign (dm:id campaign))
                                                   (:= 'title title))))
    (dm:with-model tag ('tag NIL)
      (setf-dm-fields tag campaign title description)
      (when save (dm:insert tag))
      tag)))

(defun edit-tag (tag-ish &key title description (save T))
  (let ((tag (ensure-tag tag-ish)))
    (setf-dm-fields tag title description)
    (when save (dm:save tag))
    tag))

(defun ensure-tag (tag-ish)
  (or
   (etypecase tag-ish
     (dm:data-model tag-ish)
     (db:id (dm:get-one 'tag (db:query (:= '_id tag-ish))))
     (string (ensure-tag (db:ensure-id tag-ish))))
   (error 'request-not-found :message "No such tag.")))

(defun delete-tag (tag)
  (db:with-transaction ()
    (db:remove 'tag-table (db:query (:= 'tag (dm:id tag))))
    (delete-triggers-for tag)
    (dm:delete tag)))

(defun list-tags (thing &key amount (skip 0))
  (ecase (dm:collection thing)
    (campaign
     (dm:get 'tag (db:query (:= 'campaign (dm:id thing)))
             :sort '((title :asc)) :amount amount :skip skip))
    (subscriber
     (dm:get (rdb:join (tag _id) (tag-table tag)) (db:query (:= 'subscriber (dm:id thing)))
             :sort '((title :asc)) :amount amount :skip skip :hull 'tag))))

(defun make-trigger (campaign source target &key description (delay 0) tag-constraint (save T))
  (dm:with-model trigger ('trigger NIL)
    (setf-dm-fields trigger campaign description delay tag-constraint)
    (setf (dm:field trigger "normalized-constraint") (normalize-constraint campaign (or tag-constraint "")))
    (setf (dm:field trigger "source-id") (dm:id source))
    (setf (dm:field trigger "source-type") (collection-type source))
    (setf (dm:field trigger "target-id") (dm:id target))
    (setf (dm:field trigger "target-type") (collection-type target))
    (when save (dm:insert trigger))
    trigger))

(defun edit-trigger (trigger &key description source target delay tag-constraint (save T))
  (setf-dm-fields trigger description delay tag-constraint)
  (when tag-constraint
    (setf (dm:field trigger "normalized-constraint") (normalize-constraint (dm:field trigger "campaign") tag-constraint)))
  (when source
    (setf (dm:field trigger "source-id") (dm:id source))
    (setf (dm:field trigger "source-type") (collection-type source)))
  (when target
    (setf (dm:field trigger "target-id") (dm:id target))
    (setf (dm:field trigger "target-type") (collection-type target)))
  (when save (dm:save trigger))
  trigger)

(defun delete-trigger (trigger)
  (let ((trigger (ensure-trigger trigger)))
    (db:with-transaction ()
      (db:remove 'sequence-trigger (db:query (:= 'trigger (dm:id trigger))))
      (dm:delete trigger))))

(defun delete-triggers-for (thing)
  (db:with-transaction ()
    (mapcar #'delete-trigger (dm:get 'trigger (db:query (:or (:and (:= 'target-id (dm:id thing))
                                                                   (:= 'target-type (collection-type thing)))
                                                             (:and (:= 'source-id (dm:id thing))
                                                                   (:= 'source-type (collection-type thing)))))))))

(defun ensure-trigger (trigger-ish)
  (or
   (etypecase trigger-ish
     (dm:data-model trigger-ish)
     (db:id (dm:get-one 'trigger (db:query (:= '_id trigger-ish))))
     (T (ensure-trigger (db:ensure-id trigger-ish))))
   (error 'request-not-found :message "No such trigger.")))

(defun list-triggers (thing &key amount (skip 0))
  (ecase (dm:collection thing)
    (campaign
     (dm:get 'trigger (db:query (:= 'campaign (dm:id thing)))
             :amount amount :skip skip))
    (sequence
     (dm:get (rdb:join (trigger _id) (sequence-trigger trigger))
             (db:query (:= 'sequence (dm:id thing)))
             :amount amount :skip skip :hull 'trigger))
    ((link mail tag)
     (dm:get 'trigger (db:query (:and (:= 'target-id (dm:id thing))
                                      (:= 'target-type (collection-type thing))))
             :amount amount :skip skip))))

(defun list-source-triggers (thing &key amount (skip 0))
  (dm:get 'trigger (db:query (:and (:= 'source-id (dm:id thing))
                                   (:= 'source-type (collection-type thing))))
          :amount amount :skip skip))

(defun make-link (campaign &key url (save T))
  (let ((hash (cryptos:sha256 url :to :base64)))
    (or (dm:get-one 'link (db:query (:and (:= 'campaign (dm:id campaign))
                                          (:= 'hash hash))))
        (dm:with-model link ('link NIL)
          (setf-dm-fields link url hash campaign)
          (when save (dm:insert link))
          link))))

(defun ensure-link (link-ish)
  (or
   (etypecase link-ish
     (dm:data-model link-ish)
     (db:id (dm:get-one 'link (db:query (:= '_id link-ish))))
     (T (ensure-link (db:ensure-id link-ish))))
   (error 'request-not-found :message "No such link.")))

(defun delete-link (link-ish)
  (db:with-transaction ()
    (let ((link (ensure-link link-ish)))
      (db:remove 'link-receipt (db:query (:= link (dm:id link))))
      (delete-triggers-for link)
      (dm:delete link))))

(defun list-links (campaign &key amount (skip 0))
  (dm:get 'link (db:query (:= 'campaign (dm:id campaign)))
          :sort '((url :asc)) :amount amount :skip skip))

(defun link-received-p (link subscriber)
  (< 0 (db:count 'link-receipt (db:query (:and (:= 'link (ensure-id link))
                                               (:= 'subscriber (ensure-id subscriber)))))))

(defun link-coverage (link)
  (/ (db:count 'link-receipt (db:query (:= 'link (dm:id link))))
     (db:count 'subscriber (db:query (:= 'campaign (dm:field link "campaign"))))))

(defun mark-link-received (link subscriber)
  (db:with-transaction ()
    (unless (link-received-p link subscriber)
      (db:insert 'link-receipt `(("link" . ,(ensure-id link))
                                 ("subscriber" . ,(ensure-id subscriber))
                                 ("time" . ,(get-universal-time))))
      (process-triggers subscriber link))))

(defun mail-received-p (mail subscriber)
  (< 0 (db:count 'mail-receipt (db:query (:and (:= 'mail (ensure-id mail))
                                               (:= 'subscriber (ensure-id subscriber)))))))

(defun mail-sent-p (mail subscriber)
  (let ((query (db:query (:and (:= 'mail (ensure-id mail))
                               (:= 'subscriber (ensure-id subscriber))))))
    (or (< 0 (db:count 'mail-log query))
        (< 0 (db:count 'mail-queue query)))))

(defun mail-coverage (mail)
  (let ((sent (db:count 'mail-log (db:query (:= 'mail (dm:id mail)))))
        (read (db:count 'mail-receipt (db:query (:= 'mail (dm:id mail))))))
    (if (= 0 sent) 0
        (/ read sent))))

(defun mail-sent-count (thing)
  (ecase (dm:collection thing)
    (mail
     (db:count 'mail-log (db:query (:= 'mail (dm:id thing)))))
    (subscriber
     (db:count 'mail-log (db:query (:= 'subscriber (dm:id thing)))))))

(defun mark-mail-received (mail subscriber)
  (db:with-transaction ()
    (unless (mail-received-p mail subscriber)
      (db:insert 'mail-receipt `(("mail" . ,(ensure-id mail))
                                 ("subscriber" . ,(ensure-id subscriber))
                                 ("time" . ,(get-universal-time))))
      (process-triggers subscriber mail))))

(defun mark-mail-sent (mail subscriber &optional (status :success))
  (db:insert 'mail-log `(("mail" . ,(dm:id mail))
                         ("subscriber" . ,(dm:id subscriber))
                         ("send-time" . ,(get-universal-time))
                         ("status" . ,(mail-status-id status)))))

(defun tagged-p (subscriber tag)
  (< 0 (db:count 'tag-table (db:query (:and (:= 'subscriber (ensure-id subscriber))
                                            (:= 'tag (ensure-id tag)))))))

(defun tag (subscriber tag)
  (db:with-transaction ()
    (unless (tagged-p subscriber tag)
      (db:insert 'tag-table `(("tag" . ,(ensure-id tag))
                              ("subscriber" . ,(ensure-id subscriber))))
      (process-triggers subscriber tag))))

(defun file-pathname (file)
  (make-pathname :name (princ-to-string (dm:id file))
                 :type (trivial-mimes:mime-file-type (dm:field file "mime-type"))
                 :defaults (campaign-file-directory (dm:field file "campaign"))))

(defun make-file (campaign file mime-type &key (filename (file-namestring file)) (author (auth:current)))
  (db:with-transaction ()
    (let ((model (dm:hull 'file)))
      (setf-dm-fields model campaign author mime-type filename)
      (dm:insert model)
      (ensure-directories-exist (file-pathname model))
      (alexandria:copy-file file (file-pathname model) :if-to-exists :error)
      model)))

(defun ensure-file (file-ish)
  (or
   (etypecase file-ish
     (dm:data-model file-ish)
     (T (dm:get-one 'file (db:query (:= '_id (db:ensure-id file-ish))))))
   (error 'request-not-found :message "No such file.")))

(defun delete-file (file)
  (db:with-transaction ()
    (let* ((file (ensure-file file)))
      (cl:delete-file (file-pathname file))
      (dm:delete file))))

(defun list-files (campaign &key amount (skip 0))
  (dm:get 'file (db:query (:= 'campaign (dm:id campaign)))
          :amount amount :skip skip))

(defun ensure-sequence (sequence-ish)
  (or
   (etypecase sequence-ish
     (dm:data-model sequence-ish)
     (T (dm:get-one 'sequence (db:query (:= '_id (db:ensure-id sequence-ish))))))
   (error 'request-not-found :message "No such sequence.")))

(defun list-sequences (campaign &key amount (skip 0))
  (dm:get 'sequence (db:query (:= 'campaign (ensure-id campaign)))
          :amount amount :skip skip))

(defun make-sequence (campaign title &key triggers (save T))
  (let ((sequence (dm:hull 'sequence)))
    (setf-dm-fields sequence campaign title)
    (when save
      (db:with-transaction ()
        (dm:insert sequence)
        (loop for trigger in triggers
              for i from 1
              do (etypecase trigger
                   (dm:data-model
                    (db:insert 'sequence-trigger `(("sequence" . ,(dm:id sequence))
                                                   ("trigger" . ,(dm:id trigger)))))
                   (cons
                    (destructuring-bind (delay subject) trigger
                      (let* ((title (format NIL "~a - ~a" title i))
                             (mail (make-mail campaign :title title :subject subject))
                             (trigger (make-trigger campaign campaign mail :description title :delay delay)))
                        (db:insert 'sequence-trigger `(("sequence" . ,(dm:id sequence))
                                                       ("trigger" . ,(dm:id trigger)))))))))))
    sequence))

(defun edit-sequence (sequence-ish &key title triggers (save T))
  (let ((sequence (ensure-sequence sequence-ish)))
    (setf-dm-fields sequence title)
    (when save
      (db:with-transaction ()
        (dm:save sequence)
        (db:remove 'sequence-trigger (db:query (:= 'sequence (dm:id sequence))))
        (loop with campaign = (ensure-campaign (dm:field sequence "campaign"))
              for (id delay subject) in triggers
              for i from 0
              for trigger = (cond (id
                                   (let ((trigger (ensure-trigger id)))
                                     (edit-trigger trigger :delay delay)
                                     (edit-mail (dm:field trigger "target-id") :subject subject)
                                     trigger))
                                  (T
                                   (let* ((title (format NIL "~a - ~a" title i))
                                          (mail (make-mail campaign :title title :subject subject)))
                                     (make-trigger campaign campaign mail :description title :delay delay))))
              do (db:insert 'sequence-trigger `(("sequence" . ,(dm:id sequence))
                                                ("trigger" . ,(dm:id trigger)))))))
    sequence))

(defun delete-sequence (sequence-ish)
  (let ((sequence (ensure-sequence sequence-ish)))
    (db:with-transaction ()
      (mapcar #'delete-trigger (list-triggers sequence))
      (dm:delete sequence))))

(defun subscriber-count (thing)
  (ecase (dm:collection thing)
    (campaign (db:count 'subscriber (db:query (:= 'campaign (dm:id thing)))))
    (tag (db:count 'tag-table (db:query (:= 'tag (dm:id thing)))))))

(defun mail-count (thing)
  (ecase (dm:collection thing)
    (campaign (db:count 'mail (db:query (:= 'campaign (dm:id thing)))))))

(defun mail-status-id (status)
  (ecase status
    (:success 0)
    (:unlocked 1)
    (:failed 10)
    (:send-failed 11)
    (:compile-failed 12)
    ((0 1 10 11 12) status)))

(defun id-mail-status (id)
  (ecase id
    (0 :success)
    (1 :unlocked)
    (10 :failed)
    (11 :send-failed)
    (12 :compile-failed)))

(defun user-status-id (status)
  (ecase status
    (:unconfirmed 0)
    (:active 1)
    (:deactivated 2)
    ((0 1 2) status)))

(defun id-user-status (id)
  (ecase id
    (0 :unconfirmed)
    (1 :active)
    (2 :deactivated)))

(defun collection-type (collection)
  (ecase (etypecase collection
           (symbol collection)
           (dm:data-model (dm:collection collection)))
    (mail 0)
    (link 1)
    (tag 2)
    (subscriber 3)
    (campaign 4)
    (file 5)
    (sequence 6)
    (trigger 7)
    (host 8)))

(defun type-collection (type)
  (ecase type
    ((0 10 mail) 'mail)
    ((1 link) 'link)
    ((2 tag) 'tag)
    ((3 subscriber) 'subscriber)
    ((4 campaign) 'campaign)
    ((5 file) 'file)
    ((6 sequence) 'sequence)
    ((7 trigger) 'trigger)
    ((8 host) 'host)))

(defun resolve-typed (type id)
  (let ((id (db:ensure-id id)))
    (dm:get-one (type-collection
                 (etypecase type
                   ((or symbol integer) type)
                   (string (parse-integer type))))
                (db:query (:= '_id id)))))

(defun check-accessible (dm &key (target (dm:collection dm)) (user (auth:current)))
  (labels ((check (author)
             (unless (equal (user:id user) author)
               (error 'radiance:request-denied :message (format NIL "You do not own the ~a you were trying to access."
                                                                (dm:collection dm)))))
           (check-campaign (campaign)
             (let* ((campaign (ensure-campaign campaign))
                    (record (db:select 'campaign-access
                                       (db:query (:and (:= 'campaign (dm:id campaign))
                                                       (:= 'user (user:id user))))
                                       :amount 1 :fields '(access-field)))
                    (access-field (if record
                                      (gethash "access-field" (first record))
                                      0)))
               (unless (or (equal (user:id user) (dm:field campaign "author"))
                           (etypecase target
                             (symbol (logbitp (collection-type target) access-field))
                             (integer (< target (access-level access-field)))))
                 (error 'radiance:request-denied :message (format NIL "You do not have permission to access ~as." target))))))
    ;; FIXME: extended author intent checks
    (ecase (dm:collection dm)
      (host
       (check (dm:field dm "author")))
      (campaign
       (check-campaign dm))
      ((mail tag trigger link subscriber file sequence)
       (check-campaign (dm:field dm "campaign"))))
    dm))

(defun access-level (access-field)
  (cond ((logbitp (collection-type 'campaign) access-field) 4)
        ((logbitp (collection-type 'subscriber) access-field) 3)
        ((logbitp (collection-type 'trigger) access-field) 2)
        ((logbitp (collection-type 'mail) access-field) 1)
        (T 0)))

(defun access-field (access-level)
  (let ((field 0))
    (macrolet ((set-bit (i)
                 `(setf field (logior field (ash 1 ,i)))))
      (when (< 0 access-level)
        (set-bit (collection-type 'mail))
        (set-bit (collection-type 'link))
        (set-bit (collection-type 'file)))
      (when (< 1 access-level)
        (set-bit (collection-type 'tag))
        (set-bit (collection-type 'trigger))
        (set-bit (collection-type 'sequence)))
      (when (< 2 access-level)
        (set-bit (collection-type 'subscriber)))
      (when (< 3 access-level)
        (set-bit (collection-type 'campaign)))
      field)))
