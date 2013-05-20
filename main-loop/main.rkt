#lang racket/base
;
; Generic Main Loop For Racket
;

(require racket/contract
         racket/function
         racket/match
         racket/set)

(provide add-event-handler
         remove-event-handler
         cancel-event
         call-later)


(define-struct/contract watch
  ((event evt?)
   (handlers (set/c (-> void?))))
  #:transparent
  #:mutable)


(define looping-thread
  (thread
    (thunk
      ; Event that signalizes this thread have some inbound messages.
      (define inbox-evt (thread-receive-evt))

      ; All registered watches.
      (define/contract watches (hash/c evt? watch?)
        (make-hasheq `((,inbox-evt . ,(make-watch inbox-evt (set))))))

      ; Endlessly consume events as they come in.
      (for ((event (in-producer (thunk (apply sync (hash-keys watches))) #f)))

        ; We need to process incoming messages first.
        (for ((message (in-producer thread-try-receive #f)))
          (match message
            ((list 'add-handler (var event) (var handler))
             (let* ((watch (hash-ref! watches event
                                      (thunk (make-watch event (set)))))
                    (handlers (watch-handlers watch)))
               (set-watch-handlers! watch (set-add handlers handler))))

            ((list 'remove-handler (var event) (var handler))
             (when (hash-has-key? watches event)
               (let* ((watch (hash-ref watches event))
                      (handlers (watch-handlers watch)))
                 (set-watch-handlers! watch (set-remove handlers handler))
                 (when (set-empty? (watch-handlers watch))
                   (hash-remove! watches event)))))

             ((list 'cancel (var event))
              (when (hash-has-key? watches event)
                (hash-remove! watches event)))))

        ; Then we can try to process the event.
        (when (hash-has-key? watches event)
          (let ((watch (hash-ref watches event)))
            (for ((handler (in-set (watch-handlers watch))))
                 (with-handlers ((exn:fail? (lambda (exn)
                                              ((error-display-handler)
                                               (exn-message exn) exn))))
                   (handler)))))))))


(define/contract (add-event-handler event handler)
                 (-> evt? (-> void?) void?)
  (thread-send looping-thread `(add-handler ,event ,handler)))


(define/contract (remove-event-handler event handler)
                 (-> evt? (-> void?) void?)
  (thread-send looping-thread `(remove-handler ,event ,handler)))


(define/contract (cancel-event event)
                 (-> evt? void?)
  (thread-send looping-thread `(cancel ,event)))


(define/contract (call-later handler)
                 (-> (-> void?) void?)
  (define (wrapper)
    (remove-event-handler always-evt wrapper)
    (handler))
  (thread-send looping-thread `(add-handler ,always-evt ,wrapper)))


; vim:set ts=2 sw=2 et:
