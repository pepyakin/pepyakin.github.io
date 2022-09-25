open:
  open http://localhost:1313/

live:
  hugo server -D

publish:
  hugo

new name:
  hugo new posts/{{name}}/index.md
