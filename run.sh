#!/bin/bash

bundle install
echo "done"
bundle exec jekyll serve --watch --force_polling --verbose --drafts --host 0.0.0.0 --port 4000