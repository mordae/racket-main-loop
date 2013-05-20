# Main Loop

You probably do not want to use this piece of code for anything,
but it may come in handy when you are writing bindings for C libraries
that need to integrate into your main loop.


## Examples

```racket
; Call thunk once later on.
(call-later
  (thunk
    (printf "A bit late hello!\n")))

; Run handler every time an event is ready.
; In this case, cause a cool infinite loop!
(add-event-handler always-evt
  (thunk
    (printf "Looooooping!\n")))

; Since it's looping on the background, we can stop it like this:
(cancel-event always-evt)

; Otherwise we would just unregister the handler (not that useful).
(remove-event-handler always-evt some-thunk)
```
