#|
 This file is a part of Courier
 (c) 2019 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(asdf:defsystem #:courier
  :defsystem-depends-on (:radiance)
  :class "radiance:virtual-module"
  :author "Nicolas Hafner <shinmera@tymoon.eu>"
  :maintainer "Nicolas Hafner <shinmera@tymoon.eu>"
  :version "1.2.0"
  :license "Artistic"
  :description "An email marketing service for Radiance"
  :homepage "https://shirakumo.github.io/courier/"
  :bug-tracker "https://github.com/shirakumo/courier/issues"
  :source-control (:git "https://github.com/shirakumo/courier.git")
  :serial T
  :components ((:file "module")
               (:file "db"))
  :depends-on ((:interface :database)
               (:interface :auth)
               :r-data-model
               :r-clip
               :cl-markless-plump
               :cl-smtp))
