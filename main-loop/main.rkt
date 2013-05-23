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


; Semaphore protecting watches, since hash table is a bit unsafe.
(define/contract watches-semaphore semaphore?
  (make-semaphore 1))

; All registered watches.
(define/contract watches (hash/c evt? watch?)
  (make-hasheq))


(define looping-thread
  (thread
    (thunk
      ; Event that signalizes this thread have some inbound messages.
      (define inbox-evt (thread-receive-evt))

      ; Subscribe to this event so that we can re-wait when watches change.
      (hash-set! watches inbox-evt (make-watch inbox-evt (set)))

      ; Endlessly consume events as they come in.
      (for ((event (in-producer (thunk (apply sync (hash-keys watches))) #f)))
        ; We need to process incoming messages that might have awoken us.
        (for ((message (in-producer thread-try-receive #f)))
          (void message))

        ; Then we can try to process the event.
        (for ((handler (in-set (call-with-semaphore watches-semaphore
                                 (thunk
                                   (let ((w (hash-ref watches event #f)))
                                     (if w (watch-handlers w) (set))))))))
          (with-handlers ((exn:fail? (lambda (exn) ((error-display-handler)
                                                    (exn-message exn) exn))))
            (handler)))))))


(define/contract (add-event-handler event handler)
                 (-> evt? (-> void?) void?)
  (call-with-semaphore watches-semaphore
    (thunk
      (let* ((watch (hash-ref! watches event (thunk (make-watch event (set)))))
             (handlers (watch-handlers watch)))
        (set-watch-handlers! watch (set-add handlers handler)))))
  (thread-send looping-thread #t))


(define/contract (remove-event-handler event handler)
                 (-> evt? (-> void?) void?)
  (call-with-semaphore watches-semaphore
    (thunk
      (when (hash-has-key? watches event)
        (let* ((watch (hash-ref watches event))
               (handlers (watch-handlers watch)))
          (set-watch-handlers! watch (set-remove handlers handler))
          (when (set-empty? (watch-handlers watch))
            (hash-remove! watches event))))))
  (thread-send looping-thread #t))


(define/contract (cancel-event event)
                 (-> evt? void?)
  (call-with-semaphore watches-semaphore
    (thunk
      (hash-remove! watches event)))
  (thread-send looping-thread #t))


(define/contract (call-later handler)
                 (-> (-> void?) void?)
  (define (wrapper)
    (remove-event-handler always-evt wrapper)
    (handler))
  (add-event-handler always-evt wrapper))


; vim:set ts=2 sw=2 et:
