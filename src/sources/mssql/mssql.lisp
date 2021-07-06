;;;
;;; Tools to handle the MS SQL Database
;;;

(in-package :pgloader.source.mssql)

;;;
;;; Implement the specific methods
;;;
(defmethod concurrency-support ((mssql copy-mssql) concurrency)
  "Splits the read work thanks WHERE clauses when possible and relevant,
   return nil if we decide to read all in a single thread, and a list of as
   many copy-mssql instances as CONCURRENCY otherwise. Each copy-mssql
   instance in the returned list embeds specifications about how to read
   only its partition of the source data."
  (log-message :debug "@@@ concurrency ~a" concurrency)
  (unless (= 1 concurrency)
    (let* ((indexes (table-index-list (target mssql)))
           (pkey    (first (remove-if-not #'index-primary indexes)))
           (pcol    (when pkey (first (index-columns pkey))))
           (coldef  (when pcol
                      (find pcol
                            (table-column-list (target mssql))
                            :key #'column-name
                            :test #'string=)))
           (ptype   (when (and coldef (stringp (column-type-name coldef)))
                      (column-type-name coldef))))
      (when (member ptype (list "integer" "bigint" "serial" "bigserial")
                    :test #'string=)
        ;; the table has a primary key over a integer data type we are able
        ;; to generate WHERE clause and range index scans.
        (with-connection (*mssql-db* (source-db mssql))
          (let* ((col (mssql-column-name
                       (nth (position coldef (table-column-list (target mssql)))
                            (fields mssql))))
                 (sql (format nil "select min(`~a`), max(`~a`) + 1 from `~a`"
                              col col (table-source-name (source mssql)))))
            (destructuring-bind (min max)
                (let ((result (first (mssql-query sql))))
                  ;; result is (min max), or (nil nil) if table is empty
                  (if (or (null (first result))
                          (null (second result)))
                      result
                      (mapcar #'parse-integer result)))
              ;; generate a list of ranges from min to max
              (when (and min max)
                (let ((range-list (split-range min max *rows-per-range*)))
                  (unless (< (length range-list) concurrency)
                    ;; affect those ranges to each reader, we have CONCURRENCY
                    ;; of them
                    (let ((partitions (distribute range-list concurrency)))
                      (loop :for part :in partitions :collect
                         (log-message :debug "@@@ col ~a" col)
                         (log-message :debug "@@@ part ~a" part)
                         (make-instance 'copy-mssql
                                        :source-db  (clone-connection
                                                     (source-db mssql))
                                        :target-db  (target-db mssql)
                                        :source     (source mssql)
                                        :target     (target mssql)
                                        :fields     (fields mssql)
                                        :columns    (columns mssql)
                                        :transforms (transforms mssql)
                                        :encoding   (encoding mssql)
                                        :range-list (cons col part))))))))))))))

(defun call-with-encoding-handler (copy-mssql table-name func)
  (handler-bind
      ((babel-encodings:end-of-input-in-character
        #'(lambda (c)
            (update-stats :data (target copy-mssql) :errs 1)
            (log-message :error "~a" c)
            (invoke-restart 'mssql::use-nil)))

       (babel-encodings:character-decoding-error
        #'(lambda (c)
            (update-stats :data (target copy-mssql) :errs 1)
            (let* ((encoding (babel-encodings:character-coding-error-encoding c))
                  (position  (babel-encodings:character-coding-error-position c))
                  (buffer    (babel-encodings:character-coding-error-buffer c))
                  (character
                    (when (and position (< position (length buffer)))
                      (aref buffer position))))
              (log-message :error
                           "While decoding text data from MSSQL table ~s: ~%~
Illegal ~a character starting at position ~a~@[: ~a~].~%"
                           table-name encoding position character))
            (invoke-restart 'mssql::use-nil))))
    (funcall func)))

(defmacro with-encoding-handler ((copy-mssql table-name) &body forms)
  `(call-with-encoding-handler ,copy-mssql ,table-name (lambda () ,@forms)))

(defmethod map-rows ((mssql copy-mssql) &key process-row-fn)
  "Extract Mssql data and call PROCESS-ROW-FN function with a single
   argument (a list of column values) for each row."
  (let ((table-name (table-source-name (source mssql)))
        (schema-name (table-schema (source mssql))))

    (with-connection (*mssql-db* (source-db mssql))
      (let* ((cols (get-column-list mssql))
             (sql  (format nil "SELECT ~{~a~^, ~} FROM [~a].[~a]" cols schema-name table-name)))
        (log-message :debug "~a" sql)

        (if (range-list mssql)
            ;; read a range at a time, in a loop
            (destructuring-bind (colname . ranges) (range-list mssql)
              (loop :for (min max) :in ranges :do
                 (let ((sql (format nil "~a WHERE `~a` >= ~a AND `~a` < ~a"
                                    sql colname min colname max)))
                   (with-encoding-handler (mssql table-name)
                     (mssql::map-query-results sql
                                               :row-fn process-row-fn
                                               :connection (conn-handle *mssql-db*))))))

              ;; read it all, no WHERE clause
              (with-encoding-handler (mssql table-name)
                (mssql::map-query-results sql
                                          :row-fn process-row-fn
                                          :connection (conn-handle *mssql-db*))))))))

(defmethod copy-column-list ((mssql copy-mssql))
  "We are sending the data in the MSSQL columns ordering here."
  (mapcar #'apply-identifier-case (mapcar #'mssql-column-name (fields mssql))))

(defmethod fetch-metadata ((mssql copy-mssql)
                           (catalog catalog)
                           &key
                             materialize-views
                             create-indexes
                             foreign-keys
                             including
                             excluding)
  "MS SQL introspection to prepare the migration."
  (with-stats-collection ("fetch meta data"
                          :use-result-as-rows t
                          :use-result-as-read t
                          :section :pre)
    (with-connection (*mssql-db* (source-db mssql))
      ;; If asked to MATERIALIZE VIEWS, now is the time to create them in MS
      ;; SQL, when given definitions rather than existing view names.
      (when (and materialize-views (not (eq :all materialize-views)))
        (create-matviews materialize-views mssql))

      (fetch-columns catalog mssql
                     :including including
                     :excluding excluding)

      ;; fetch view (and their columns) metadata, covering comments too
      (let* ((view-names (unless (eq :all materialize-views)
                           (mapcar #'matview-source-name materialize-views)))
             (including
              (loop :for (schema-name . view-name) :in view-names
                 :do (let* ((schema-name (or schema-name "dbo"))
                            (schema-entry
                             (or (assoc schema-name including :test #'string=)
                                 (progn (push (cons schema-name nil) including)
                                        (assoc schema-name including
                                               :test #'string=)))))
                       (push-to-end view-name (cdr schema-entry))))))
        (cond (view-names
               (fetch-columns catalog mssql
                              :including including
                              :excluding excluding
                              :table-type :view))

              ((eq :all materialize-views)
               (fetch-columns catalog mssql :table-type :view))))

      (when create-indexes
        (fetch-indexes catalog mssql
                       :including including
                       :excluding excluding))

      (when foreign-keys
        (fetch-foreign-keys catalog mssql
                            :including including
                            :excluding excluding))

      ;; return how many objects we're going to deal with in total
      ;; for stats collection
      (+ (count-tables catalog)
         (count-views catalog)
         (count-indexes catalog)
         (count-fkeys catalog))))

  ;; be sure to return the catalog itself
  catalog)


(defmethod cleanup ((mssql copy-mssql) (catalog catalog) &key materialize-views)
  "When there is a PostgreSQL error at prepare-pgsql-database step, we might
   need to clean-up any view created in the MS SQL connection for the
   migration purpose."
  (when materialize-views
    (with-connection (*mssql-db* (source-db mssql))
      (drop-matviews materialize-views mssql))))
