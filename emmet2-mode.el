(defun emmet2-expand ()
  (interactive)
  (let* ((bounds (bounds-of-thing-at-point 'line)))
    (when bounds
      (let ((input (buffer-substring-no-properties (car bounds) (cdr bounds))))
        (print input)
        (delete-region (car bounds) (cdr bounds))
        (insert "[TODO]")))))
